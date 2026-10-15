import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ImprintEditor: View {
    @Bindable var store: LibraryStore
    @Bindable var audio: AudioService
    let original: Imprint
    var saved: (Imprint) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Imprint
    @State private var baseline: Imprint
    @State private var showImageImport = false
    @State private var showAudioImport = false
    @State private var confirmDiscard = false
    @State private var showDetails = false
    @State private var showScaleEditor = false
    @State private var error: String?
    @State private var status: String?
    @State private var importing = false
    @State private var transcribingID: UUID?
    @State private var transcriptionGeneration: UUID?
    @State private var cancellingTranscription = false
    @State private var pendingRecordingAttachment: MediaAttachment?
    @State private var confirmDiscardRecording = false
    @State private var transcriptionTask: Task<Void, Never>?
    @FocusState private var bodyFocused: Bool
    private var dirty: Bool { draft != baseline }

    init(store: LibraryStore, audio: AudioService, original: Imprint, saved: @escaping (Imprint) -> Void) {
        self.store = store; self.audio = audio; self.original = original; self.saved = saved
        _draft = State(initialValue: original); _baseline = State(initialValue: original)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { requestClose() }.keyboardShortcut(.cancelAction).disabled(importing)
                Spacer()
                Text("补记").imprintFont(.headline)
                Spacer()
                Button("保存") { saveAndClose() }.keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent).disabled(!draft.hasContent || importing || audio.isRecording || audio.recoverableRecordingURL != nil)
                    .accessibilityIdentifier("saveImprint")
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("标题（可选）", text: Binding(get: { draft.title ?? "" }, set: { draft.title = $0.isEmpty ? nil : $0 }))
                        .textFieldStyle(.plain).imprintFont(.title2).accessibilityLabel("标题，可选").accessibilityIdentifier("titleField")
                    Text("正文").imprintFont(.callout, bold: true)
                    TextEditor(text: $draft.body)
                        .imprintFont(.body).lineSpacing(5).scrollContentBackground(.hidden)
                        .padding(8).frame(minHeight: 180)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
                        .focused($bodyFocused).accessibilityLabel("正文").accessibilityIdentifier("bodyEditor")
                    attachmentToolbar
                    if audio.isRecording { recordingBanner }
                    if let url = audio.recoverableRecordingURL { recordingRecoveryBanner(url) }
                    if importing { ProgressView("正在保存附件…").controlSize(.small) }
                    ForEach($draft.attachments) { $attachment in
                        AttachmentEditor(attachment: $attachment, store: store, audio: audio, transcribing: transcribingID == attachment.id, cancelling: cancellingTranscription,
                            retry: { startTranscribing(attachment.id) }, remove: { removeAttachment(attachment.id) }, cancel: cancelTranscription)
                    }
                    if !draft.scales.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("刻度").imprintFont(.headline)
                            ForEach($draft.scales) { $scale in
                                ScaleInlineEditor(scale: $scale) { draft.scales.removeAll { $0.id == scale.id } }
                            }
                        }
                    }
                    DisclosureGroup("分类与发生时间", isExpanded: $showDetails) {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("分类（可选）", selection: $draft.categoryID) {
                                Text("未分类").tag(Optional<UUID>.none)
                                ForEach(categoryOptions(store.categories)) { option in Text(option.path).tag(Optional(option.id)) }
                            }.accessibilityIdentifier("imprintCategory")
                            DatePicker("发生时间", selection: $draft.occurredAt, displayedComponents: [.date, .hourAndMinute])
                        }.padding(.top, 12)
                    }.imprintFont(.callout)
                    if let status { Label(status, systemImage: "info.circle").imprintFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("editorStatus") }
                    if let error { Label(error, systemImage: "exclamationmark.triangle").imprintFont(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("saveError") }
                    if error == nil, let playbackError = audio.errorMessage { Label(playbackError, systemImage: "exclamationmark.triangle").imprintFont(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }.padding(24).frame(maxWidth: ImprintLayout.readingWidth).frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 500, idealWidth: 700, minHeight: 420, idealHeight: 680)
        .interactiveDismissDisabled(dirty || importing || audio.isRecording || audio.recoverableRecordingURL != nil || transcribingID != nil)
        .fileImporter(isPresented: $showImageImport, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in importFiles(result, kind: .image) }
        .fileImporter(isPresented: $showAudioImport, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: false) { result in importFiles(result, kind: .audio) }
        .confirmationDialog("保留当前编辑？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("保存并关闭") { saveAndClose() }.disabled(!draft.hasContent || audio.isRecording)
            Button("放弃尚未保存的修改", role: .destructive) {
                draft = baseline
                publishDirty()
                close()
            }
            Button("继续编辑", role: .cancel) {}
        } message: { Text("已经保存的原声会保留。未保存的文字修改会被放弃。") }
        .confirmationDialog("放弃尚未保存的原声？", isPresented: $confirmDiscardRecording, titleVisibility: .visible) {
            Button("放弃这段原声", role: .destructive) {
                do {
                    try audio.discardRecoverableRecording()
                    if let attachment = pendingRecordingAttachment { draft.attachments.removeAll { $0.id == attachment.id } }
                    pendingRecordingAttachment = nil
                    status = "已按你的选择放弃这段原声。"
                } catch { self.error = error.localizedDescription }
            }
            Button("保留原声", role: .cancel) {}
        } message: { Text("此操作会移除待恢复的录音文件。其他文字与附件会保留。") }
        .onAppear { bodyFocused = true; publishDirty() }
        .onChange(of: dirty) { _, _ in publishDirty() }
        .onChange(of: importing) { _, _ in publishDirty() }
        .onChange(of: audio.isRecording) { _, _ in publishDirty() }
        .onChange(of: audio.recoverableRecordingURL) { _, _ in publishDirty() }
        .onDisappear { transcriptionTask?.cancel(); audio.cancelRecording(); audio.stopPlayback(); NotificationCenter.default.post(name: Notification.Name("imprintEditorDirtyChanged"), object: nil, userInfo: ["dirty": false]) }
    }

    private var attachmentToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { imageButton; audioImportButton; recordButton; scaleButton }
            VStack(alignment: .leading, spacing: 12) { HStack { imageButton; audioImportButton }; HStack { recordButton; scaleButton } }
        }
        .disabled(importing || transcribingID != nil || audio.recoverableRecordingURL != nil)
    }
    private var imageButton: some View { Button { showImageImport = true } label: { Label("图片", systemImage: "photo.badge.plus") }.accessibilityIdentifier("importImage").disabled(audio.isRecording) }
    private var audioImportButton: some View { Button { showAudioImport = true } label: { Label("导入音频", systemImage: "waveform.badge.plus") }.accessibilityIdentifier("importAudio").disabled(audio.isRecording) }
    private var recordButton: some View {
        Button {
            Task {
                do {
                    if audio.isRecording { try await finishRecording() }
                    else { error = nil; try await audio.startRecording() }
                } catch { self.error = error.localizedDescription }
            }
        } label: { Label(audio.isRecording ? "结束录音" : "录音", systemImage: audio.isRecording ? "stop.circle" : "mic") }
        .accessibilityIdentifier("recordAudio")
    }
    private var scaleButton: some View { Button { draft.scales.append(ImprintScale()) } label: { Label("刻度", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("addScale").disabled(audio.isRecording) }
    private var recordingBanner: some View {
        HStack {
            Label("正在录音，结束后先保存原声，再转写", systemImage: "record.circle").foregroundStyle(.red)
            Spacer()
            Button("取消录制") { audio.cancelRecording(); status = "录制已取消。" }
        }.imprintFont(.callout).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func recordingRecoveryBanner(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("这段原声还需要保存，文件仍然保留。", systemImage: "waveform.badge.exclamationmark").imprintFont(.callout, bold: true)
            ViewThatFits(in: .horizontal) {
                HStack { retryRecordingButton(url); showRecordingButton(url); discardRecordingButton }
                VStack(alignment: .leading, spacing: 8) { retryRecordingButton(url); showRecordingButton(url); discardRecordingButton }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
    private func retryRecordingButton(_ url: URL) -> some View {
        Button("重试保存原声") {
            Task {
                do { try await preserveRecording(url) }
                catch { self.error = "原声未能完成保存，文件已保留，可以重试或在 Finder 中显示。\(error.localizedDescription)" }
            }
        }.disabled(importing).accessibilityIdentifier("retryRecordingSave")
    }
    private func showRecordingButton(_ url: URL) -> some View {
        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.accessibilityIdentifier("showRecoverableRecording")
    }
    private var discardRecordingButton: some View {
        Button("放弃这段原声", role: .destructive) { confirmDiscardRecording = true }.disabled(importing)
    }

    private func saveAndClose() {
        do { try persist(); saved(draft); close() }
        catch { self.error = "保存失败，输入已保留。\(error.localizedDescription)" }
    }
    private func persist() throws {
        draft.updatedAt = Date()
        try store.save(draft)
        baseline = draft
        publishDirty()
    }
    private func requestClose() {
        if audio.isRecording { error = "请先结束或取消录制，原声才可保存。"; return }
        if audio.recoverableRecordingURL != nil { error = "原声文件仍然保留。请先重试保存原声，或明确选择放弃这段原声。"; return }
        if importing { return }
        if dirty { confirmDiscard = true } else { close() }
    }
    private func close() { transcriptionTask?.cancel(); audio.stopPlayback(); dismiss() }
    private func publishDirty() {
        NotificationCenter.default.post(name: Notification.Name("imprintEditorDirtyChanged"), object: nil, userInfo: ["dirty": dirty || importing || audio.isRecording || audio.recoverableRecordingURL != nil])
    }
    private func importFiles(_ result: Result<[URL], Error>, kind: MediaKind) {
        switch result {
        case .failure(let failure): error = failure.localizedDescription
        case .success(let urls):
            importing = true; error = nil
            Task {
                do {
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let attachment = try await store.importAttachment(from: url, kind: kind)
                        draft.attachments.append(attachment)
                        if kind == .audio {
                            // A durable reference exists before recognition is allowed to begin.
                            try persist()
                            status = "原声已保存，正在本机转写。"
                            startTranscribing(attachment.id)
                        }
                    }
                } catch { self.error = "附件未能完成保存，已有输入与原声会保留。\(error.localizedDescription)" }
                importing = false
            }
        }
    }
    private func finishRecording() async throws {
        let source = try audio.stopRecording()
        try await preserveRecording(source)
    }
    private func preserveRecording(_ source: URL) async throws {
        importing = true
        defer { importing = false }
        let attachment: MediaAttachment
        if let pending = pendingRecordingAttachment, draft.attachments.contains(where: { $0.id == pending.id }) {
            attachment = pending
        } else {
            attachment = try await store.importAttachment(from: source, kind: .audio)
            pendingRecordingAttachment = attachment
            draft.attachments.append(attachment)
        }
        try persist()
        audio.acknowledgeRecordingSaved()
        pendingRecordingAttachment = nil
        status = "原声已保存，正在本机转写。"
        startTranscribing(attachment.id)
    }
    private func removeAttachment(_ id: UUID) {
        if transcribingID == id { cancelTranscription() }
        if pendingRecordingAttachment?.id == id { pendingRecordingAttachment = nil }
        audio.stopPlayback(); draft.attachments.removeAll { $0.id == id }
    }
    private func cancelTranscription() {
        guard transcribingID != nil else { return }
        cancellingTranscription = true
        transcriptionTask?.cancel()
        status = "正在取消转写，已保存的原声仍然保留。"
    }
    private func startTranscribing(_ id: UUID) {
        guard let attachment = draft.attachments.first(where: { $0.id == id }), transcribingID == nil else { return }
        do { try persist() } catch { self.error = "原声引用尚未保存，暂不转写。\(error.localizedDescription)"; return }
        let previousText = attachment.transcript
        let generation = UUID()
        transcriptionGeneration = generation
        transcribingID = id; error = nil
        transcriptionTask = Task {
            defer {
                if transcriptionGeneration == generation {
                    transcribingID = nil; transcriptionGeneration = nil; transcriptionTask = nil
                    if cancellingTranscription { status = "转写已取消，已保存的原声仍然保留。" }
                    cancellingTranscription = false
                }
            }
            do {
                let text = try await audio.transcribe(url: store.mediaURL(for: attachment), locale: Locale(identifier: "zh_CN"))
                guard !Task.isCancelled, let index = draft.attachments.firstIndex(where: { $0.id == id }) else { return }
                if draft.attachments[index].transcript == previousText {
                    draft.attachments[index].transcript = text
                    draft.attachments[index].transcriptionNote = nil
                    try persist()
                    status = "原声与转写已保存。你可以继续修改文字。"
                } else { status = "你已经修改了转写，保留你的文字。原声仍可再次转写。" }
            } catch {
                if !Task.isCancelled {
                    self.error = "本机转写未完成，原声已保留。\(error.localizedDescription)"
                    if let index = draft.attachments.firstIndex(where: { $0.id == id }) {
                        draft.attachments[index].transcriptionNote = "转写未完成，可以重试或手动补充。"
                        do { try persist() } catch { self.error = "原声已保存，转写状态未能保存。\(error.localizedDescription)" }
                    }
                }
            }
        }
    }
}

struct AttachmentEditor: View {
    @Binding var attachment: MediaAttachment
    let store: LibraryStore
    @Bindable var audio: AudioService
    var transcribing: Bool
    var cancelling: Bool
    var retry: () -> Void
    var remove: () -> Void
    var cancel: () -> Void
    @State private var prepareResult: String?
    @State private var confirmReplaceTranscript = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(attachment.originalName, systemImage: attachment.kind == .image ? "photo" : "waveform").lineLimit(2)
                Spacer()
                Button(action: remove) { Label("移除附件", systemImage: "xmark.circle") }.labelStyle(.iconOnly).help("移除附件引用")
            }.imprintFont(.callout)
            if attachment.kind == .image {
                AttachmentImageView(url: store.mediaURL(for: attachment), label: attachment.originalName).frame(maxHeight: 240)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { playButton; transcribeControl; modelButton }
                    VStack(alignment: .leading, spacing: 12) { HStack { playButton; transcribeControl }; modelButton }
                }
                Text("转写文字（可修改）").imprintFont(.caption1).foregroundStyle(.secondary)
                TextEditor(text: $attachment.transcript).imprintFont(.body).frame(minHeight: 90)
                    .padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .accessibilityLabel("转写文字，可修改").accessibilityIdentifier("transcriptEditor")
                if let note = attachment.transcriptionNote { Text(note).imprintFont(.caption1).foregroundStyle(.secondary) }
                if let prepareResult { Text(prepareResult).imprintFont(.caption1).foregroundStyle(.secondary) }
            }
        }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog("重新转写并替换现有文字？", isPresented: $confirmReplaceTranscript, titleVisibility: .visible) {
            Button("重新转写并替换", role: .destructive, action: retry)
            Button("保留当前文字", role: .cancel) {}
        } message: {
            Text("现有文字会保留到转写成功；如果识别期间继续修改，优先保留你的文字。原声不会改变。")
        }
    }
    private var playButton: some View {
        Button {
            do { if audio.isPlaying(url: store.mediaURL(for: attachment)) { audio.stopPlayback() } else { try audio.play(url: store.mediaURL(for: attachment)) } }
            catch { audio.errorMessage = error.localizedDescription }
        } label: { Label(audio.isPlaying(url: store.mediaURL(for: attachment)) ? "停止原声" : "播放原声", systemImage: audio.isPlaying(url: store.mediaURL(for: attachment)) ? "stop.circle" : "play.circle") }
        .accessibilityIdentifier("playAudio").disabled(audio.isRecording)
    }
    @ViewBuilder private var transcribeControl: some View {
        if transcribing { HStack { ProgressView().controlSize(.small); Button(cancelling ? "正在取消…" : "取消转写", action: cancel).disabled(cancelling) } }
        else {
            Button(attachment.transcript.isEmpty ? "本机转写" : "重新转写") {
                if attachment.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { retry() }
                else { confirmReplaceTranscript = true }
            }.accessibilityIdentifier("retryTranscription").disabled(audio.isRecording || audio.transcriptionInProgress)
        }
    }
    private var modelButton: some View {
        Button(audio.isPreparingModel ? "准备中…" : "准备中文模型") {
            Task {
                do { try await audio.prepareChineseModel(); prepareResult = "中文模型已就绪。" }
                catch { prepareResult = error.localizedDescription }
            }
        }.disabled(audio.isPreparingModel || transcribing || audio.isRecording)
        .help("按需下载系统中文识别模型，原声不会上传")
    }
}

struct ScaleInlineEditor: View {
    @Binding var scale: ImprintScale
    var remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("刻度名称", text: $scale.name).textFieldStyle(.roundedBorder).accessibilityLabel("刻度名称")
                Button(action: remove) { Label("移除刻度", systemImage: "minus.circle") }.labelStyle(.iconOnly)
            }
            Picker("类型", selection: $scale.kind) { ForEach(ScaleKind.allCases) { kind in Text(kind.title).tag(kind) } }.pickerStyle(.segmented)
            if scale.kind == .choice {
                TextField("选项，用中文逗号分隔", text: Binding(get: { scale.options.joined(separator: "，") }, set: { scale.options = $0.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("刻度选项，用逗号分隔")
                Picker("选择", selection: $scale.value) {
                    Text("未选择").tag("")
                    ForEach(Array(Set(scale.options)).sorted(), id: \.self) { Text($0).tag($0) }
                }
            } else {
                TextField(scale.kind == .number ? "数值" : "内容", text: $scale.value).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(scale.kind == .number ? "刻度数值" : "刻度内容")
            }
            TextField("单位（可选）", text: $scale.unit).textFieldStyle(.roundedBorder).accessibilityLabel("单位，可选")
        }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
