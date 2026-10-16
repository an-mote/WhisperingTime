import Foundation
import CoreGraphics

/// A derived, compressed time coordinate system. It never changes library dates or hierarchy.
struct TimelineLayout {
    struct Node: Identifiable, Equatable {
        let id: UUID
        let branchID: String
        let frame: CGRect
    }

    struct Branch: Identifiable, Equatable {
        let id: String
        let categoryID: UUID?
        let name: String
        let labelFrame: CGRect
        let y: CGFloat
        let firstRecordID: UUID?
        let parentID: String?
        let startX: CGFloat
        let endX: CGFloat
        /// Empty ancestors have a structural junction, with no artificial content node.
        let junction: CGPoint
        /// Absolute category depth in the library, including ancestors outside the current scope.
        let depth: Int
        /// Contains this header, its content and all descendant groups, including their local routing channels.
        let subtreeFrame: CGRect
    }

    enum ConnectionKind: Equatable { case hierarchy, continuation }

    /// One drawn segment. Shared structural trunks are drawn once and carry every path that uses them.
    struct Connection: Identifiable, Equatable {
        let id: String
        let from: CGPoint
        let to: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let relationshipID: String
        let relationshipIDs: [String]
        let sourceRecordID: UUID?
        let targetRecordID: UUID?
        let kind: ConnectionKind
        /// The empty category that owns this shared trunk or one of its structural arms.
        let structuralBranchID: String?

        init(
            id: String, from: CGPoint, to: CGPoint, control1: CGPoint, control2: CGPoint,
            relationshipID: String, sourceRecordID: UUID?, targetRecordID: UUID?, kind: ConnectionKind,
            relationshipIDs: [String]? = nil, structuralBranchID: String? = nil
        ) {
            self.id = id; self.from = from; self.to = to
            self.control1 = control1; self.control2 = control2
            self.relationshipID = relationshipID
            self.relationshipIDs = relationshipIDs ?? [relationshipID]
            self.sourceRecordID = sourceRecordID; self.targetRecordID = targetRecordID
            self.kind = kind; self.structuralBranchID = structuralBranchID
        }
    }

    struct Tick: Identifiable, Equatable {
        let id: String
        let date: Date
        let x: CGFloat
    }

    let nodes: [Node]
    let branches: [Branch]
    let connections: [Connection]
    let size: CGSize
    let orderedIDs: [UUID]
    let ticks: [Tick]
    let nodeWidth: CGFloat

    init(
        categories: [CategoryNode], records: [Imprint], scope: ReviewScope = .all,
        nodeSizes: [UUID: CGSize] = [:], labelSizes: [String: CGSize] = [:], textScale: CGFloat = 1
    ) {
        let scale = textScale.isFinite ? min(max(textScale, 1), 3) : 1
        let padding: CGFloat = 20 * scale
        let labelWidth: CGFloat = 176 * scale
        let labelHeight: CGFloat = 24 * scale
        let labelGap: CGFloat = 10 * scale
        let groupInset: CGFloat = 12 * scale
        let verticalInset: CGFloat = 6 * scale
        let groupGap: CGFloat = 12 * scale
        let channelStep: CGFloat = 10 * scale
        let fanStep: CGFloat = 8 * scale
        let defaultHeight: CGFloat = 148 * scale
        let looseKey = "unclassified"
        func key(_ id: UUID) -> String { "category-\(id.uuidString.lowercased())" }

        let lookup = categories.reduce(into: [UUID: CategoryNode]()) { $0[$1.id] = $1 }
        var allowed = Set(lookup.keys)
        if case .category(let root) = scope {
            allowed = [root]
            var pending = [root]
            while let parent = pending.popLast() {
                for child in categories where child.parentID == parent && allowed.insert(child.id).inserted {
                    pending.append(child.id)
                }
            }
        }
        let filtered = records.filter { record in
            switch scope {
            case .all: true
            case .unclassified: record.categoryID == nil
            case .category: record.categoryID.map { allowed.contains($0) && lookup[$0] != nil } ?? false
            }
        }
        var seen = Set<UUID>()
        let ordered = filtered.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.id.uuidString < $1.id.uuidString
        }.filter { seen.insert($0.id).inserted }
        orderedIDs = ordered.map(\.id)
        let cardWidth = max(236 * scale, ordered.compactMap { record -> CGFloat? in
            guard let width = nodeSizes[record.id]?.width, width.isFinite, width > 0 else { return nil }
            return width
        }.max() ?? 0)
        nodeWidth = cardWidth
        guard !ordered.isEmpty else {
            nodes = []; branches = []; connections = []; ticks = []
            size = CGSize(width: 640, height: 320)
            return
        }

