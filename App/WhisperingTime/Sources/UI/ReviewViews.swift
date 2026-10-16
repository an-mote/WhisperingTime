import SwiftUI
import AppKit

struct CardsReview: View {
    let records: [Imprint]
    let store: LibraryStore
    let timeDisplay: TimeDisplay
    @Binding var selectedID: UUID?
    var open: (Imprint) -> Void
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 420), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                ForEach(records) { record in
                    RecordPreviewButton(record: record, store: store, timeDisplay: timeDisplay, selected: selectedID == record.id) { selectedID = record.id; open(record) }
                }
            }.padding(.horizontal, ImprintLayout.gutter).padding(.bottom, ImprintLayout.gutter)
        }.accessibilityIdentifier("cardsCanvas")
    }
}

struct RecordPreviewButton: View {
    let record: Imprint
    let store: LibraryStore
    let timeDisplay: TimeDisplay
    var selected = false
    var action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                if let image = record.attachments.first(where: { $0.kind == .image }) {
                    AttachmentImageView(url: store.mediaURL(for: image), label: image.originalName, contentMode: .fit)
                        .frame(maxWidth: .infinity).frame(height: 160).clipped()
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
                if let title = record.title, !title.isEmpty { Text(title).imprintFont(.headline).lineLimit(3) }
                if !record.body.isEmpty { Text(record.body).imprintFont(.body).lineSpacing(4).lineLimit(7).multilineTextAlignment(.leading) }
                if let voice = record.attachments.first(where: { $0.kind == .audio }) {
                    Label(voice.transcript.isEmpty ? "一段声音" : voice.transcript, systemImage: "waveform")
                        .imprintFont(.callout).lineLimit(3).foregroundStyle(.secondary)
                }
                if !record.scales.isEmpty {
                    ForEach(record.scales.prefix(3)) { scale in
                        Label("\(scale.name)：\(scale.value)\(scale.unit.isEmpty ? "" : " \(scale.unit)")", systemImage: "slider.horizontal.3")
                            .imprintFont(.callout).lineLimit(2)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(store.categoryPath(record.categoryID)).lineLimit(2)
                    Spacer(minLength: 4)
                    if selected { Image(systemName: "checkmark.circle.fill").accessibilityLabel("已选中") }
                }.imprintFont(.caption1).foregroundStyle(.secondary)
                if let date = timeDisplay.label(for: record.occurredAt) { Text(date).imprintFont(.caption1).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: ImprintLayout.radius))
            .overlay { RoundedRectangle(cornerRadius: ImprintLayout.radius).strokeBorder(selected ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: selected ? 2 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: ImprintLayout.radius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.displayTitle)，\(store.categoryPath(record.categoryID))")
        .accessibilityHint("打开完整印迹")
        .accessibilityIdentifier("imprint-\(record.id.uuidString)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CalendarReview: View {
    let records: [Imprint]
    let store: LibraryStore
    let timeDisplay: TimeDisplay
    @Binding var selectedID: UUID?
    var open: (Imprint) -> Void
    @State private var month = Date()
    @State private var selectedDay = Date()
    private let calendar = Calendar(identifier: .gregorian)
    private var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month }
    private var days: [Date] {
        let offset = (calendar.component(.weekday, from: monthStart) + 5) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: monthStart) }
    }
    private var dayRecords: [Imprint] { records.filter { calendar.isDate($0.occurredAt, inSameDayAs: selectedDay) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { shiftMonth(-1) } label: { Label("上个月", systemImage: "chevron.left") }.labelStyle(.iconOnly)
                    Spacer()
                    Text(month.formatted(.dateTime.year().month(.wide))).imprintFont(.headline)
                    Spacer()
                    Button { shiftMonth(1) } label: { Label("下个月", systemImage: "chevron.right") }.labelStyle(.iconOnly)
                }
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).imprintFont(.caption1).foregroundStyle(.secondary).frame(minWidth: 0, maxWidth: .infinity).accessibilityLabel("星期\($0)") }
                    }
                    ForEach(0..<6, id: \.self) { week in
                        HStack(spacing: 5) {
                            ForEach(Array(days.dropFirst(week * 7).prefix(7)), id: \.self) { day in
                                let count = records.filter { calendar.isDate($0.occurredAt, inSameDayAs: day) }.count
                                let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                                let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
                                Button {
                                    selectedDay = day
                                    if let first = records.first(where: { calendar.isDate($0.occurredAt, inSameDayAs: day) }) { selectedID = first.id }
                                } label: {
                                    VStack(spacing: 5) {
                                        Text(String(calendar.component(.day, from: day))).imprintFont(.body)
                                        Image(systemName: count > 0 ? "circle.fill" : "circle").font(.system(size: 5)).opacity(count > 0 ? 1 : 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 42)
                                    .foregroundStyle(inMonth ? Color.primary : Color.secondary)
                                    .background(selected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay { if selected { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: 2) } }
                                }
                                .buttonStyle(.plain)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .accessibilityLabel("\(day.formatted(.dateTime.year().month().day()))，\(count) 条印迹")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                }
                Divider()
                Text(selectedDay.formatted(.dateTime.month().day())).imprintFont(.headline)
                if dayRecords.isEmpty {
                    Text("这一天没有印迹。你也可以继续看看其他日子。").imprintFont(.body).foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ForEach(dayRecords) { record in
                        RecordPreviewButton(record: record, store: store, timeDisplay: timeDisplay, selected: selectedID == record.id) { selectedID = record.id; open(record) }
                    }
                }
            }.frame(maxWidth: ImprintLayout.readingWidth).padding(.horizontal, ImprintLayout.gutter).padding(.bottom, ImprintLayout.gutter).frame(maxWidth: .infinity)
        }
        .onAppear { alignWithAvailableImprint() }
        .onChange(of: records.map(\.id)) { _, _ in alignWithAvailableImprint() }
        .accessibilityIdentifier("calendarCanvas")
    }
    private func shiftMonth(_ offset: Int) { if let next = calendar.date(byAdding: .month, value: offset, to: month) { month = next } }
    private func alignWithAvailableImprint() {
        guard let record = records.first(where: { $0.id == selectedID }) ?? records.first else { return }
        selectedID = record.id
        month = record.occurredAt
        selectedDay = record.occurredAt
    }
}

