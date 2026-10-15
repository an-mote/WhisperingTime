import SwiftUI

struct ImprintContent: View {
    let record: Imprint
    let store: LibraryStore
    @Bindable var audio: AudioService
    let timeDisplay: TimeDisplay
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let title = record.title, !title.isEmpty { Text(title).imprintFont(.largeTitle, bold: true).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            HStack {
                Label(store.categoryPath(record.categoryID), systemImage: "folder").fixedSize(horizontal: false, vertical: true)
                if let date = timeDisplay.label(for: record.occurredAt) { Text(date) }
            }.imprintFont(.callout).foregroundStyle(.secondary)
            if !record.body.isEmpty { Text(record.body).imprintFont(.body).lineSpacing(7).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(record.attachments) { attachment in
                switch attachment.kind {
                case .image:
                    AttachmentImageView(url: store.mediaURL(for: attachment), label: attachment.originalName)
                        .frame(maxWidth: .infinity).frame(maxHeight: 480)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .audio:
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button {
                                do { if audio.isPlaying(url: store.mediaURL(for: attachment)) { audio.stopPlayback() } else { try audio.play(url: store.mediaURL(for: attachment)) } }
                                catch { audio.errorMessage = error.localizedDescription }
                            } label: { Label(audio.isPlaying(url: store.mediaURL(for: attachment)) ? "停止原声" : "播放原声", systemImage: audio.isPlaying(url: store.mediaURL(for: attachment)) ? "stop.circle" : "play.circle") }
                            Text(attachment.originalName).imprintFont(.caption1).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if !attachment.transcript.isEmpty { Text(attachment.transcript).imprintFont(.body).textSelection(.enabled).lineSpacing(5) }
                        if let note = attachment.transcriptionNote { Label(note, systemImage: "info.circle").imprintFont(.callout).foregroundStyle(.secondary) }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if !record.scales.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("刻度").imprintFont(.headline)
                    ForEach(record.scales) { scale in
                        LabeledContent {
                            Text(scale.value + (scale.unit.isEmpty ? "" : " \(scale.unit)")).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        } label: { Text(scale.name.isEmpty ? "未命名刻度" : scale.name).fixedSize(horizontal: false, vertical: true) }
                        .imprintFont(.body)
                    }
                }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = audio.errorMessage { Label(error, systemImage: "exclamationmark.triangle").imprintFont(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ImprintDetailSheet: View {
    @Bindable var store: LibraryStore
    @Bindable var audio: AudioService
    let id: UUID
    let timeDisplay: TimeDisplay
    @Environment(\.dismiss) private var dismiss
    @State private var editDraft: Imprint?
    @State private var confirmDelete = false
    @State private var error: String?
    private var record: Imprint? { store.imprints.first { $0.id == id } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("完成") { audio.stopPlayback(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { confirmDelete = true } label: { Label("删除印迹", systemImage: "trash") }.labelStyle(.iconOnly).help("删除印迹").disabled(store.isDemo || store.loadError != nil)
                Button("编辑") { audio.stopPlayback(); editDraft = record }.accessibilityIdentifier("editImprint").disabled(store.isDemo || store.loadError != nil)
            }.padding(16)
            Divider()
            ScrollView {
                if let record {
                    ImprintContent(record: record, store: store, audio: audio, timeDisplay: timeDisplay)
                        .padding(24).frame(maxWidth: ImprintLayout.readingWidth).frame(maxWidth: .infinity)
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding() }
        }.frame(minWidth: 500, idealWidth: 720, minHeight: 420, idealHeight: 650)
        .sheet(item: $editDraft) { draft in ImprintEditor(store: store, audio: audio, original: draft) { _ in } }
        .confirmationDialog("删除这条印迹？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除印迹", role: .destructive) {
                do { try store.deleteRecord(id); audio.stopPlayback(); dismiss() }
                catch { self.error = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("删除后将从当前本机资料中移除。") }
        .onDisappear { audio.stopPlayback() }
    }
}