        var included = Set<UUID>()
        var grouped: [String: [Imprint]] = [:]
        var recordBranch: [UUID: String] = [:]
        for record in ordered {
            let branchKey = record.categoryID.flatMap { lookup[$0] != nil ? key($0) : nil } ?? looseKey
            grouped[branchKey, default: []].append(record)
            recordBranch[record.id] = branchKey
            var current = record.categoryID
            var ancestors = Set<UUID>()
            while let id = current, ancestors.insert(id).inserted, let category = lookup[id], allowed.contains(id) {
                included.insert(id)
                if case .category(let root) = scope, id == root { break }
                current = category.parentID
            }
        }
        var categoryByKey: [String: CategoryNode] = [:]
        var parents: [String: String] = [:]
        var children: [String: [String]] = [:]
        for id in included {
            guard let category = lookup[id] else { continue }
            let branchKey = key(id)
            categoryByKey[branchKey] = category
            if case .category(let root) = scope, id == root { continue }
            if let parent = category.parentID, included.contains(parent) {
                parents[branchKey] = key(parent)
                children[key(parent), default: []].append(branchKey)
            }
        }
        for parent in Array(children.keys) { children[parent]?.sort() }
        let rank = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset) })
        func earliestRank(in branchKey: String, visiting: Set<String> = []) -> Int {
            guard !visiting.contains(branchKey) else { return .max }
            var next = visiting; next.insert(branchKey)
            return min(grouped[branchKey]?.first.map { rank[$0.id, default: .max] } ?? .max,
                       children[branchKey, default: []].map { earliestRank(in: $0, visiting: next) }.min() ?? .max)
        }
        var roots = categoryByKey.keys.filter { parents[$0] == nil }
        if grouped[looseKey] != nil { roots.append(looseKey) }
        roots.sort {
            let lhs = earliestRank(in: $0), rhs = earliestRank(in: $1)
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        var branchOrder: [String] = []
        var treeChildren: [String: [String]] = [:]
        var visited = Set<String>()
        func place(_ branchKey: String) {
            guard visited.insert(branchKey).inserted else { return }
            branchOrder.append(branchKey)
            for child in children[branchKey, default: []] where !visited.contains(child) {
                treeChildren[branchKey, default: []].append(child)
                place(child)
            }
        }
        for root in roots { place(root) }
        // Cyclic imported data still produces a finite, deterministic forest.
        for leftover in categoryByKey.keys.sorted() where !visited.contains(leftover) {
            parents.removeValue(forKey: leftover)
            roots.append(leftover)
            place(leftover)
        }
        for branchKey in branchOrder {
            if let parent = parents[branchKey], !treeChildren[parent, default: []].contains(branchKey) {
                parents.removeValue(forKey: branchKey)
            }
        }
        func absoluteDepth(_ categoryID: UUID?) -> Int {
            var current = categoryID.flatMap { lookup[$0]?.parentID }
            var visited = Set<UUID>()
            var depth = 0
            while let id = current, visited.insert(id).inserted, let ancestor = lookup[id] {
                depth += 1
                current = ancestor.parentID
            }
            return depth
        }
        let heights = ordered.reduce(into: [UUID: CGFloat]()) { result, record in
            let value = nodeSizes[record.id]?.height ?? defaultHeight
            result[record.id] = value.isFinite && value > 0 ? max(value, 72 * scale) : defaultHeight
        }
        let measuredLabels = branchOrder.reduce(into: [String: CGSize]()) { result, branchKey in
            let isStructural = grouped[branchKey, default: []].isEmpty
            let estimatedWidth = isStructural
                ? min(labelWidth, max(28 * scale, CGFloat(categoryByKey[branchKey]?.name.count ?? 2) * 14 * scale))
                : labelWidth
            let width = labelSizes[branchKey]?.width ?? estimatedWidth
            let height = labelSizes[branchKey]?.height ?? labelHeight
            result[branchKey] = CGSize(
                width: width.isFinite && width > 0 ? (isStructural ? width : max(labelWidth, width)) : estimatedWidth,
                height: height.isFinite && height > 0 ? height : labelHeight
            )
        }

        // Every branch shares the same chronological x coordinates. Same-branch cards need a full card gap.
        var columnX: [UUID: CGFloat] = [:]
        var lastInLane: [String: CGFloat] = [:]
        var previousX = padding - 160 * scale
        for record in ordered {
            let branchKey = recordBranch[record.id, default: looseKey]
            let sameLaneMinimum = lastInLane[branchKey].map { $0 + cardWidth + 24 * scale } ?? padding
            let x = max(previousX + 160 * scale, sameLaneMinimum)
            columnX[record.id] = x
            lastInLane[branchKey] = x
            previousX = x
        }

        // Subtrees keep continuous vertical bands. Empty names occupy only a measured short branch to the
        // left of their children; they never reserve a fake content row or a full-width hierarchy column.
        var groupLeft: [String: CGFloat] = [:]
        var channelBase: [String: CGFloat] = [:]
        var structuralX: [String: CGFloat] = [:]
        for branchKey in branchOrder.reversed() {
            let own = grouped[branchKey, default: []]
            let descendants = treeChildren[branchKey, default: []]
            let ownLeft = own.compactMap { columnX[$0.id] }.min() ?? .greatestFiniteMagnitude
            let descendantLeft = descendants.compactMap { groupLeft[$0] }.min() ?? .greatestFiniteMagnitude
            let innerLeft = min(ownLeft, descendantLeft)
            channelBase[branchKey] = innerLeft
            if own.isEmpty {
                let width = measuredLabels[branchKey]?.width ?? labelWidth
                structuralX[branchKey] = innerLeft - width - 16 * scale
                groupLeft[branchKey] = structuralX[branchKey]! - 8 * scale
            } else {
                groupLeft[branchKey] = innerLeft - groupInset - CGFloat(descendants.count) * channelStep
            }
        }
        let horizontalShift = max(0, 4 * scale - (groupLeft.values.min() ?? padding))
        for id in Array(columnX.keys) { columnX[id, default: 0] += horizontalShift }
        for branchKey in branchOrder {
            groupLeft[branchKey, default: 0] += horizontalShift
            channelBase[branchKey, default: 0] += horizontalShift
            if structuralX[branchKey] != nil { structuralX[branchKey, default: 0] += horizontalShift }
        }

        var frames: [UUID: CGRect] = [:]
        var labelFrames: [String: CGRect] = [:]
        var junctions: [String: CGPoint] = [:]
        var subtreeFrames: [String: CGRect] = [:]
        func shiftSubtree(_ branchKey: String, by delta: CGFloat) {
            for record in grouped[branchKey, default: []] { frames[record.id] = frames[record.id]?.offsetBy(dx: 0, dy: delta) }
            labelFrames[branchKey] = labelFrames[branchKey]?.offsetBy(dx: 0, dy: delta)
            if let point = junctions[branchKey] { junctions[branchKey] = CGPoint(x: point.x, y: point.y + delta) }
            subtreeFrames[branchKey] = subtreeFrames[branchKey]?.offsetBy(dx: 0, dy: delta)
            for child in treeChildren[branchKey, default: []] { shiftSubtree(child, by: delta) }
        }
        func childAnchor(_ branchKey: String) -> CGPoint {
            if let first = grouped[branchKey]?.first, let frame = frames[first.id] {
                return CGPoint(x: frame.minX, y: frame.midY)
            }
            return junctions[branchKey, default: .zero]
        }
        func arrange(_ branchKey: String, top: CGFloat) -> CGFloat {
            let own = grouped[branchKey, default: []]
            let descendants = treeChildren[branchKey, default: []]
            let labelSize = measuredLabels[branchKey, default: CGSize(width: labelWidth, height: labelHeight)]
            var bottom: CGFloat
            if own.isEmpty {
                var childTop = top
                bottom = top
                for child in descendants {
                    bottom = arrange(child, top: childTop)
                    childTop = bottom + groupGap
                }
                var anchors = descendants.map(childAnchor)
                var y = ((anchors.first?.y ?? top) + (anchors.last?.y ?? top)) / 2
                let x = structuralX[branchKey, default: padding]
                // Keep the name above the branch point. A middle child may share the point's y, so a
                // centered name would block its horizontal arm. Very tall names need an actual safe gap.
                if descendants.count > 1, let upper = anchors.filter({ $0.y < y }).map(\.y).max() {
                    let extra = max(0, 2 * (labelSize.height + 12 * scale - (y - upper)))
                    if extra > 0 {
                        for (child, anchor) in zip(descendants, anchors) where anchor.y >= y {
                            shiftSubtree(child, by: extra)
                        }
                        bottom += extra
                        anchors = descendants.map(childAnchor)
                        y = ((anchors.first?.y ?? top) + (anchors.last?.y ?? top)) / 2
                    }
                }
                var labelY = y - labelSize.height - 8 * scale
                if labelY < top + verticalInset {
                    let delta = top + verticalInset - labelY
                    for child in descendants { shiftSubtree(child, by: delta) }
                    y += delta; bottom += delta; labelY += delta
                }
                labelFrames[branchKey] = CGRect(x: x + 8 * scale, y: labelY, width: labelSize.width, height: labelSize.height)
                junctions[branchKey] = CGPoint(x: x, y: y)
                bottom = max(bottom, labelY + labelSize.height)
            } else {
                // Keep the parent content row between its upper and lower child subtrees.
                let split = (descendants.count + 1) / 2
                var ownTop = top
                for child in descendants.prefix(split) {
                    ownTop = arrange(child, top: ownTop) + groupGap
                }
                let first = own[0]
                let firstHeight = heights[first.id, default: defaultHeight]
                let maximumHeight = own.map { heights[$0.id, default: defaultHeight] }.max() ?? firstHeight
                var centerY = ownTop + verticalInset + max(labelSize.height + labelGap + firstHeight / 2, maximumHeight / 2)
                var labelY = centerY - firstHeight / 2 - labelGap - labelSize.height
                let labelX = columnX[first.id, default: padding]
                for record in own.dropFirst() {
                    let x = columnX[record.id, default: padding]
                    if x < labelX + labelSize.width {
                        labelY = min(labelY, centerY - heights[record.id, default: defaultHeight] / 2 - labelGap - labelSize.height)
                    }
                }
                if labelY < ownTop + verticalInset {
                    centerY += ownTop + verticalInset - labelY
                    labelY = ownTop + verticalInset
                }
                labelFrames[branchKey] = CGRect(x: labelX, y: labelY, width: labelSize.width, height: labelSize.height)
                for record in own {
                    let height = heights[record.id, default: defaultHeight]
                    frames[record.id] = CGRect(x: columnX[record.id, default: padding], y: centerY - height / 2,
                                               width: cardWidth, height: height)
                }
                junctions[branchKey] = CGPoint(x: labelX + cardWidth / 2, y: centerY)
                bottom = centerY + maximumHeight / 2
                var childTop = bottom + groupGap
                for child in descendants.dropFirst(split) {
                    bottom = arrange(child, top: childTop)
                    childTop = bottom + groupGap
                }
            }
            let ownRectangles = own.compactMap { frames[$0.id] } + [labelFrames[branchKey]!]
            let right = max(ownRectangles.map(\.maxX).max() ?? 0,
                            descendants.compactMap { subtreeFrames[$0]?.maxX }.max() ?? 0) + groupInset
            let left = groupLeft[branchKey, default: padding]
            subtreeFrames[branchKey] = CGRect(x: left, y: top, width: right - left, height: bottom + verticalInset - top)
            return bottom + verticalInset
        }
        var nextTop = padding
        for root in roots { nextTop = arrange(root, top: nextTop) + groupGap }
        let placedNodes = ordered.map {
            Node(id: $0.id, branchID: recordBranch[$0.id, default: looseKey], frame: frames[$0.id]!)
        }
        nodes = placedNodes
        let placedBranches = branchOrder.map { branchKey -> Branch in
            let category = categoryByKey[branchKey]
            let own = grouped[branchKey, default: []]
            let firstFrame = own.first.flatMap { frames[$0.id] }
            let junction = junctions[branchKey, default: .zero]
            return Branch(
                id: branchKey, categoryID: category?.id, name: category?.name ?? "未分类",
                labelFrame: labelFrames[branchKey, default: .zero], y: junction.y,
                firstRecordID: own.first?.id, parentID: parents[branchKey],
                startX: firstFrame?.minX ?? junction.x,
                endX: own.last.flatMap { frames[$0.id]?.maxX } ?? junction.x,
                junction: junction, depth: absoluteDepth(category?.id),
                subtreeFrame: subtreeFrames[branchKey, default: .zero]
            )
        }
        branches = placedBranches
        let branchLookup = Dictionary(uniqueKeysWithValues: placedBranches.map { ($0.id, $0) })
        var segments: [Connection] = []

        // Horizontal continuations occupy only their own row and are always drawn first.
        for branch in placedBranches {
            let own = grouped[branch.id, default: []]
            for index in own.indices.dropFirst() {
                let before = frames[own[index - 1].id]!, after = frames[own[index].id]!
                segments += Self.smooth([CGPoint(x: before.maxX, y: before.midY), CGPoint(x: after.minX, y: after.midY)],
                                        id: branch.id + "-next-" + own[index].id.uuidString,
                                        source: own[index - 1].id, target: own[index].id, kind: .continuation, radius: 0)
            }
        }
        // Each side of an empty parent has one shared structural fallback, never cloned parallel cables.
        // The natural-curve pass below removes these trunks wherever a direct fan is safe.
        for branch in placedBranches {
            let descendants = treeChildren[branch.id, default: []]
            guard !descendants.isEmpty else { continue }
            let anchor = branch.junction
            let above = descendants.filter { childAnchor($0).y < anchor.y }.reversed()
            let below = descendants.filter { childAnchor($0).y >= anchor.y }
            for (side, orderedChildren) in [(CGFloat(-1), Array(above)), (CGFloat(1), below)] {
                guard !orderedChildren.isEmpty else { continue }
                if branch.firstRecordID == nil {
                    var trunkStart = anchor
                    for (index, childKey) in orderedChildren.enumerated() {
                        guard let child = branchLookup[childKey] else { continue }
                        let to = childAnchor(childKey)
                        let radius = min(6 * scale, max(0, (to.x - anchor.x) / 2), abs(to.y - anchor.y) / 2)
                        let fork = CGPoint(x: anchor.x, y: to.y - side * radius)
                        let relationship = child.id + "-fork"
                        let remaining = orderedChildren.dropFirst(index).map { $0 + "-fork" }
                        segments += Self.smooth([trunkStart, fork], id: branch.id + "-trunk-\(side)-\(index)",
                                                source: nil, target: nil, kind: .hierarchy, radius: 0,
                                                relationshipIDs: remaining, structuralBranchID: branch.id)
                        segments += Self.smooth([fork, CGPoint(x: fork.x, y: to.y), to], id: relationship,
                                                source: nil, target: child.firstRecordID, kind: .hierarchy, radius: radius,
                                                structuralBranchID: branch.id)
                        trunkStart = fork
                    }
                    continue
                }
                let sourceFrame = frames[branch.firstRecordID!]!
                // Upper fallbacks leave the first card's left port, clearing its heading; lower ones leave its bottom.
                let from = side < 0 ? CGPoint(x: sourceFrame.minX, y: sourceFrame.midY)
                    : CGPoint(x: sourceFrame.midX, y: sourceFrame.maxY)
                for (index, childKey) in orderedChildren.enumerated() {
                    guard let child = branchLookup[childKey] else { continue }
                    let to = childAnchor(childKey)
                    let channelX = channelBase[branch.id, default: from.x] - CGFloat(index + 1) * channelStep
                    let fanHeight = CGFloat(orderedChildren.count - index + 1) * fanStep
                    let turn = CGPoint(x: channelX, y: from.y + side * fanHeight)
                    let relationship = child.id + "-fork"
                    segments.append(Connection(
                        id: relationship + "-fan", from: from, to: turn,
                        control1: CGPoint(x: from.x, y: from.y + side * fanHeight / 2),
                        control2: CGPoint(x: channelX, y: turn.y - side * fanHeight / 2),
                        relationshipID: relationship, sourceRecordID: branch.firstRecordID,
                        targetRecordID: child.firstRecordID, kind: .hierarchy
                    ))
                    segments += Self.smooth([turn, CGPoint(x: channelX, y: to.y), to], id: relationship,
                                            source: branch.firstRecordID, target: child.firstRecordID,
                                            kind: .hierarchy, radius: 6 * scale)
                }
            }
        }
        let obstacles = placedNodes.map(\.frame) + placedBranches.map(\.labelFrame)
        func samples(_ curve: Connection, count: Int = 80) -> [CGPoint] {
            (0...count).map { step in
                let t = CGFloat(step) / CGFloat(count), u = 1 - t
                return CGPoint(
                    x: u * u * u * curve.from.x + 3 * u * u * t * curve.control1.x + 3 * u * t * t * curve.control2.x + t * t * t * curve.to.x,
                    y: u * u * u * curve.from.y + 3 * u * u * t * curve.control1.y + 3 * u * t * t * curve.control2.y + t * t * t * curve.to.y
                )
            }
        }
        func intersects(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, allowed: [CGPoint]) -> Bool {
            guard max(a.x, b.x) + 0.001 >= min(c.x, d.x), max(c.x, d.x) + 0.001 >= min(a.x, b.x),
                  max(a.y, b.y) + 0.001 >= min(c.y, d.y), max(c.y, d.y) + 0.001 >= min(a.y, b.y) else { return false }
            func cross(_ x: CGFloat, _ y: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGFloat { x * y2 - y * x2 }
            let x = b.x - a.x, y = b.y - a.y, x2 = d.x - c.x, y2 = d.y - c.y
            let denominator = cross(x, y, x2, y2)
            if abs(denominator) < 0.000_001 {
                guard abs(cross(c.x - a.x, c.y - a.y, x, y)) < 0.000_001 else { return false }
                let first = abs(x) > abs(y) ? [a.x, b.x].sorted() : [a.y, b.y].sorted()
                let second = abs(x) > abs(y) ? [c.x, d.x].sorted() : [c.y, d.y].sorted()
                return min(first[1], second[1]) - max(first[0], second[0]) > 0.001
            }
            let t = cross(c.x - a.x, c.y - a.y, x2, y2) / denominator
            let u = cross(c.x - a.x, c.y - a.y, x, y) / denominator
            guard t >= -0.000_001 && t <= 1.000_001 && u >= -0.000_001 && u <= 1.000_001 else { return false }
            let point = CGPoint(x: a.x + t * x, y: a.y + t * y)
            return !allowed.contains { hypot($0.x - point.x, $0.y - point.y) < 0.001 }
        }
        func isClear(_ candidate: Connection, source: CGRect?, target: CGRect?, otherRoutes: [Connection]) -> Bool {
            let points = samples(candidate)
            let walls = obstacles.map { frame in
                source.map({ frame == $0 }) == true || target.map({ frame == $0 }) == true
                    ? frame.insetBy(dx: 0.1, dy: 0.1) : frame.insetBy(dx: -3 * scale, dy: -3 * scale)
            }
            guard points.allSatisfy({ point in point.x >= 0 && point.y >= 0 && !walls.contains { $0.contains(point) } }) else { return false }
            for other in otherRoutes {
                let existing = samples(other, count: 24)
                let shared = [candidate.from, candidate.to].filter { port in
                    [other.from, other.to].contains { hypot($0.x - port.x, $0.y - port.y) < 0.001 }
                }
                for edge in zip(points, points.dropFirst()) {
                    for old in zip(existing, existing.dropFirst()) where intersects(edge.0, edge.1, old.0, old.1, allowed: shared) {
                        return false
                    }
                }
            }
            return true
        }
        // Keep each remaining fallback until a natural curve is clear. Shared trunk metadata is reduced
        // rather than deleting geometry still used by a sibling path.
        func removing(_ relationship: String, from routes: [Connection]) -> [Connection] {
            routes.compactMap { edge in
                let remaining = edge.relationshipIDs.filter { $0 != relationship }
                guard !remaining.isEmpty else { return nil }
                guard remaining.count != edge.relationshipIDs.count else { return edge }
                return Connection(id: edge.id, from: edge.from, to: edge.to, control1: edge.control1, control2: edge.control2,
                                  relationshipID: remaining[0], sourceRecordID: edge.sourceRecordID, targetRecordID: edge.targetRecordID,
                                  kind: edge.kind, relationshipIDs: remaining, structuralBranchID: edge.structuralBranchID)
            }
        }
        for branch in placedBranches {
            guard let parentID = branch.parentID, let parent = branchLookup[parentID] else { continue }
            let sourceID = parent.firstRecordID, targetID = branch.firstRecordID
            let source = sourceID.flatMap { frames[$0] }, target = targetID.flatMap { frames[$0] }
            let relationship = branch.id + "-fork"
            let otherRoutes = removing(relationship, from: segments)
            let sourceCenter = source.map { CGPoint(x: $0.midX, y: $0.midY) } ?? parent.junction
            let targetCenter = target.map { CGPoint(x: $0.midX, y: $0.midY) } ?? branch.junction
            let forward: CGFloat = targetCenter.x >= sourceCenter.x ? 1 : -1
            let side: CGFloat = targetCenter.y >= sourceCenter.y ? 1 : -1
            let horizontal = CGPoint(x: forward, y: 0), vertical = CGPoint(x: 0, y: side)
            let fromSide = source.map { CGPoint(x: forward > 0 ? $0.maxX : $0.minX, y: $0.midY) } ?? parent.junction
            let toSide = target.map { CGPoint(x: source == nil || forward > 0 ? $0.minX : $0.maxX, y: $0.midY) } ?? branch.junction
            let incoming = target == nil || source == nil ? CGPoint(x: 1, y: 0) : horizontal
            var ports: [(CGPoint, CGPoint, CGPoint, CGPoint)] = []
            if let source {
                let fromVertical = CGPoint(x: source.midX, y: side < 0 ? source.minY : source.maxY)
                ports = [(fromSide, toSide, horizontal, incoming), (fromVertical, toSide, vertical, incoming)]
                if let target {
                    let toVertical = CGPoint(x: target.midX, y: side < 0 ? target.maxY : target.minY)
                    ports += [(fromSide, toVertical, horizontal, vertical), (fromVertical, toVertical, vertical, vertical)]
                }
            } else {
                let outgoing = abs(targetCenter.y - sourceCenter.y) < 0.001 ? CGPoint(x: 1, y: 0) : vertical
                ports = [(parent.junction, toSide, outgoing, incoming)]
            }
            var replacement: Connection?
            for (from, to, outward, inward) in ports {
                let length = max(28 * scale, min(140 * scale, abs(to.x - from.x) * 0.45 + abs(to.y - from.y) * 0.1))
                var lengths = [CGFloat(1), 0.5, 1.5, 2.5].map { (length * $0, length) }
                if source == nil {
                    if abs(to.y - from.y) < 0.001 {
                        lengths.insert((abs(to.x - from.x) / 3, abs(to.x - from.x) / 3), at: 0)
                    } else {
                        lengths.insert((abs(to.y - from.y) * 0.7, max(20 * scale, min(100 * scale, abs(to.x - from.x) * 0.65))), at: 0)
                    }
                }
                for (outLength, inLength) in lengths {
                    let curve = Connection(
                        id: relationship + "-direct", from: from, to: to,
                        control1: CGPoint(x: from.x + outward.x * outLength, y: from.y + outward.y * outLength),
                        control2: CGPoint(x: to.x - inward.x * inLength, y: to.y - inward.y * inLength),
                        relationshipID: relationship, sourceRecordID: sourceID, targetRecordID: targetID, kind: .hierarchy,
                        structuralBranchID: source == nil ? parent.id : nil
                    )
                    if isClear(curve, source: source, target: target, otherRoutes: otherRoutes) {
                        replacement = curve
                        break
                    }
                }
                if replacement != nil { break }
            }
            if let replacement { segments = otherRoutes + [replacement] }
        }
        connections = segments
        var lastMonth: DateComponents?
        var monthTicks: [Tick] = []
        for record in ordered {
            let month = Calendar.current.dateComponents([.year, .month], from: record.occurredAt)
            guard month != lastMonth else { continue }
            lastMonth = month
            monthTicks.append(Tick(id: record.id.uuidString, date: record.occurredAt, x: frames[record.id]!.midX))
        }
        ticks = monthTicks
        let routeExtents = segments.map { edge -> CGRect in
            let points = samples(edge, count: 24)
            let left = points.map(\.x).min()!, top = points.map(\.y).min()!
            return CGRect(x: left, y: top, width: points.map(\.x).max()! - left, height: points.map(\.y).max()! - top)
        }
        let extents = placedNodes.map(\.frame) + placedBranches.map(\.subtreeFrame) + routeExtents
        size = CGSize(width: (extents.map(\.maxX).max() ?? cardWidth) + padding,
                      height: (extents.map(\.maxY).max() ?? defaultHeight) + padding)
    }

    private static func smooth(
        _ points: [CGPoint], id: String, source: UUID?, target: UUID?, kind: ConnectionKind, radius: CGFloat,
        relationshipIDs: [String]? = nil, structuralBranchID: String? = nil
    ) -> [Connection] {
        var path: [CGPoint] = []
        for point in points {
            guard path.last != point else { continue }
            if path.count > 1 {
                let a = path[path.count - 2], b = path[path.count - 1]
                if (a.x == b.x && b.x == point.x) || (a.y == b.y && b.y == point.y) { path.removeLast() }
            }
            path.append(point)
        }
        guard let first = path.first, let last = path.last, path.count > 1 else { return [] }
        var result: [Connection] = []
        func append(_ from: CGPoint, _ to: CGPoint, _ c1: CGPoint, _ c2: CGPoint) {
            guard from != to else { return }
            let relationships = relationshipIDs ?? [id]
            result.append(Connection(id: id + "-\(result.count)", from: from, to: to, control1: c1, control2: c2,
                                     relationshipID: relationships.first ?? id, sourceRecordID: source, targetRecordID: target,
                                     kind: kind, relationshipIDs: relationships, structuralBranchID: structuralBranchID))
        }
        func line(_ from: CGPoint, _ to: CGPoint) {
            append(from, to, CGPoint(x: from.x + (to.x - from.x) / 3, y: from.y + (to.y - from.y) / 3),
                   CGPoint(x: from.x + (to.x - from.x) * 2 / 3, y: from.y + (to.y - from.y) * 2 / 3))
        }
        var current = first
        for index in 1..<(path.count - 1) {
            let a = path[index - 1], b = path[index], c = path[index + 1]
            let length1 = hypot(b.x - a.x, b.y - a.y), length2 = hypot(c.x - b.x, c.y - b.y)
            let r = min(radius, length1 / 2, length2 / 2)
            let incoming = CGPoint(x: (b.x - a.x) / length1, y: (b.y - a.y) / length1)
            let outgoing = CGPoint(x: (c.x - b.x) / length2, y: (c.y - b.y) / length2)
            let before = CGPoint(x: b.x - incoming.x * r, y: b.y - incoming.y * r)
            let after = CGPoint(x: b.x + outgoing.x * r, y: b.y + outgoing.y * r)
            line(current, before)
            let k: CGFloat = 0.55228475
            append(before, after, CGPoint(x: before.x + incoming.x * r * k, y: before.y + incoming.y * r * k),
                   CGPoint(x: after.x - outgoing.x * r * k, y: after.y - outgoing.y * r * k))
            current = after
        }
        line(current, last)
        return result
    }
}
