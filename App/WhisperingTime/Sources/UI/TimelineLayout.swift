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

    /// One smooth segment of a relationship. Ordered segments share a relationshipID.
    struct Connection: Identifiable, Equatable {
        let id: String
        let from: CGPoint
        let to: CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let relationshipID: String
        let sourceRecordID: UUID?
        let targetRecordID: UUID?
        let kind: ConnectionKind
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
            let width = labelSizes[branchKey]?.width ?? labelWidth
            let height = labelSizes[branchKey]?.height ?? labelHeight
            result[branchKey] = CGSize(
                width: width.isFinite && width > 0 ? max(labelWidth, width) : labelWidth,
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

        // Each subtree owns one continuous band. Its narrow left gutter contains only its own forks;
        // descendants' gutters are nested to the right, so unrelated edges cannot weave through a group.
        var groupLeft: [String: CGFloat] = [:]
        var channelBase: [String: CGFloat] = [:]
        for branchKey in branchOrder.reversed() {
            let ownLeft = grouped[branchKey, default: []].compactMap { columnX[$0.id] }.min() ?? .greatestFiniteMagnitude
            let descendantLeft = treeChildren[branchKey, default: []].compactMap { groupLeft[$0] }.min() ?? .greatestFiniteMagnitude
            let innerLeft = min(ownLeft, descendantLeft)
            channelBase[branchKey] = innerLeft
            let cableCount = grouped[branchKey, default: []].isEmpty ? 0 : treeChildren[branchKey, default: []].filter {
                !grouped[$0, default: []].isEmpty
            }.count
            groupLeft[branchKey] = innerLeft - groupInset - CGFloat(cableCount) * channelStep
        }
        let horizontalShift = max(0, 4 * scale - (groupLeft.values.min() ?? padding))
        for id in Array(columnX.keys) { columnX[id, default: 0] += horizontalShift }
        for branchKey in branchOrder {
            groupLeft[branchKey, default: 0] += horizontalShift
            channelBase[branchKey, default: 0] += horizontalShift
        }

        var frames: [UUID: CGRect] = [:]
        var labelFrames: [String: CGRect] = [:]
        var junctions: [String: CGPoint] = [:]
        var subtreeFrames: [String: CGRect] = [:]
        func arrange(_ branchKey: String, top: CGFloat) -> CGFloat {
            let own = grouped[branchKey, default: []]
            let descendants = treeChildren[branchKey, default: []]
            let labelSize = measuredLabels[branchKey, default: CGSize(width: labelWidth, height: labelHeight)]
            var ownBottom: CGFloat
            if let first = own.first {
                let firstHeight = heights[first.id, default: defaultHeight]
                let maximumHeight = own.map { heights[$0.id, default: defaultHeight] }.max() ?? firstHeight
                var centerY = top + verticalInset + max(labelSize.height + labelGap + firstHeight / 2, maximumHeight / 2)
                var labelY = centerY - firstHeight / 2 - labelGap - labelSize.height
                let labelX = columnX[first.id, default: padding]
                // A rare measured label wider than a card must also clear later, taller content in this row.
                for record in own.dropFirst() {
                    let x = columnX[record.id, default: padding]
                    if x < labelX + labelSize.width {
                        labelY = min(labelY, centerY - heights[record.id, default: defaultHeight] / 2 - labelGap - labelSize.height)
                    }
                }
                if labelY < top + verticalInset {
                    centerY += top + verticalInset - labelY
                    labelY = top + verticalInset
                }
                labelFrames[branchKey] = CGRect(x: labelX, y: labelY, width: labelSize.width, height: labelSize.height)
                for record in own {
                    let height = heights[record.id, default: defaultHeight]
                    frames[record.id] = CGRect(x: columnX[record.id, default: padding], y: centerY - height / 2,
                                               width: cardWidth, height: height)
                }
                junctions[branchKey] = CGPoint(x: labelX + cardWidth / 2, y: centerY)
                ownBottom = centerY + maximumHeight / 2
            } else {
                let x = channelBase[branchKey, default: padding] + 8 * scale
                labelFrames[branchKey] = CGRect(x: x, y: top + verticalInset, width: labelSize.width, height: labelSize.height)
                junctions[branchKey] = CGPoint(x: x - 8 * scale, y: top + verticalInset + labelSize.height / 2)
                ownBottom = top + verticalInset + labelSize.height
            }
            let sourceY = own.first.flatMap { frames[$0.id]?.maxY } ?? junctions[branchKey, default: .zero].y
            let cableCount = own.isEmpty ? 0 : descendants.filter { !grouped[$0, default: []].isEmpty }.count
            let fanHeight = cableCount == 0 ? 0 : CGFloat(cableCount + 1) * fanStep
            var bottom = ownBottom
            if !descendants.isEmpty {
                var childTop = max(ownBottom, sourceY + fanHeight) + groupGap
                for child in descendants {
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
        for root in roots {
            nextTop = arrange(root, top: nextTop) + groupGap
        }
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
        // Ordered local channels give a planar tree even when a parent's first date is later than a child's.
        // Later sibling targets use the outer channels and turn sooner; curves share only the real source port.
        for branch in placedBranches {
            let descendants = treeChildren[branch.id, default: []].filter { !grouped[$0, default: []].isEmpty }
            // Empty ancestors use category names and contiguous subtree placement, never a second cable tree.
            guard !descendants.isEmpty, branch.firstRecordID != nil else { continue }
            let sourceFrame = branch.firstRecordID.flatMap { frames[$0] }
            let from = sourceFrame.map { CGPoint(x: $0.midX, y: $0.maxY) } ?? branch.junction
            for (index, childKey) in descendants.enumerated() {
                guard let child = branchLookup[childKey] else { continue }
                let targetFrame = child.firstRecordID.flatMap { frames[$0] }
                let to = targetFrame.map { CGPoint(x: $0.minX, y: $0.midY) } ?? child.junction
                let channelX = channelBase[branch.id, default: from.x] - CGFloat(index + 1) * channelStep
                let fanHeight = CGFloat(descendants.count - index + 1) * fanStep
                let turn = CGPoint(x: channelX, y: from.y + fanHeight)
                let relationship = child.id + "-fork"
                segments.append(Connection(
                    id: relationship + "-fan", from: from, to: turn,
                    control1: CGPoint(x: from.x, y: from.y + fanHeight / 2),
                    control2: CGPoint(x: channelX, y: turn.y - fanHeight / 2),
                    relationshipID: relationship, sourceRecordID: branch.firstRecordID,
                    targetRecordID: child.firstRecordID, kind: .hierarchy
                ))
                segments += Self.smooth([turn, CGPoint(x: channelX, y: to.y), to], id: relationship,
                                        source: branch.firstRecordID, target: child.firstRecordID,
                                        kind: .hierarchy, radius: 6 * scale)
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
        func isClear(_ candidate: Connection, source: CGRect, target: CGRect, otherRoutes: [Connection]) -> Bool {
            let points = samples(candidate)
            let walls = obstacles.map { frame in
                frame == source || frame == target ? frame.insetBy(dx: 0.1, dy: 0.1) : frame.insetBy(dx: -3 * scale, dy: -3 * scale)
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
        // Keep the planar fallback until a short natural curve is proven clear of all remaining routes.
        // This avoids a greedy direct edge trapping a later relationship into a crossing or an outer loop.
        for branch in placedBranches {
            guard let parentID = branch.parentID, let parent = branchLookup[parentID],
                  let sourceID = parent.firstRecordID, let targetID = branch.firstRecordID,
                  let source = frames[sourceID], let target = frames[targetID] else { continue }
            let relationship = branch.id + "-fork"
            let otherRoutes = segments.filter { $0.relationshipID != relationship }
            let forward: CGFloat = target.midX >= source.midX ? 1 : -1
            let horizontal = CGPoint(x: forward, y: 0), vertical = CGPoint(x: 0, y: 1)
            let sourceSide = CGPoint(x: forward > 0 ? source.maxX : source.minX, y: source.midY)
            let targetSide = CGPoint(x: forward > 0 ? target.minX : target.maxX, y: target.midY)
            let sourceBottom = CGPoint(x: source.midX, y: source.maxY)
            let targetTop = CGPoint(x: target.midX, y: target.minY)
            let ports: [(CGPoint, CGPoint, CGPoint, CGPoint)] = [
                (sourceSide, targetSide, horizontal, horizontal),
                (sourceBottom, targetSide, vertical, horizontal),
                (sourceSide, targetTop, horizontal, vertical),
                (sourceBottom, targetTop, vertical, vertical)
            ]
            var replacement: Connection?
            for (from, to, outward, inward) in ports {
                let length = max(28 * scale, min(140 * scale, abs(to.x - from.x) * 0.45 + abs(to.y - from.y) * 0.1))
                for factor in [CGFloat(1), 0.5, 1.5] {
                    let curve = Connection(
                        id: relationship + "-direct", from: from, to: to,
                        control1: CGPoint(x: from.x + outward.x * length * factor, y: from.y + outward.y * length * factor),
                        control2: CGPoint(x: to.x - inward.x * length, y: to.y - inward.y * length),
                        relationshipID: relationship, sourceRecordID: sourceID, targetRecordID: targetID, kind: .hierarchy
                    )
                    if isClear(curve, source: source, target: target, otherRoutes: otherRoutes) {
                        replacement = curve
                        break
                    }
                }
                if replacement != nil { break }
            }
            if let replacement {
                segments.removeAll { $0.relationshipID == relationship }
                segments.append(replacement)
            }
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

    private static func smooth(_ points: [CGPoint], id: String, source: UUID?, target: UUID?, kind: ConnectionKind, radius: CGFloat) -> [Connection] {
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
            result.append(Connection(id: id + "-\(result.count)", from: from, to: to, control1: c1, control2: c2,
                                     relationshipID: id, sourceRecordID: source, targetRecordID: target, kind: kind))
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
