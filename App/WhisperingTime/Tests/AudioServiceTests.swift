import AVFoundation
import XCTest
@testable import WhisperingTime

@MainActor
final class AudioServiceTests: XCTestCase {
    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperingTimeAudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    func testUnreadableImportedAudioRetainsOriginalBytes() async throws {
        try await withDirectory { directory in
            let url = directory.appendingPathComponent("损坏的录音.m4a")
            let original = Data("并不是音频，但需要保留以便用户重选。".utf8)
            try original.write(to: url)
            let service = AudioService()
            do {
                _ = try await service.transcribe(url: url)
                XCTFail("Unreadable audio must not produce a successful transcript")
            } catch {
                XCTAssertEqual(error as? AudioServiceError, .unreadableAudio)
            }
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(service.transcriptionInProgress)
            XCTAssertNotNil(service.errorMessage)
            XCTAssertFalse(service.isRecording)
        }
    }

    func testHeaderOnlyAudioIsRejectedAndRetained() async throws {
        try await withDirectory { directory in
            let url = directory.appendingPathComponent("空录音.wav")
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            do { _ = try AVAudioFile(forWriting: url, settings: format.settings) }
            XCTAssertThrowsError(try AudioService.validateAudio(at: url)) { error in
                XCTAssertEqual(error as? AudioServiceError, .emptyAudio)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testMissingAudioDoesNotStartPlaybackOrRecording() throws {
        let service = AudioService()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try service.play(url: url)) { error in
            XCTAssertEqual(error as? AudioServiceError, .missingAudio)
        }
        XCTAssertFalse(service.isPlaying)
        XCTAssertFalse(service.isRecording)
        XCTAssertNotNil(service.errorMessage)
    }

    func testCancelledTranscriptionResetsStateWithoutChangingSource() async throws {
        try await withDirectory { directory in
            let url = directory.appendingPathComponent("可取消的原声.wav")
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
            buffer.frameLength = 1_600
            for frame in 0..<1_600 { buffer.floatChannelData?[0][frame] = 0 }
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            let original = try Data(contentsOf: url)
            let service = AudioService()
            let task = Task { try await service.transcribe(url: url) }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Cancelled work must not return a transcript")
            } catch is CancellationError {
                // Cancellation is an ordinary editor action, not a saved error.
            } catch {
                XCTFail("Expected cancellation, got \(error)")
            }
            XCTAssertFalse(service.transcriptionInProgress)
            XCTAssertNil(service.errorMessage)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testStoppingWithoutRecordingProvidesRecoverableError() throws {
        let service = AudioService()
        XCTAssertThrowsError(try service.stopRecording()) { error in
            XCTAssertEqual(error as? AudioServiceError, .recordingNotStarted)
        }
        service.cancelRecording()
        service.stopPlayback()
        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(service.isPlaying)
    }

    private func makeSilentAudio(at url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        for frame in 0..<16_000 { buffer.floatChannelData?[0][frame] = 0 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    func testStoppedOriginalSurvivesFailedImportAndEditorCancellation() async throws {
        try await withDirectory { directory in
            let original = directory.appendingPathComponent("已结束的原声.wav")
            try makeSilentAudio(at: original)
            let bytes = try Data(contentsOf: original)
            let service = AudioService()
            XCTAssertEqual(try service.retainStoppedRecording(at: original), original)

            // Simulate attachment storage failure before a record can reference it.
            let inaccessibleDestination = directory.appendingPathComponent("未创建的资料目录/原声.wav")
            XCTAssertThrowsError(try FileManager.default.copyItem(at: original, to: inaccessibleDestination))
            service.cancelRecording()
            XCTAssertEqual(service.recoverableRecordingURL, original)
            XCTAssertEqual(try Data(contentsOf: original), bytes)

            // A retry commits its attachment and reference before acknowledging.
            let savedCopy = directory.appendingPathComponent("已保存副本.wav")
            try FileManager.default.copyItem(at: original, to: savedCopy)
            try Data("{\"attachment\":\"已保存副本.wav\"}".utf8)
                .write(to: directory.appendingPathComponent("资料.json"), options: .atomic)
            service.acknowledgeRecordingSaved()
            XCTAssertNil(service.recoverableRecordingURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
            XCTAssertEqual(try Data(contentsOf: savedCopy), bytes)
        }
    }

    func testInvalidStoppedOriginalNeedsExplicitDiscardAndBlocksNewRecordingBeforePermission() async throws {
        try await withDirectory { directory in
            let original = directory.appendingPathComponent("部分录音.m4a")
            let bytes = Data("无法解码，但不得在关闭编辑器时删除".utf8)
            try bytes.write(to: original)
            let service = AudioService()
            XCTAssertThrowsError(try service.retainStoppedRecording(at: original))
            service.cancelRecording()
            XCTAssertEqual(service.recoverableRecordingURL, original)
            XCTAssertEqual(try Data(contentsOf: original), bytes)
            do {
                try await service.startRecording()
                XCTFail("An unresolved original must not be overwritten by a new recording")
            } catch {
                XCTAssertEqual(error as? AudioServiceError, .recordingNeedsRecovery)
            }
            try service.discardRecoverableRecording()
            XCTAssertNil(service.recoverableRecordingURL)
            XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        }
    }

    func testSwitchingAudioIdentifiesOnlyCurrentAttachmentAndStopsCleanly() async throws {
        try await withDirectory { directory in
            let first = directory.appendingPathComponent("第一段.wav")
            let second = directory.appendingPathComponent("第二段.wav")
            try makeSilentAudio(at: first)
            try makeSilentAudio(at: second)
            let service = AudioService()
            try service.play(url: first)
            XCTAssertTrue(service.isPlaying(url: first))
            XCTAssertFalse(service.isPlaying(url: second))
            try service.play(url: second)
            XCTAssertFalse(service.isPlaying(url: first))
            XCTAssertTrue(service.isPlaying(url: second))
            XCTAssertEqual(service.playingURL, second.standardizedFileURL)
            service.stopPlayback()
            XCTAssertNil(service.playingURL)
            XCTAssertFalse(service.isPlaying(url: second))
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        }
    }
}
