import AVFoundation
import Foundation
import Observation
import Speech

enum AudioServiceError: LocalizedError, Equatable {
    case microphoneDenied
    case recordingAlreadyStarted
    case recordingNotStarted
    case recordingFailed
    case recordingNeedsRecovery
    case missingAudio
    case unreadableAudio
    case emptyAudio
    case playbackFailed
    case transcriptionAlreadyStarted
    case speechUnavailable
    case unsupportedLanguage
    case modelNotInstalled
    case noRecognizedSpeech

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "未获得麦克风权限。请在系统设置的‘隐私与安全性 → 麦克风’中允许印迹录音，也可以导入已有音频。"
        case .recordingAlreadyStarted: "正在录音，请先结束当前录音。"
        case .recordingNotStarted: "当前没有正在进行的录音。"
        case .recordingFailed: "录音未能开始。请检查输入设备后重试，也可以导入已有音频。"
        case .recordingNeedsRecovery: "上一段原声尚未完成保存，请先重试保存，或明确放弃这段原声。"
        case .missingAudio: "找不到原始音频，请重新选择文件。"
        case .unreadableAudio: "无法读取此音频。请使用系统支持的音频文件，例如 M4A、WAV 或 AIFF。"
        case .emptyAudio: "音频中没有可读取的声音，请重新录音或选择其他文件。"
        case .playbackFailed: "音频未能播放。原始文件已保留，请检查文件后重试。"
        case .transcriptionAlreadyStarted: "正在转写一段音频，请等待完成或取消。"
        case .speechUnavailable: "这台 Mac 暂不支持设备端语音转写。原声已保留，可以手动补充文字。"
        case .unsupportedLanguage: "设备端转写暂不支持所选语言。原声已保留，可以手动补充文字。"
        case .modelNotInstalled:
            "设备端中文语音模型尚未就绪。原声已保留；可稍后重试或手动补充文字。印迹不会上传录音或自动下载模型。"
        case .noRecognizedSpeech: "没有识别到可转写的文字。原声已保留，可以重试或手动补充。"
        }
    }
}

/// The recording, playback and transcription state belongs to the editor or review
/// session that owns this service. No microphone permission is requested at launch.
@MainActor
@Observable
final class AudioService {
    private(set) var isRecording = false
    private(set) var isPlaying = false
    private(set) var transcriptionInProgress = false
    private(set) var isPreparingModel = false
    private(set) var playingURL: URL?
    private(set) var recoverableRecordingURL: URL?
    var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var pendingRecordingToken: UUID?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var delegate: AudioServiceDelegate?

