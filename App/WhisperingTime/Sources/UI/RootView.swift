import SwiftUI
import AppKit

enum ImprintLayout {
    static let spacing: CGFloat = 16
    static let gutter: CGFloat = 24
    static let readingWidth: CGFloat = 760
    static let radius: CGFloat = 12
}

struct RootView: View {
    @Bindable var store: LibraryStore
    @State private var audio = AudioService()
    @State private var visibility: NavigationSplitViewVisibility = .detailOnly
    @State private var scope: ReviewScope = .all
    @State private var mode: ReviewMode = .cards
    @State private var timeDisplay: TimeDisplay = .hidden
    @State private var selectedID: UUID?
    @State private var timelineViewport = TimelineViewportState()
    @State private var editorDraft: Imprint?
    @State private var detailID: SelectedImprint?
    @State private var categoryAction: CategoryAction?
    @State private var showSync = false
    @State private var showAbout = false
    @State private var notice: String?
    @State private var compactToolbar = true

    private var records: [Imprint] { store.records(in: scope) }
    private var scopeName: String {
        switch scope {
        case .all: "全部印迹"
        case .unclassified: "未分类"
        case .category(let id): store.categoryPath(id)
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            CategorySidebar(store: store, scope: $scope, action: $categoryAction, showSync: $showSync, showAbout: $showAbout)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 320)
        } detail: {
            VStack(spacing: 0) {
                if let error = store.loadError {
                    Label("资料未能读取：\(error)。原文件已保留，请先处理文件问题。", systemImage: "exclamationmark.triangle")
                        .imprintFont(.callout).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary)
                        .accessibilityIdentifier("loadError")
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scopeName).imprintFont(.title2, bold: true).fixedSize(horizontal: false, vertical: true)
                        Text(store.isDemo ? "示例资料 · 与你的测试资料分开保存" : "本机测试资料 · SwiftUI 原型")
                            .imprintFont(.caption1).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if store.isDemo { Button("返回我的资料") { switchDemo(false) }.controlSize(.small) }
                }
                .padding(.horizontal, ImprintLayout.gutter).padding(.vertical, 16)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("reviewHeader")
                if records.isEmpty {
                    emptyState
                } else {
                    reviewCanvas
                }
            }
            .onGeometryChange(for: Bool.self, of: { $0.size.width < 800 }) { compactToolbar = $0 }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("印迹")
            .toolbar { toolbarContent }
        }
        .sheet(item: $editorDraft) { draft in
            ImprintEditor(store: store, audio: audio, original: draft) { saved in
                selectedID = saved.id
            }
        }
        .sheet(item: $detailID) { selection in
            ImprintDetailSheet(store: store, audio: audio, id: selection.id, timeDisplay: timeDisplay)
        }
        .sheet(item: $categoryAction) { action in
            CategoryEditSheet(store: store, action: action) { deleted in
                if deleted, case .category(let id) = scope, !store.categories.contains(where: { $0.id == id }) { scope = .all }
            }
        }
        .sheet(isPresented: $showSync) { RelayDemoSheet() }
        .sheet(isPresented: $showAbout) { PrototypeInfoSheet(store: store) }
        .alert("操作未完成", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("知道了", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("newImprintRequested"))) { _ in newImprint() }
        .onAppear { if let initialMode = PrototypeQA.reviewMode { mode = initialMode } }
        .onChange(of: scope) { _, _ in
            // Selection is retained across filters and all four views; it becomes visible again when its scope returns.
        }
        .onChange(of: store.isDemo) { _, _ in selectedID = nil; scope = .all; detailID = nil; timelineViewport = TimelineViewportState() }
        .onDisappear { audio.stopPlayback() }
    }

    @ViewBuilder private var reviewCanvas: some View {
        switch mode {
        case .cards:
            CardsReview(records: records, store: store, timeDisplay: timeDisplay, selectedID: $selectedID, open: open)
        case .calendar:
            CalendarReview(records: records, store: store, timeDisplay: timeDisplay, selectedID: $selectedID, open: open)
        case .timeline:
            TimelineReview(records: records, store: store, scope: scope, timeDisplay: timeDisplay, selectedID: $selectedID, viewport: $timelineViewport, open: open)
        case .slideshow:
            SlideshowReview(records: records, store: store, audio: audio, timeDisplay: timeDisplay, selectedID: $selectedID, fullScreen: toggleFullScreen, exitPlayback: exitPlayback)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("把值得回看的片刻留在这里", systemImage: "rectangle.stack")
        } description: {
            Text("文字、画面或声音都可以。标题和分类随你选择。")
        } actions: {
            Button("补记一条", action: newImprint).buttonStyle(.borderedProminent)
                .disabled(store.loadError != nil)
            if !store.isDemo {
                Button("先看看示例") { switchDemo(true) }.accessibilityIdentifier("showExamples")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if compactToolbar {
                Menu {
                    Picker("展示方式", selection: $mode) {
                        ForEach(ReviewMode.allCases) { item in Label(item.title, systemImage: item.symbol).tag(item) }
                    }
                } label: { Text(mode.title) }
                .accessibilityIdentifier("modePicker")
            } else {
                Picker("展示方式", selection: $mode) {
                    ForEach(ReviewMode.allCases) { item in Text(item.title).tag(item).accessibilityLabel(item.title) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 330).accessibilityIdentifier("modePicker")
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("时间显示", selection: $timeDisplay) {
                    ForEach(TimeDisplay.allCases) { item in Text(item.title).tag(item) }
                }
            } label: { Label(timeDisplay.title, systemImage: timeDisplay == .hidden ? "clock.badge.questionmark" : "clock") }
            .accessibilityLabel(timeDisplay.title)
            .accessibilityIdentifier("timeDisplay").help("时间默认隐藏；日历与时间轴底部保留日期坐标")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: newImprint) { Label("补记", systemImage: "square.and.pencil") }
                .accessibilityIdentifier("newImprint").help("补记一条（⌘N）").disabled(store.loadError != nil)
        }
    }

    private func newImprint() {
        guard store.loadError == nil, editorDraft == nil, detailID == nil else { return }
        if store.isDemo { store.setDemo(false); scope = .all }
        var draft = Imprint()
        if case .category(let id) = scope { draft.categoryID = id }
        editorDraft = draft
    }
    private func open(_ record: Imprint) { selectedID = record.id; detailID = SelectedImprint(id: record.id) }
    private func switchDemo(_ enabled: Bool) { audio.stopPlayback(); store.setDemo(enabled) }
    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
    private func exitPlayback() {
        audio.stopPlayback()
        if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true { NSApp.keyWindow?.toggleFullScreen(nil) }
        mode = .cards
    }
}

struct SelectedImprint: Identifiable { let id: UUID }
