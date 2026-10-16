import SwiftUI
import AppKit

/// Kept by RootView, so changing review modes does not discard the place being read.
struct TimelineViewportState {
    var offset = CGPoint.zero
    var visibleSize = CGSize.zero
    var anchorID: UUID?
    var anchorDelta = CGPoint.zero
    var lastSelectedID: UUID?
    var hasVisited = false
}

private struct TimelineInputs: Equatable {
    var categories: [CategoryNode]
    var records: [Imprint]
    var scope: ReviewScope
    var scale: CGFloat
}

private struct TimelineMeasurement: Equatable {
    let size: CGSize
    let scale: CGFloat
    let generation: Int
}

private struct TimelineNodeSizes: PreferenceKey {
    static let defaultValue: [UUID: TimelineMeasurement] = [:]
    static func reduce(value: inout [UUID: TimelineMeasurement], nextValue: () -> [UUID: TimelineMeasurement]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TimelineBranchSizes: PreferenceKey {
    static let defaultValue: [String: TimelineMeasurement] = [:]
    static func reduce(value: inout [String: TimelineMeasurement], nextValue: () -> [String: TimelineMeasurement]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct TimelineReview: View {
    let records: [Imprint]
    let store: LibraryStore
    let scope: ReviewScope
    let timeDisplay: TimeDisplay
    @Binding var selectedID: UUID?
    @Binding var viewport: TimelineViewportState
    var open: (Imprint) -> Void
    @Environment(\.imprintTextScale) private var textScale
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var layout = TimelineLayout(categories: [], records: [], scope: .all)
    @State private var sizes: [UUID: CGSize] = [:]
    @State private var labelSizes: [String: CGSize] = [:]
    @State private var lookup: [UUID: Imprint] = [:]
    @State private var revision = 0
    @State private var command = TimelineScrollCommand()
    @State private var navigatorHeight: CGFloat = 100
    @State private var activeMeasurementScale: CGFloat = 1
    @State private var measurementGeneration = 0

    private var inputs: TimelineInputs {
        TimelineInputs(categories: store.categories, records: records, scope: scope, scale: textScale)
    }
    private var scrollRange: CGFloat { max(0, layout.size.width - viewport.visibleSize.width) }
    private var measurementsReady: Bool {
        !layout.nodes.isEmpty && layout.nodes.allSatisfy { sizes[$0.id] != nil }
            && layout.branches.allSatisfy { labelSizes[$0.id] != nil }
    }
    private var dateStyle: Date.FormatStyle { .dateTime.year().month().locale(Locale(identifier: "zh_CN")) }
    private var visibleRange: String {
        let left = viewport.offset.x
        let right = left + viewport.visibleSize.width
        let visible = layout.nodes.filter { $0.frame.maxX >= left && $0.frame.minX <= right }
        let first = visible.first ?? layout.nodes.min { abs($0.frame.midX - left) < abs($1.frame.midX - left) }
        let last = visible.last ?? first
        guard let first, let last, let firstRecord = lookup[first.id], let lastRecord = lookup[last.id] else { return "时间导航" }
        let start = firstRecord.occurredAt.formatted(dateStyle)
        let end = lastRecord.occurredAt.formatted(dateStyle)
        return start == end ? "当前画面：\(start)" : "当前画面：\(start) — \(end)"
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                TimelineScrollCanvas(layout: layout, revision: revision, measurementsReady: measurementsReady, selectedID: selectedID,
                                     viewport: $viewport, command: command,
                                     content: AnyView(tree.environment(\.imprintTextScale, textScale)))
                    .frame(width: geometry.size.width, height: max(0, geometry.size.height - navigatorHeight - 1))
                Divider().frame(height: 1)
                navigator.fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { ceil($0.size.height) }) { height in
                        if abs(navigatorHeight - height) > 0.5 { navigatorHeight = height }
                    }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .onChange(of: inputs, initial: true) { old, new in
            activeMeasurementScale = new.scale
            measurementGeneration += 1
            // A moved or renamed category can keep its ID while its heading changes
            // wrapping. Do not restore a viewport using its old height.
            sizes = [:]; labelSizes = [:]
            if old.scale != new.scale {
                viewport.hasVisited = false
            }
            lookup = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            sizes = sizes.filter { lookup[$0.key] != nil }
            rebuild()
        }
    }

    private var tree: some View {
        let groupedNodes = Dictionary(grouping: layout.nodes, by: \.branchID)
        let measuredGeneration = measurementGeneration
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for edge in layout.connections {
                    var path = Path()
                    path.move(to: edge.from)
                    path.addCurve(to: edge.to, control1: edge.control1, control2: edge.control2)
                    context.stroke(path, with: .color(.primary.opacity(contrast == .increased ? 0.85 : 0.56)), style: StrokeStyle(lineWidth: contrast == .increased ? 3 : 2, lineCap: .round))
                }
            }.accessibilityHidden(true).allowsHitTesting(false)
            ForEach(layout.branches) { branch in
                ZStack(alignment: .topLeading) {
                    TimelineHeadingLayout(maximumWidth: 176 * textScale) {
                        branchHeading(branch)
                    }
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: TimelineBranchSizes.self, value: [branch.id: TimelineMeasurement(size: CGSize(width: geometry.size.width, height: ceil(geometry.size.height)), scale: textScale, generation: measuredGeneration)])
                            }
                        }
                        .frame(width: branch.labelFrame.width, height: branch.labelFrame.height, alignment: .leading)
                        .position(x: branch.labelFrame.midX, y: branch.labelFrame.midY)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel(branchDescription(branch))
                        .accessibilityIdentifier("timelineBranch-\(branch.id)")
                    ForEach(groupedNodes[branch.id, default: []]) { node in
                        if let record = lookup[node.id] {
                            TimelineRecordButton(record: record, store: store, timeDisplay: timeDisplay, selected: selectedID == record.id) {
                                // Opening the sheet keeps the canvas exactly where the person clicked.
                                viewport.lastSelectedID = record.id
                                selectedID = record.id
                                open(record)
                            }
                            .frame(width: layout.nodeWidth)
                            .fixedSize(horizontal: false, vertical: true)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: TimelineNodeSizes.self, value: [node.id: TimelineMeasurement(size: CGSize(width: geometry.size.width, height: ceil(geometry.size.height)), scale: textScale, generation: measuredGeneration)])
                                }
                            }
                            .frame(width: node.frame.width, height: node.frame.height, alignment: .center)
                            .position(x: node.frame.midX, y: node.frame.midY)
                        }
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .accessibilityElement(children: .contain)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onPreferenceChange(TimelineNodeSizes.self) { measured in
            let current = measured.filter { $0.value.scale == activeMeasurementScale && $0.value.generation == measurementGeneration }.mapValues(\.size)
            let changed = current.filter { id, size in
                guard size.width.isFinite, size.height.isFinite, size.height > 0 else { return false }
                return abs((sizes[id]?.height ?? 0) - size.height) > 0.5
            }
            guard !changed.isEmpty else { return }
            sizes.merge(changed, uniquingKeysWith: { _, new in new })
            rebuild()
        }
        .onPreferenceChange(TimelineBranchSizes.self) { measured in
            let current = measured.filter { $0.value.scale == activeMeasurementScale && $0.value.generation == measurementGeneration }.mapValues(\.size)
            let changed = current.filter { id, size in
                guard size.height.isFinite, size.height > 0 else { return false }
                return abs((labelSizes[id]?.height ?? 0) - size.height) > 0.5
                    || abs((labelSizes[id]?.width ?? 0) - size.width) > 0.5
            }
            guard !changed.isEmpty else { return }
            labelSizes.merge(changed, uniquingKeysWith: { _, new in new })
            rebuild()
        }
    }

    private func branchDescription(_ branch: TimelineLayout.Branch) -> String {
        guard branch.categoryID != nil else { return "未分类分支" }
        let category = store.categories.first { $0.id == branch.categoryID }
        let parent = store.categories.first { $0.id == category?.parentID }
        return "分类：\(branch.name)" + (parent.map { "，上级分类：\($0.name)" } ?? "")
    }

    private func branchHeading(_ branch: TimelineLayout.Branch) -> some View {
        Text(branch.name)
            .imprintFont(.headline, bold: true)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var navigator: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let first = layout.ticks.first { Text(first.date.formatted(dateStyle)) }
                Spacer(minLength: 8)
                if let last = layout.ticks.last, layout.ticks.first?.date != last.date { Text(last.date.formatted(dateStyle)) }
            }.imprintFont(.caption1).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { move(-1) } label: { Label("较早", systemImage: "chevron.left") }
                    .labelStyle(.iconOnly).disabled(!measurementsReady || viewport.offset.x <= 0.5)
                    .accessibilityIdentifier("timelineEarlier").help("向较早时间移动（←）")
                TimelineScroller(value: scrollRange > 0 ? viewport.offset.x / scrollRange : 0,
                                 proportion: layout.size.width > 0 ? min(1, viewport.visibleSize.width / layout.size.width) : 1,
                                 enabled: measurementsReady && scrollRange > 0.5) { value in
                    scroll(to: CGPoint(x: value * scrollRange, y: viewport.offset.y))
                }.frame(height: 22)
                Button { move(1) } label: { Label("较新", systemImage: "chevron.right") }
                    .labelStyle(.iconOnly).disabled(!measurementsReady || viewport.offset.x >= scrollRange - 0.5)
                    .accessibilityIdentifier("timelineLater").help("向较新时间移动（→）")
            }
            Text(visibleRange).imprintFont(.caption1).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("timelineVisibleRange")
        }
        .padding(.horizontal, ImprintLayout.gutter).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain).accessibilityLabel("时间导航").accessibilityIdentifier("timelineNavigator")
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard press.modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return .ignored }
            move(press.key == .leftArrow ? -1 : 1)
            return .handled
        }
    }

    private func rebuild() {
        layout = TimelineLayout(categories: store.categories, records: records, scope: scope, nodeSizes: sizes, labelSizes: labelSizes, textScale: textScale)
        revision += 1
    }
    private func move(_ direction: CGFloat) {
        guard measurementsReady else { return }
        scroll(to: CGPoint(x: viewport.offset.x + direction * max(120, viewport.visibleSize.width * 0.7), y: viewport.offset.y))
    }
    private func scroll(to target: CGPoint) {
        command = TimelineScrollCommand(serial: command.serial + 1,
                                        target: CGPoint(x: min(scrollRange, max(0, target.x)), y: target.y))
    }
}