    func startRecording() async throws {
        guard recoverableRecordingURL == nil else { throw report(.recordingNeedsRecovery) }
        guard !isRecording, pendingRecordingToken == nil else { throw report(.recordingAlreadyStarted) }
        let requestToken = UUID()
        pendingRecordingToken = requestToken
        defer { if pendingRecordingToken == requestToken { pendingRecordingToken = nil } }
        errorMessage = nil
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined: granted = await AVCaptureDevice.requestAccess(for: .audio)
        default: granted = false
        }
        guard granted else { throw report(.microphoneDenied) }
        try Task.checkCancellation()
        guard pendingRecordingToken == requestToken else { throw CancellationError() }
        stopPlayback()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperingTime录音", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            recorder.delegate = serviceDelegate
            guard recorder.prepareToRecord(), recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                throw AudioServiceError.recordingFailed
            }
            self.recorder = recorder
            recordingURL = url
            isRecording = true
        } catch {
            errorMessage = AudioServiceError.recordingFailed.localizedDescription
            throw AudioServiceError.recordingFailed
        }
    }

    /// The returned temporary original survives service teardown. The caller copies
    /// it into its attachment store before discarding it; ASR never deletes it.
    func stopRecording() throws -> URL {
        guard let recorder, let url = recordingURL, isRecording else {
            throw report(.recordingNotStarted)
        }
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        isRecording = false
        return try retainStoppedRecording(at: url)
    }

    func cancelRecording() {
        pendingRecordingToken = nil
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        isRecording = false
    }

    /// A stopped original is kept independently of the active recorder. In
    /// particular, closing an editor must not silently discard failed imports.
    func retainStoppedRecording(at url: URL) throws -> URL {
        if let recoverableRecordingURL, recoverableRecordingURL != url {
            throw report(.recordingNeedsRecovery)
        }
        if FileManager.default.fileExists(atPath: url.path) { recoverableRecordingURL = url }
        do {
            try Self.validateAudio(at: url)
            return url
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Call only after the attachment copy AND its record reference are committed.
    func acknowledgeRecordingSaved() {
        if let recoverableRecordingURL { try? FileManager.default.removeItem(at: recoverableRecordingURL) }
        recoverableRecordingURL = nil
    }

    func discardRecoverableRecording() throws {
        guard let url = recoverableRecordingURL else { return }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        recoverableRecordingURL = nil
    }

    func isPlaying(url: URL) -> Bool {
        isPlaying && playingURL?.standardizedFileURL == url.standardizedFileURL
    }

    func play(url: URL) throws {
        stopPlayback()
        errorMessage = nil
        do {
            try Self.validateAudio(at: url)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = serviceDelegate
            guard player.prepareToPlay(), player.play() else { throw AudioServiceError.playbackFailed }
            self.player = player
            isPlaying = true
            playingURL = url.standardizedFileURL
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func stopPlayback() {
        player?.delegate = nil
        player?.stop()
        player = nil
        isPlaying = false
        playingURL = nil
    }

    func transcribe(url: URL, locale: Locale = Locale(identifier: "zh_CN")) async throws -> String {
        guard !transcriptionInProgress else { throw report(.transcriptionAlreadyStarted) }
        transcriptionInProgress = true
        errorMessage = nil
        defer { transcriptionInProgress = false }

        let work = Task.detached(priority: .userInitiated) {
            try await Self.transcribeLocally(url: url, locale: locale)
        }
        do {
            return try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            errorMessage = "转写未完成：\(error.localizedDescription) 原声仍然保留，可以重试或手动补充。"
            throw error
        }
    }

    /// This is the only method allowed to download model assets, and is invoked
    /// by an explicit user action. It downloads Apple's model, never audio.
    func prepareChineseModel() async throws {
        guard !isPreparingModel else { return }
        isPreparingModel = true
        errorMessage = nil
        defer { isPreparingModel = false }
        do {
            guard SpeechTranscriber.isAvailable else { throw AudioServiceError.speechUnavailable }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh_CN")) else {
                throw AudioServiceError.unsupportedLanguage
            }
            try Task.checkCancellation()
            try await AssetInventory.reserve(locale: locale)
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            if await AssetInventory.status(forModules: [transcriber]) != .installed {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            }
            try Task.checkCancellation()
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw AudioServiceError.modelNotInstalled
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            errorMessage = "中文转写模型未准备完成：\(error.localizedDescription) 原声不会上传，可以稍后重试。"
            throw error
        }
    }

    /// AVAudioFile only opens the header here; SpeechAnalyzer streams the original
    /// file through its file-input API, handling compatible sample-rate conversion.
    nonisolated static func validateAudio(at url: URL) throws {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw AudioServiceError.missingAudio
        }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch { throw AudioServiceError.unreadableAudio }
        guard file.length > 0, file.processingFormat.sampleRate > 0 else {
            throw AudioServiceError.emptyAudio
        }
    }

    nonisolated private static func transcribeLocally(url: URL, locale: Locale) async throws -> String {
        try Task.checkCancellation()
        try validateAudio(at: url)
        guard SpeechTranscriber.isAvailable else { throw AudioServiceError.speechUnavailable }
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AudioServiceError.unsupportedLanguage
        }
        // A language installed by the system is not available to this app until
        // the app reserves it. Reservation itself never downloads model data.
        try await AssetInventory.reserve(locale: supportedLocale)
        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw AudioServiceError.modelNotInstalled
        }
        try Task.checkCancellation()

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task {
            var segments: [String] = []
            for try await result in transcriber.results {
                try Task.checkCancellation()
                segments.append(String(result.text.characters))
            }
            return segments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            return try await withTaskCancellationHandler {
                let file = try AVAudioFile(forReading: url)
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                let text = try await results.value
                try Task.checkCancellation()
                guard !text.isEmpty else { throw AudioServiceError.noRecognizedSpeech }
                return text
            } onCancel: {
                results.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private var serviceDelegate: AudioServiceDelegate {
        if let delegate { return delegate }
        let delegate = AudioServiceDelegate(owner: self)
        self.delegate = delegate
        return delegate
    }

    private func report(_ error: AudioServiceError) -> AudioServiceError {
        errorMessage = error.localizedDescription
        return error
    }

    fileprivate func playbackFinished(id: ObjectIdentifier, success: Bool) {
        guard let player, ObjectIdentifier(player) == id else { return }
        self.player = nil
        isPlaying = false
        playingURL = nil
        if !success { errorMessage = AudioServiceError.playbackFailed.localizedDescription }
    }

    fileprivate func recordingFailed(id: ObjectIdentifier, _ error: String?) {
        guard let recorder, ObjectIdentifier(recorder) == id else { return }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        if let recordingURL, FileManager.default.fileExists(atPath: recordingURL.path) {
            recoverableRecordingURL = recordingURL
        }
        recordingURL = nil
        // Keep the partial source file for diagnosis or recovery; it is never
        // silently treated as a successfully saved attachment.
        errorMessage = error ?? AudioServiceError.recordingFailed.localizedDescription
    }
}

@MainActor
private final class AudioServiceDelegate: NSObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    weak var owner: AudioService?

    init(owner: AudioService) { self.owner = owner }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.owner?.playbackFinished(id: id, success: flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.owner?.playbackFinished(id: id, success: false) }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let message = error?.localizedDescription
        let id = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in self?.owner?.recordingFailed(id: id, message) }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            let id = ObjectIdentifier(recorder)
            Task { @MainActor [weak self] in self?.owner?.recordingFailed(id: id, nil) }
        }
    }
}