struct SlideshowReview: View {
    let records: [Imprint]
    let store: LibraryStore
    @Bindable var audio: AudioService
    let timeDisplay: TimeDisplay
    @Binding var selectedID: UUID?
    var fullScreen: () -> Void
    var exitPlayback: () -> Void
    @State private var autoplay = false
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ordered: [Imprint] { records.sorted { $0.occurredAt < $1.occurredAt } }
    private var index: Int { ordered.firstIndex(where: { $0.id == selectedID }) ?? 0 }
    private var record: Imprint? { ordered.indices.contains(index) ? ordered[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            if let record {
                ScrollView {
                    ImprintContent(record: record, store: store, audio: audio, timeDisplay: timeDisplay)
                        .id(record.id).padding(ImprintLayout.gutter).frame(maxWidth: ImprintLayout.readingWidth).frame(maxWidth: .infinity)
                }.accessibilityIdentifier("slideContent")
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { playbackControls; Spacer(minLength: 8); fullScreenButton; exitButton }
                VStack(spacing: 10) { HStack { playbackControls }; HStack { fullScreenButton; exitButton } }
            }.padding(16)
        }
        .focusable().focused($focused)
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.space) { autoplay.toggle(); return .handled }
        .onKeyPress(.escape) {
            autoplay = false
            exitPlayback()
            return .handled
        }
        .onAppear { focused = true; selectAvailableImprint() }
        .onChange(of: ordered.map(\.id)) { _, _ in selectAvailableImprint() }
        .onDisappear { autoplay = false; audio.stopPlayback() }
        .onChange(of: phase) { _, value in if value != .active { autoplay = false } }
        .onChange(of: reduceMotion) { _, reduced in if reduced { autoplay = false } }
        .task(id: autoplay) {
            guard autoplay else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard autoplay, phase == .active, !audio.isPlaying else { continue }
                if index >= ordered.count - 1 { autoplay = false; return }
                step(1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("slideshowCanvas")
    }
    @ViewBuilder private var playbackControls: some View {
        Button { step(-1) } label: { Label("上一条", systemImage: "backward.end") }.labelStyle(.iconOnly).disabled(index == 0).help("上一条（←）")
        Text("\(index + 1) / \(ordered.count)").imprintFont(.callout, monospacedDigits: true).accessibilityLabel("第 \(index + 1) 条，共 \(ordered.count) 条")
        Button { step(1) } label: { Label("下一条", systemImage: "forward.end") }.labelStyle(.iconOnly).disabled(index >= ordered.count - 1).help("下一条（→）")
        Button { autoplay.toggle() } label: { Label(autoplay ? (audio.isPlaying ? "原声播放中，已暂停翻页" : "暂停自动播放") : "自动播放", systemImage: autoplay ? "pause" : "play") }
            .accessibilityIdentifier("autoplay").help("每 5 秒切换；空格播放或暂停")
    }
    private var fullScreenButton: some View {
        Button(action: fullScreen) { Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right") }.accessibilityIdentifier("fullScreen")
    }
    private var exitButton: some View {
        Button(action: exitPlayback) { Label("退出播放", systemImage: "xmark") }.help("退出播放（Esc）").accessibilityIdentifier("exitPlayback")
    }
    private func step(_ direction: Int) {
        let next = index + direction
        guard ordered.indices.contains(next) else { return }
        audio.stopPlayback(); selectedID = ordered[next].id
    }
    private func selectAvailableImprint() {
        if !ordered.contains(where: { $0.id == selectedID }) {
            audio.stopPlayback()
            selectedID = ordered.first?.id
        }
    }
}

struct AttachmentImageView: View {
    let url: URL
    let label: String
    var contentMode: ContentMode = .fit
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode).accessibilityLabel(label) }
            else if failed { Label("图片未能读取", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary).padding() }
            else { ProgressView().accessibilityLabel("载入图片") }
        }
        .task(id: url) {
            image = nil; failed = false
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:)); failed = image == nil
        }
    }
}