/// Measure short ancestor names at their natural width while allowing long names to wrap.
private struct TimelineHeadingLayout: Layout {
    let maximumWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: maximumWidth, height: nil)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

private struct TimelineRecordButton: View {
    let record: Imprint
    let store: LibraryStore
    let timeDisplay: TimeDisplay
    let selected: Bool
    var action: () -> Void
    @Environment(\.imprintTextScale) private var textScale
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                if let image = record.attachments.first(where: { $0.kind == .image }) {
                    AttachmentImageView(url: store.mediaURL(for: image), label: image.originalName, contentMode: .fit)
                        .frame(height: 82 * textScale).frame(maxWidth: .infinity)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                HStack(alignment: .top, spacing: 6) {
                    Text(record.displayTitle).imprintFont(.headline).lineLimit(3).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        .opacity(selected ? 1 : 0).accessibilityHidden(true)
                }
                if record.title != nil, !record.body.isEmpty {
                    Text(record.body).imprintFont(.body).lineLimit(2).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                if record.attachments.contains(where: { $0.kind == .audio }) {
                    Label("含原声", systemImage: "waveform").imprintFont(.caption1).foregroundStyle(.secondary)
                }
                if !record.scales.isEmpty {
                    Label("\(record.scales.count) 项刻度", systemImage: "slider.horizontal.3").imprintFont(.caption1).foregroundStyle(.secondary)
                }
                if let date = timeDisplay.label(for: record.occurredAt) {
                    Text(date).imprintFont(.caption1).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: ImprintLayout.radius))
            .overlay {
                RoundedRectangle(cornerRadius: ImprintLayout.radius)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(contrast == .increased ? 0.7 : 0.45), lineWidth: selected ? 2 : 1)
            }
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

private struct TimelineScrollCommand: Equatable {
    var serial = 0
    var target = CGPoint.zero
}

private typealias TimelineDocumentView = NSHostingView<AnyView>

final class TimelineNativeScrollView: NSScrollView {
    override func accessibilityValue() -> Any? {
        String(format: "x=%.1f,y=%.1f", contentView.bounds.minX, contentView.bounds.minY)
    }
    override func accessibilityHelp() -> String? {
        #if DEBUG
        if PrototypeQA.windowSize != nil {
            return "QA视口：\(contentView.bounds.size)，画布框：\(frame)，窗口：\(window?.contentView?.bounds.size ?? .zero)"
        }
        #endif
        return "可滚动浏览分类分支，也可使用底部时间导航"
    }
    override func scrollWheel(with event: NSEvent) {
        let previousX = contentView.bounds.minX
        super.scrollWheel(with: event)
        // Preserve horizontal wheel input with the control in the footer. Let AppKit handle
        // the event first, and never apply a second step when it already moved the clip.
        guard event.scrollingDeltaX != 0, abs(contentView.bounds.minX - previousX) < 0.01,
              let documentView else { return }
        let step = event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : 10)
        var origin = contentView.bounds.origin
        origin.x = min(max(0, documentView.frame.width - contentView.bounds.width), max(0, origin.x - step))
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

/// The native clip view is the single source of scroll position for wheel, keyboard and scroller input.
private struct TimelineScrollCanvas: NSViewRepresentable {
    let layout: TimelineLayout
    let revision: Int
    let measurementsReady: Bool
    let selectedID: UUID?
    @Binding var viewport: TimelineViewportState
    let command: TimelineScrollCommand
    let content: AnyView

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> TimelineNativeScrollView {
        let scroll = TimelineNativeScrollView()
        scroll.drawsBackground = false
        scroll.clipsToBounds = true
        scroll.contentView.clipsToBounds = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.setAccessibilityIdentifier("timelineCanvas")
        scroll.setAccessibilityLabel("树根时间轴")
        let document = TimelineDocumentView(rootView: hostedContent(in: .zero))
        document.isFlipped = true
        document.clipsToBounds = true
        document.sizingOptions = []
        scroll.documentView = document
        context.coordinator.install(scroll)
        return scroll
    }
    func updateNSView(_ scroll: TimelineNativeScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(scroll)
    }
    private func documentOrigin(in container: CGSize) -> CGPoint {
        CGPoint(x: max(0, (container.width - layout.size.width) / 2),
                y: max(0, (container.height - layout.size.height) / 2))
    }
    private func hostedContent(in container: CGSize) -> AnyView {
        let origin = documentOrigin(in: container)
        return AnyView(content.offset(x: origin.x, y: origin.y)
            .frame(width: max(layout.size.width, container.width), height: max(layout.size.height, container.height), alignment: .topLeading))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TimelineNativeScrollView, context: Context) -> CGSize? {
        // The document can be much taller than the window. Its intrinsic size must never
        // become the minimum height of the viewport and push the persistent controls out.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 640
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 320
        return CGSize(width: max(0, width), height: max(0, height))
    }
    static func dismantleNSView(_ nsView: TimelineNativeScrollView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator {
        var parent: TimelineScrollCanvas
        private weak var scroll: TimelineNativeScrollView?
        private var observer: NSObjectProtocol?
        private var pending: Task<Void, Never>?
        private var lastRevision = -1
        private var lastCommand = 0
        private var lastContainer = CGSize.zero
        private var installed = false

        init(parent: TimelineScrollCanvas) { self.parent = parent }
        func install(_ scroll: TimelineNativeScrollView) {
            self.scroll = scroll
            scroll.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedulePublish() }
            }
        }
        func stop() {
            pending?.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }
        func update(_ scroll: TimelineNativeScrollView) {
            guard let document = scroll.documentView as? TimelineDocumentView else { return }
            let container = scroll.contentView.bounds.size
            document.setFrameSize(CGSize(width: max(parent.layout.size.width, container.width), height: max(parent.layout.size.height, container.height)))
            document.rootView = parent.hostedContent(in: container)
            // A fresh hosting tree first receives an empty derived layout. It must not consume
            // the remembered viewport before the real records and a usable clip size arrive.
            guard parent.measurementsReady, !parent.layout.nodes.isEmpty, container.width > 0, container.height > 0 else { return }
            let origin = parent.documentOrigin(in: container)
            func documentFrame(_ node: TimelineLayout.Node) -> CGRect {
                node.frame.offsetBy(dx: origin.x, dy: origin.y)
            }
            var target = scroll.contentView.bounds.origin
            if !installed || lastRevision != parent.revision || lastContainer != container || parent.viewport.lastSelectedID != parent.selectedID {
                if let selected = parent.layout.nodes.first(where: { $0.id == parent.selectedID }),
                   !parent.viewport.hasVisited || parent.viewport.lastSelectedID != parent.selectedID {
                    let frame = documentFrame(selected)
                    target = CGPoint(x: frame.midX - container.width / 2, y: frame.midY - container.height / 2)
                } else if let anchor = parent.layout.nodes.first(where: { $0.id == parent.viewport.anchorID }), parent.viewport.hasVisited {
                    let frame = documentFrame(anchor)
                    target = CGPoint(x: frame.minX + parent.viewport.anchorDelta.x, y: frame.minY + parent.viewport.anchorDelta.y)
                } else if let first = parent.layout.nodes.first {
                    let frame = documentFrame(first)
                    target = CGPoint(x: frame.maxX > container.width ? frame.minX - 24 : 0,
                                     y: max(0, frame.maxY - container.height + 24))
                }
                lastRevision = parent.revision
                lastContainer = container
                installed = true
            }
            if parent.command.serial != lastCommand {
                target = parent.command.target
                lastCommand = parent.command.serial
            }
            target.x = min(max(0, document.frame.width - container.width), max(0, target.x))
            target.y = min(max(0, document.frame.height - container.height), max(0, target.y))
            scroll.contentView.scroll(to: target)
            scroll.reflectScrolledClipView(scroll.contentView)
            schedulePublish()
        }
        private func schedulePublish() {
            // Coalesce AppKit notifications after representable updates, without timing delays.
            pending?.cancel()
            pending = Task { @MainActor [weak self] in
                guard !Task.isCancelled, let self, let scroll = self.scroll else { return }
                let bounds = scroll.contentView.bounds
                guard self.parent.measurementsReady, bounds.width > 0, bounds.height > 0 else { return }
                var state = self.parent.viewport
                state.offset = bounds.origin
                state.visibleSize = bounds.size
                state.hasVisited = !self.parent.layout.nodes.isEmpty
                // A retained selection must be located again when it re-enters the scope,
                // even if it had already been shown before that filter was applied.
                state.lastSelectedID = self.parent.layout.nodes.contains(where: { $0.id == self.parent.selectedID })
                    ? self.parent.selectedID : nil
                if let nearest = self.parent.layout.nodes.min(by: {
                    let origin = self.parent.documentOrigin(in: bounds.size)
                    return hypot($0.frame.midX + origin.x - bounds.midX, $0.frame.midY + origin.y - bounds.midY)
                        < hypot($1.frame.midX + origin.x - bounds.midX, $1.frame.midY + origin.y - bounds.midY)
                }) {
                    let origin = self.parent.documentOrigin(in: bounds.size)
                    state.anchorID = nearest.id
                    state.anchorDelta = CGPoint(x: bounds.minX - nearest.frame.minX - origin.x, y: bounds.minY - nearest.frame.minY - origin.y)
                }
                let old = self.parent.viewport
                if old.offset != state.offset || old.visibleSize != state.visibleSize || old.anchorID != state.anchorID || old.anchorDelta != state.anchorDelta || old.lastSelectedID != state.lastSelectedID || old.hasVisited != state.hasVisited {
                    self.parent.viewport = state
                }
            }
        }
    }
}

private final class TimelineNativeScroller: NSScroller {
    private(set) var isTrackingKnob = false
    override func mouseDown(with event: NSEvent) {
        isTrackingKnob = true
        defer { isTrackingKnob = false }
        super.mouseDown(with: event)
    }
}

private struct TimelineScroller: NSViewRepresentable {
    let value: CGFloat
    let proportion: CGFloat
    let enabled: Bool
    var changed: (CGFloat) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> TimelineNativeScroller {
        let control = TimelineNativeScroller(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        control.scrollerStyle = .legacy
        control.controlSize = .regular
        control.target = context.coordinator
        control.action = #selector(Coordinator.drag(_:))
        control.setAccessibilityIdentifier("timelineScroller")
        control.setAccessibilityLabel("时间滚动条")
        control.setAccessibilityHelp("拖动以浏览较早或较新的印迹；也可使用两侧按钮")
        return control
    }
    func updateNSView(_ control: TimelineNativeScroller, context: Context) {
        context.coordinator.parent = self
        control.knobProportion = min(1, max(0, proportion))
        // Do not reset AppKit's live knob tracking while its action is being delivered.
        if !control.isTrackingKnob, abs(control.doubleValue - Double(value)) > 0.0001 { control.doubleValue = Double(min(1, max(0, value))) }
        // AppKit updates the control's usable parts when its knob proportion changes.
        // Apply availability last so a full-width knob also exposes the disabled state.
        control.isEnabled = enabled
        control.setAccessibilityEnabled(enabled)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: TimelineScroller
        init(parent: TimelineScroller) { self.parent = parent }
        @objc func drag(_ sender: NSScroller) {
            guard parent.enabled else { return }
            var value = CGFloat(sender.doubleValue)
            switch sender.hitPart {
            case .decrementLine: value = parent.value - 0.05
            case .incrementLine: value = parent.value + 0.05
            case .decrementPage: value = parent.value - max(0.05, parent.proportion / max(0.01, 1 - parent.proportion))
            case .incrementPage: value = parent.value + max(0.05, parent.proportion / max(0.01, 1 - parent.proportion))
            default: break
            }
            parent.changed(min(1, max(0, value)))
        }
    }
}
