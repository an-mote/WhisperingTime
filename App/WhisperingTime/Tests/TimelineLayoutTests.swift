import XCTest
import CoreGraphics
@testable import WhisperingTime

final class TimelineLayoutTests: XCTestCase {
    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func category(_ value: Int, parent: Int? = nil) -> CategoryNode {
        CategoryNode(id: id(value), parentID: parent.map(id), name: "分类\(value)")
    }

    private func record(_ value: Int, category: Int? = nil, time: TimeInterval) -> Imprint {
        Imprint(id: id(value), categoryID: category.map(id), occurredAt: Date(timeIntervalSince1970: time), body: "中文内容\(value)")
    }

    private func assertNoOverlaps(_ layout: TimelineLayout, file: StaticString = #filePath, line: UInt = #line) {
        for (index, node) in layout.nodes.enumerated() {
            XCTAssertTrue(node.frame.minX >= 0 && node.frame.minY >= 0, file: file, line: line)
            XCTAssertTrue(layout.size.width >= node.frame.maxX && layout.size.height >= node.frame.maxY, file: file, line: line)
            for other in layout.nodes.dropFirst(index + 1) {
                XCTAssertFalse(node.frame.intersects(other.frame), "\(node.id) intersects \(other.id)", file: file, line: line)
            }
        }
        for (index, branch) in layout.branches.enumerated() {
            XCTAssertGreaterThanOrEqual(branch.labelFrame.minX, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(branch.labelFrame.minY, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(branch.labelFrame.maxX, layout.size.width, file: file, line: line)
            XCTAssertLessThanOrEqual(branch.labelFrame.maxY, layout.size.height, file: file, line: line)
            XCTAssertFalse(layout.nodes.contains { $0.frame.intersects(branch.labelFrame) }, file: file, line: line)
            for other in layout.branches.dropFirst(index + 1) {
                XCTAssertFalse(branch.labelFrame.intersects(other.labelFrame), file: file, line: line)
            }
        }
        for connection in layout.connections {
            for step in 0...100 {
                let t = CGFloat(step) / 100
                let u = 1 - t
                let point = CGPoint(
                    x: u * u * u * connection.from.x + 3 * u * u * t * connection.control1.x + 3 * u * t * t * connection.control2.x + t * t * t * connection.to.x,
                    y: u * u * u * connection.from.y + 3 * u * u * t * connection.control1.y + 3 * u * t * t * connection.control2.y + t * t * t * connection.to.y
                )
                XCTAssertFalse(layout.nodes.contains { $0.frame.insetBy(dx: 0.1, dy: 0.1).contains(point) }, "A connection crosses a card: \(connection.id)", file: file, line: line)
                XCTAssertFalse(layout.branches.contains { $0.labelFrame.insetBy(dx: 0.1, dy: 0.1).contains(point) }, "A connection crosses a category label: \(connection.id)", file: file, line: line)
                XCTAssertGreaterThanOrEqual(point.x, 0, file: file, line: line)
                XCTAssertGreaterThanOrEqual(point.y, 0, file: file, line: line)
                XCTAssertLessThanOrEqual(point.x, layout.size.width, file: file, line: line)
                XCTAssertLessThanOrEqual(point.y, layout.size.height, file: file, line: line)
            }
        }
    }

    private func assertCardBoundary(_ point: CGPoint, frame: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let horizontal = abs(point.y - frame.midY) < 0.001 && (abs(point.x - frame.minX) < 0.001 || abs(point.x - frame.maxX) < 0.001)
        let vertical = abs(point.x - frame.midX) < 0.001 && (abs(point.y - frame.minY) < 0.001 || abs(point.y - frame.maxY) < 0.001)
        XCTAssertTrue(horizontal || vertical, file: file, line: line)
    }

    private func hierarchyPath(_ layout: TimelineLayout, to branch: TimelineLayout.Branch) -> [TimelineLayout.Connection] {
        layout.connections.filter { $0.relationshipIDs.contains(branch.id + "-fork") }
    }

    private func assertCompleteHierarchy(_ layout: TimelineLayout, file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = Set(layout.branches.filter { $0.parentID != nil }.map { $0.id + "-fork" })
        let actual = Set(layout.connections.filter { $0.kind == .hierarchy }.flatMap(\.relationshipIDs))
        XCTAssertEqual(actual, expected, "Every visible parent/child pair needs a continuous drawn path", file: file, line: line)
        for branch in layout.branches where branch.parentID != nil {
            let parent = try XCTUnwrap(layout.branches.first { $0.id == branch.parentID }, file: file, line: line)
            let path = hierarchyPath(layout, to: branch)
            let first = try XCTUnwrap(path.first, file: file, line: line)
            let last = try XCTUnwrap(path.last, file: file, line: line)
            if let id = parent.firstRecordID {
                let source = try XCTUnwrap(layout.nodes.first { $0.id == id }, file: file, line: line)
                assertCardBoundary(first.from, frame: source.frame, file: file, line: line)
                XCTAssertEqual(first.sourceRecordID, id, file: file, line: line)
            } else {
                XCTAssertEqual(first.from, parent.junction, file: file, line: line)
            }
            if let id = branch.firstRecordID {
                let target = try XCTUnwrap(layout.nodes.first { $0.id == id }, file: file, line: line)
                assertCardBoundary(last.to, frame: target.frame, file: file, line: line)
                XCTAssertEqual(last.targetRecordID, id, file: file, line: line)
            } else {
                XCTAssertEqual(last.to, branch.junction, file: file, line: line)
            }
            for (before, after) in zip(path, path.dropFirst()) {
                XCTAssertEqual(before.to, after.from, "A parent/child branch must not have a gap", file: file, line: line)
            }
        }
    }

    /// Each connection is drawn once, even when several semantic paths use a shared trunk.
    /// Separate physical segments may touch at declared route joins, structural forks or real card ports.
    private func assertNoCrossingRelationships(_ layout: TimelineLayout, file: StaticString = #filePath, line: UInt = #line) {
        struct Edge {
            let from: CGPoint
            let to: CGPoint
            let connection: TimelineLayout.Connection
        }
        func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.y - a.y * b.x }
        func minus(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
        func same(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 0.001 }
        func isCardPort(_ point: CGPoint) -> Bool {
            layout.nodes.contains { node in
                let rect = node.frame
                return same(point, CGPoint(x: rect.minX, y: rect.midY)) || same(point, CGPoint(x: rect.maxX, y: rect.midY))
                    || same(point, CGPoint(x: rect.midX, y: rect.minY)) || same(point, CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
        XCTAssertEqual(Set(layout.connections.map(\.id)).count, layout.connections.count, file: file, line: line)
        let edges = layout.connections.flatMap { connection -> [Edge] in
            let samples = (0...24).map { step -> CGPoint in
                let t = CGFloat(step) / 24, u = 1 - t
                return CGPoint(
                    x: u * u * u * connection.from.x + 3 * u * u * t * connection.control1.x + 3 * u * t * t * connection.control2.x + t * t * t * connection.to.x,
                    y: u * u * u * connection.from.y + 3 * u * u * t * connection.control1.y + 3 * u * t * t * connection.control2.y + t * t * t * connection.to.y
                )
            }
            return zip(samples, samples.dropFirst()).map { Edge(from: $0.0, to: $0.1, connection: connection) }
        }
        for (index, edge) in edges.enumerated() {
            for other in edges.dropFirst(index + 1) where edge.connection.id != other.connection.id {
                guard max(edge.from.x, edge.to.x) + 0.001 >= min(other.from.x, other.to.x),
                      max(other.from.x, other.to.x) + 0.001 >= min(edge.from.x, edge.to.x),
                      max(edge.from.y, edge.to.y) + 0.001 >= min(other.from.y, other.to.y),
                      max(other.from.y, other.to.y) + 0.001 >= min(edge.from.y, edge.to.y) else { continue }
                let a = minus(edge.to, edge.from), b = minus(other.to, other.from)
                let delta = minus(other.from, edge.from), denominator = cross(a, b)
                if abs(denominator) < 0.000_001 {
                    guard abs(cross(delta, a)) < 0.000_001 else { continue }
                    let useX = abs(a.x) > abs(a.y)
                    let first = [useX ? edge.from.x : edge.from.y, useX ? edge.to.x : edge.to.y].sorted()
                    let second = [useX ? other.from.x : other.from.y, useX ? other.to.x : other.to.y].sorted()
                    XCTAssertLessThanOrEqual(min(first[1], second[1]) - max(first[0], second[0]), 0.001,
                                             "A shared trunk must be drawn once: \(edge.connection.id) / \(other.connection.id)", file: file, line: line)
                    continue
                }
                let t = cross(delta, b) / denominator, u = cross(delta, a) / denominator
                guard t >= -0.000_001 && t <= 1.000_001 && u >= -0.000_001 && u <= 1.000_001 else { continue }
                let point = CGPoint(x: edge.from.x + t * a.x, y: edge.from.y + t * a.y)
                let atDeclaredEndpoints = [edge.connection.from, edge.connection.to].contains { same($0, point) }
                    && [other.connection.from, other.connection.to].contains { same($0, point) }
                let samePath = !Set(edge.connection.relationshipIDs).isDisjoint(with: other.connection.relationshipIDs)
                let sameStructure = edge.connection.structuralBranchID != nil
                    && edge.connection.structuralBranchID == other.connection.structuralBranchID
                let emptyCategoryPort = layout.branches.contains { $0.firstRecordID == nil && same($0.junction, point) }
                XCTAssertTrue(atDeclaredEndpoints && (samePath || sameStructure || isCardPort(point) || emptyCategoryPort),
                              "Crossed branches: \(edge.connection.id) / \(other.connection.id) at \(point)", file: file, line: line)
            }
        }
    }

    func testHierarchyForksFromTheParentsFirstCardToTheChildsFirstCard() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 1), category(4, parent: 2), category(5)]
        let records = [record(101, category: 1, time: 50), record(102, category: 2, time: 10), record(103, category: 3, time: 20), record(104, category: 4, time: 30), record(105, category: 4, time: 40)]
        let layout = TimelineLayout(categories: categories, records: records)
        XCTAssertEqual(Set(layout.nodes.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(layout.nodes.count, records.count)
        XCTAssertFalse(layout.branches.contains { $0.categoryID == id(5) })
        let root = try XCTUnwrap(layout.branches.first { $0.categoryID == id(1) })
        let upper = try XCTUnwrap(layout.branches.first { $0.categoryID == id(2) })
        let lower = try XCTUnwrap(layout.branches.first { $0.categoryID == id(3) })
        XCTAssertLessThan(upper.y, root.y)
        XCTAssertGreaterThan(lower.y, root.y)
        XCTAssertEqual(layout.branches.map(\.categoryID), [id(1), id(2), id(4), id(3)])
        for branch in layout.branches where branch.parentID != nil {
            let parent = try XCTUnwrap(layout.branches.first { $0.id == branch.parentID })
            let source = try XCTUnwrap(layout.nodes.first { $0.id == parent.firstRecordID })
            let target = try XCTUnwrap(layout.nodes.first { $0.id == branch.firstRecordID })
            let route = hierarchyPath(layout, to: branch)
            let first = try XCTUnwrap(route.first), last = try XCTUnwrap(route.last)
            XCTAssertEqual(first.kind, .hierarchy)
            XCTAssertEqual(first.sourceRecordID, parent.firstRecordID)
            XCTAssertEqual(last.targetRecordID, branch.firstRecordID)
            assertCardBoundary(first.from, frame: source.frame)
            assertCardBoundary(last.to, frame: target.frame)
            for (before, after) in zip(route, route.dropFirst()) { XCTAssertEqual(before.to, after.from) }
        }
        XCTAssertEqual(Set(layout.connections.filter { $0.kind == .hierarchy }.flatMap(\.relationshipIDs)).count, 3)
        XCTAssertEqual(Set(layout.connections.filter { $0.kind == .continuation }.flatMap(\.relationshipIDs)).count, 1)
        assertNoOverlaps(layout)
    }

    func testChildCanPrecedeParentWithoutChangingDatesOrReversingTime() throws {
        let categories = [category(1), category(2, parent: 1)]
        let child = record(102, category: 2, time: 1)
        let parent = record(101, category: 1, time: 1_000_000_000)
        let layout = TimelineLayout(categories: categories, records: [parent, child])
        XCTAssertEqual(layout.orderedIDs, [child.id, parent.id])
        XCTAssertLessThan(try XCTUnwrap(layout.nodes.first { $0.id == child.id }).frame.minX,
                          try XCTUnwrap(layout.nodes.first { $0.id == parent.id }).frame.minX)
        XCTAssertEqual(parent.occurredAt, Date(timeIntervalSince1970: 1_000_000_000))
        let route = layout.connections.filter { $0.kind == .hierarchy }
        let first = try XCTUnwrap(route.first), last = try XCTUnwrap(route.last)
        XCTAssertEqual(first.sourceRecordID, parent.id)
        XCTAssertEqual(last.targetRecordID, child.id)
        assertCardBoundary(first.from, frame: try XCTUnwrap(layout.nodes.first { $0.id == parent.id }).frame)
        assertCardBoundary(last.to, frame: try XCTUnwrap(layout.nodes.first { $0.id == child.id }).frame)
        assertNoOverlaps(layout)
    }

    func testEmptyAncestorsRemainStructuralAndCompletelyEmptyTreesDisappear() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 2), category(4), category(5, parent: 4)]
        let layout = TimelineLayout(categories: categories, records: [record(101, category: 3, time: 1)])
        XCTAssertEqual(Set(layout.branches.compactMap(\.categoryID)), [id(1), id(2), id(3)])
        XCTAssertEqual(layout.branches.filter { $0.firstRecordID == nil }.count, 2)
        XCTAssertEqual(layout.nodes.count, 1)
        XCTAssertEqual(Set(layout.connections.flatMap(\.relationshipIDs)).count, 2)
        try assertCompleteHierarchy(layout)
        let leafOnly = TimelineLayout(categories: [category(3)], records: [record(101, category: 3, time: 1)])
        XCTAssertLessThanOrEqual(layout.size.height - leafOnly.size.height, 2 * (24 + 16 + 32) + 1)
        let emptyLabelWidth = layout.branches.filter { $0.firstRecordID == nil }.reduce(CGFloat.zero) { $0 + $1.labelFrame.width + 24 }
        XCTAssertLessThanOrEqual(layout.nodes.first!.frame.minX, 20 + emptyLabelWidth)
        for branch in layout.branches where branch.firstRecordID == nil {
            XCTAssertEqual(branch.startX, branch.endX)
            XCTAssertEqual(branch.junction.x, branch.labelFrame.minX - 8, accuracy: 0.001)
            XCTAssertEqual(branch.junction.y, branch.labelFrame.maxY + 8, accuracy: 0.001)
        }
        let nested = try XCTUnwrap(layout.branches.first { $0.categoryID == id(2) })
        let root = try XCTUnwrap(layout.branches.first { $0.categoryID == id(1) })
        XCTAssertTrue(root.subtreeFrame.contains(nested.subtreeFrame))
        XCTAssertFalse(hierarchyPath(layout, to: nested).isEmpty)
        assertNoOverlaps(layout)
        let empty = TimelineLayout(categories: categories, records: [])
        XCTAssertTrue(empty.nodes.isEmpty && empty.branches.isEmpty && empty.ticks.isEmpty && empty.connections.isEmpty)
    }

    func testUnclassifiedAndMultipleRootsShareTheCompressedTimeCoordinate() throws {
        let categories = [category(1), category(2)]
        let layout = TimelineLayout(categories: categories, records: [record(101, category: 1, time: 0), record(102, time: 1), record(103, category: 2, time: 10_000_000_000)])
        XCTAssertEqual(layout.branches.count, 3)
        XCTAssertEqual(layout.branches.filter { $0.parentID == nil }.count, 3)
        XCTAssertEqual(layout.branches.first { $0.categoryID == nil }?.name, "未分类")
        let xs = layout.nodes.map(\.frame.minX)
        XCTAssertEqual(xs[1] - xs[0], xs[2] - xs[1], accuracy: 0.001)
        assertNoOverlaps(layout)
    }

    func testIdenticalDatesUseUUIDOrderAndStablePositions() {
        let records = [record(104, time: 4), record(102, time: 4), record(103, time: 4), record(101, time: 4)]
        let first = TimelineLayout(categories: [], records: records)
        let second = TimelineLayout(categories: [], records: Array(records.reversed()))
        XCTAssertEqual(first.orderedIDs, [id(101), id(102), id(103), id(104)])
        XCTAssertEqual(first.nodes, second.nodes)
        XCTAssertEqual(first.ticks.count, 1)
        assertNoOverlaps(first)
    }

    func testCategoryScopeKeepsDescendantsAndUnclassifiedScopeKeepsOnlyLooseRecords() {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 2), category(4)]
        let records = [record(101, category: 1, time: 1), record(102, category: 2, time: 2), record(103, category: 3, time: 3), record(104, category: 4, time: 4), record(105, time: 5)]
        let subtree = TimelineLayout(categories: categories, records: records, scope: .category(id(2)))
        XCTAssertEqual(Set(subtree.nodes.map(\.id)), [id(102), id(103)])
        XCTAssertEqual(Set(subtree.branches.compactMap(\.categoryID)), [id(2), id(3)])
        XCTAssertNil(subtree.branches.first { $0.categoryID == id(2) }?.parentID)
        XCTAssertEqual(subtree.branches.first { $0.categoryID == id(2) }?.depth, 1)
        XCTAssertEqual(subtree.branches.first { $0.categoryID == id(3) }?.depth, 2)
        let loose = TimelineLayout(categories: categories, records: records, scope: .unclassified)
        XCTAssertEqual(loose.nodes.map(\.id), [id(105)])
        XCTAssertEqual(loose.branches.count, 1)
        assertNoOverlaps(subtree)
        assertNoOverlaps(loose)
    }

    func testMovingCategoryAndDeletingItsFirstRecordRebuildsConnections() throws {
        var categories = [category(1), category(2), category(3, parent: 1)]
        let first = record(101, category: 3, time: 1)
        let second = record(102, category: 3, time: 2)
        let root = record(103, category: 2, time: 3)
        let before = TimelineLayout(categories: categories, records: [first, second, root])
        let childID = try XCTUnwrap(before.branches.first { $0.categoryID == id(3) }).id
        categories[2].parentID = id(2)
        let after = TimelineLayout(categories: categories, records: [second, root])
        let child = try XCTUnwrap(after.branches.first { $0.id == childID })
        XCTAssertEqual(child.firstRecordID, second.id)
        XCTAssertEqual(child.parentID, after.branches.first { $0.categoryID == id(2) }?.id)
        XCTAssertFalse(after.branches.contains { $0.categoryID == id(1) })
        XCTAssertFalse(after.nodes.contains { $0.id == first.id })
        let frame = try XCTUnwrap(after.nodes.first { $0.id == second.id }).frame
        let route = hierarchyPath(after, to: child)
        assertCardBoundary(try XCTUnwrap(route.last).to, frame: frame)
        assertNoOverlaps(after)
    }

    func testMeasuredLargeCardsAndDoubleTextScaleRemainSeparated() {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 1)]
        let records = (101...108).map { record($0, category: $0 % 3 + 1, time: TimeInterval($0)) }
        let sizes = Dictionary(uniqueKeysWithValues: records.enumerated().map { index, record in
            (record.id, CGSize(width: 472, height: CGFloat(index % 3 + 1) * 140))
        })
        let layout = TimelineLayout(categories: categories, records: records, nodeSizes: sizes, textScale: 2)
        XCTAssertEqual(layout.nodeWidth, 472)
        XCTAssertTrue(layout.nodes.allSatisfy { $0.frame.width == 472 })
        XCTAssertTrue(layout.branches.allSatisfy { $0.labelFrame.width == 352 })
        assertNoOverlaps(layout)
    }

    func testMonthlyTicksAndSiblingLanesRemainStableWhenInputOrderChanges() {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 1)]
        let january = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 15))!
        let march = Calendar.current.date(from: DateComponents(year: 2025, month: 3, day: 15))!
        let records = [record(101, category: 2, time: january.timeIntervalSince1970), record(102, category: 3, time: january.timeIntervalSince1970 + 1), record(103, category: 2, time: march.timeIntervalSince1970)]
        let first = TimelineLayout(categories: categories, records: records)
        let reversed = TimelineLayout(categories: Array(categories.reversed()), records: Array(records.reversed()))
        XCTAssertEqual(first.branches, reversed.branches)
        XCTAssertEqual(first.nodes, reversed.nodes)
        XCTAssertEqual(first.ticks.map(\.date), [january, march])
        XCTAssertLessThan(first.ticks[0].x, first.ticks[1].x)
    }

    func testMeasuredLongChineseLabelsFitTheirOwnLanesAtDoubleTextScale() throws {
        let categories = [
            CategoryNode(id: id(1), name: String(repeating: "与家人一起走过的每一段日常", count: 12)),
            category(2, parent: 1), category(3, parent: 1)
        ]
        let records = [record(101, category: 2, time: 1), record(102, category: 3, time: 2)]
        let initial = TimelineLayout(categories: categories, records: records, textScale: 2)
        let longBranch = try XCTUnwrap(initial.branches.first { $0.categoryID == id(1) })
        let labels = [longBranch.id: CGSize(width: 352, height: 920)]
        let layout = TimelineLayout(categories: categories, records: records, labelSizes: labels, textScale: 2)
        XCTAssertEqual(layout.branches.first { $0.id == longBranch.id }?.labelFrame.height, 920)
        for (index, branch) in layout.branches.enumerated() {
            XCTAssertGreaterThanOrEqual(branch.labelFrame.minY, 0)
            if branch.firstRecordID != nil {
                XCTAssertLessThanOrEqual(branch.labelFrame.maxY, branch.y)
            } else {
                XCTAssertEqual(branch.junction.y, branch.labelFrame.maxY + 16, accuracy: 0.001)
                XCTAssertEqual(branch.junction.x, branch.labelFrame.minX - 16, accuracy: 0.001)
            }
            XCTAssertLessThanOrEqual(branch.labelFrame.maxY, layout.size.height)
            XCTAssertLessThanOrEqual(branch.labelFrame.maxX, layout.size.width)
            for other in layout.branches.dropFirst(index + 1) {
                XCTAssertFalse(branch.labelFrame.intersects(other.labelFrame))
            }
            for node in layout.nodes {
                XCTAssertFalse(branch.labelFrame.intersects(node.frame))
            }
        }
        try assertCompleteHierarchy(layout)
        assertNoOverlaps(layout)
        assertNoCrossingRelationships(layout)
    }

    func testTallCardKeepsItsWholeBranchAndFollowingSubtreesInSeparateBands() {
        let categories = [category(1), category(2), category(3)]
        let records = [record(101, category: 1, time: 1), record(102, category: 2, time: 2), record(103, category: 1, time: 3), record(104, category: 3, time: 4)]
        let layout = TimelineLayout(categories: categories, records: records, nodeSizes: [id(101): CGSize(width: 236, height: 900)])
        let frames = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame) })
        XCTAssertGreaterThan(frames[id(104)]!.minX, frames[id(101)]!.maxX)
        XCTAssertEqual(frames[id(101)]!.midY, frames[id(103)]!.midY)
        XCTAssertLessThan(frames[id(101)]!.maxY, frames[id(102)]!.minY)
        XCTAssertLessThan(frames[id(102)]!.maxY, frames[id(104)]!.minY)
        XCTAssertLessThan(layout.size.height, 1_600)
        assertNoOverlaps(layout)
    }

    func testOldLabelMeasurementCannotNarrowTheCurrentTextScale() throws {
        let categories = [category(1), category(2)]
        let records = [record(101, category: 1, time: 1), record(102, category: 2, time: 2)]
        let initial = TimelineLayout(categories: categories, records: records)
        let firstBranch = try XCTUnwrap(initial.branches.first { $0.categoryID == id(1) })
        let secondBranch = try XCTUnwrap(initial.branches.first { $0.categoryID == id(2) })
        let layout = TimelineLayout(
            categories: categories, records: records,
            labelSizes: [firstBranch.id: CGSize(width: 176, height: 52), secondBranch.id: CGSize(width: 420, height: 104)],
            textScale: 2
        )
        XCTAssertEqual(layout.branches.first { $0.id == firstBranch.id }?.labelFrame.width, 352)
        XCTAssertEqual(layout.branches.first { $0.id == secondBranch.id }?.labelFrame.width, 420)
        assertNoOverlaps(layout)
    }

    func testLabelsStayAttachedAndEmptyChainsReserveOnlyTheirMeasuredNameWidths() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 2), category(4, parent: 3)]
        let records = [record(101, category: 4, time: 1), record(102, category: 4, time: 2)]
        let layout = TimelineLayout(categories: categories, records: records)
        let leaf = try XCTUnwrap(layout.branches.first { $0.categoryID == id(4) })
        let first = try XCTUnwrap(layout.nodes.first { $0.id == leaf.firstRecordID })
        let measuredNames = layout.branches.filter { $0.firstRecordID == nil }.reduce(CGFloat.zero) { $0 + $1.labelFrame.width + 24 }
        XCTAssertLessThanOrEqual(first.frame.minX, 20 + measuredNames)
        XCTAssertEqual(leaf.labelFrame.minX, first.frame.minX)
        XCTAssertEqual(first.frame.minY - leaf.labelFrame.maxY, 10, accuracy: 0.001)
        XCTAssertLessThan(layout.size.width, 880)
        XCTAssertEqual(layout.branches.filter { $0.firstRecordID != nil }.count, 1)
        XCTAssertEqual(Set(layout.connections.filter { $0.kind == .continuation }.flatMap(\.relationshipIDs)).count, 1)
        assertNoOverlaps(layout)
    }

    func testInterleavedLanesShareColumnsButSameLaneCardsKeepTheirGap() {
        let categories = [category(1), category(2), category(3)]
        let records = [record(101, category: 1, time: 1), record(102, category: 2, time: 2), record(103, category: 3, time: 3), record(104, category: 1, time: 4)]
        let layout = TimelineLayout(categories: categories, records: records)
        let frames = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.id, $0.frame) })
        XCTAssertLessThan(frames[id(102)]!.minX, frames[id(101)]!.maxX)
        XCTAssertLessThan(frames[id(103)]!.minX, frames[id(102)]!.maxX)
        XCTAssertGreaterThanOrEqual(frames[id(104)]!.minX - frames[id(101)]!.maxX, 24)
        XCTAssertTrue(zip(layout.nodes, layout.nodes.dropFirst()).allSatisfy { $0.0.frame.minX < $0.1.frame.minX })
        assertNoOverlaps(layout)
    }

    func testFortyInterleavedRecordsRouteEveryRelationshipWithoutCrossingContent() throws {
        let categories = [category(1)] + (2...7).map { category($0, parent: 1) }
        let records = (0..<40).map { index in record(101 + index, category: index % 7 + 1, time: TimeInterval(index)) }
        let layout = TimelineLayout(categories: categories, records: records)
        XCTAssertEqual(layout.nodes.count, 40)
        XCTAssertEqual(Set(layout.connections.flatMap(\.relationshipIDs)).count, 39)
        try assertCompleteHierarchy(layout)
        for branch in layout.branches {
            let first = try XCTUnwrap(layout.nodes.first { $0.id == branch.firstRecordID })
            XCTAssertEqual(first.frame.minY - branch.labelFrame.maxY, 10, accuracy: 0.001)
            if branch.parentID != nil {
                XCTAssertFalse(hierarchyPath(layout, to: branch).isEmpty)
            }
        }
        assertNoOverlaps(layout)
        assertNoCrossingRelationships(layout)
    }

    func testFiveRecordCompositionUsesWindowWidthAndKeepsTheOldestRecordNearTheFirstScreen() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 2), category(4, parent: 3), category(5, parent: 1), category(6, parent: 3)]
        let records = [record(101, time: 1), record(102, category: 3, time: 2), record(103, category: 5, time: 3), record(104, category: 6, time: 4), record(105, category: 4, time: 5)]
        let initial = TimelineLayout(categories: categories, records: records)
        let labels = Dictionary(uniqueKeysWithValues: initial.branches.map {
            ($0.id, CGSize(width: $0.firstRecordID == nil ? 42 : 176, height: $0.firstRecordID == nil ? 15 : 18))
        })
        let cards = Dictionary(uniqueKeysWithValues: records.map {
            ($0.id, CGSize(width: 236, height: $0.id == id(104) ? 200 : 116))
        })
        let layout = TimelineLayout(categories: categories, records: records, nodeSizes: cards, labelSizes: labels)
        XCTAssertGreaterThanOrEqual(layout.size.width, 880)
        XCTAssertLessThan(layout.size.width, 1_100)
        XCTAssertLessThanOrEqual(layout.size.height, 1_150)
        let oldest = try XCTUnwrap(layout.nodes.first { $0.id == id(101) })
        XCTAssertLessThan(oldest.frame.minX, 100)
        XCTAssertLessThanOrEqual(oldest.frame.maxY, 200)
        XCTAssertEqual(layout.branches.first?.name, "未分类")
        XCTAssertTrue(zip(layout.nodes, layout.nodes.dropFirst()).allSatisfy { $0.1.frame.minX - $0.0.frame.minX >= 160 })
        let root = try XCTUnwrap(layout.branches.first { $0.categoryID == id(1) })
        let nested = try XCTUnwrap(layout.branches.first { $0.categoryID == id(2) })
        XCTAssertTrue(root.subtreeFrame.contains(nested.subtreeFrame))
        try assertCompleteHierarchy(layout)
        assertNoCrossingRelationships(layout)
        assertNoOverlaps(layout)
    }

    func testEmptyAncestorBranchesClearWideNeighborLabels() throws {
        let categories = [category(1), category(2), category(3, parent: 2), category(4, parent: 3), category(5)]
        let records = [record(101, category: 1, time: 1), record(102, category: 5, time: 2), record(103, category: 4, time: 3)]
        let initial = TimelineLayout(categories: categories, records: records)
        let neighbor = try XCTUnwrap(initial.branches.first { $0.categoryID == id(1) })
        let layout = TimelineLayout(categories: categories, records: records,
                                    labelSizes: [neighbor.id: CGSize(width: 310, height: 300)])
        for branch in layout.branches where branch.firstRecordID == nil {
            XCTAssertFalse(layout.nodes.contains { $0.frame.contains(branch.junction) })
            XCTAssertFalse(layout.branches.contains { $0.labelFrame.contains(branch.junction) })
            if let parentID = branch.parentID {
                let parent = try XCTUnwrap(layout.branches.first { $0.id == parentID })
                XCTAssertTrue(parent.subtreeFrame.contains(branch.subtreeFrame))
                XCTAssertFalse(hierarchyPath(layout, to: branch).isEmpty)
            }
        }
        assertNoOverlaps(layout)
    }

    func testThreeLevelSiblingSubtreesRemainContiguousAndAllCablesStaySeparate() throws {
        let categories = [
            category(1), category(2, parent: 1), category(3, parent: 1), category(4, parent: 1),
            category(5, parent: 2), category(6, parent: 2), category(7, parent: 3), category(8, parent: 3),
            category(9, parent: 4), category(10, parent: 4)
        ]
        // Parents 1 and 3 occur after their descendants; sibling subtrees still cannot interleave.
        let records = (1...10).map { value in
            record(100 + value, category: value, time: TimeInterval(value == 1 ? 80 : value == 3 ? 90 : value))
        }
        let layout = TimelineLayout(categories: categories, records: records)
        XCTAssertEqual(layout.branches.map(\.categoryID), [id(1), id(2), id(5), id(6), id(3), id(7), id(8), id(4), id(9), id(10)])
        XCTAssertEqual(Set(layout.connections.filter { $0.kind == .hierarchy }.flatMap(\.relationshipIDs)).count, 9)
        try assertCompleteHierarchy(layout)
        let root = try XCTUnwrap(layout.branches.first { $0.categoryID == id(1) })
        XCTAssertEqual(root.depth, 0)
        for branch in layout.branches.dropFirst() {
            let parent = try XCTUnwrap(layout.branches.first { $0.id == branch.parentID })
            XCTAssertEqual(branch.depth, parent.depth + 1)
            XCTAssertTrue(parent.subtreeFrame.contains(branch.subtreeFrame))
            let route = hierarchyPath(layout, to: branch)
            let parentCard = try XCTUnwrap(layout.nodes.first { $0.id == parent.firstRecordID })
            let childCard = try XCTUnwrap(layout.nodes.first { $0.id == branch.firstRecordID })
            assertCardBoundary(try XCTUnwrap(route.first).from, frame: parentCard.frame)
            assertCardBoundary(try XCTUnwrap(route.last).to, frame: childCard.frame)
        }
        let siblingGroups = layout.branches.filter { $0.parentID == root.id }
        for (before, after) in zip(siblingGroups, siblingGroups.dropFirst()) {
            XCTAssertLessThan(before.subtreeFrame.maxY, after.subtreeFrame.minY)
        }
        assertNoOverlaps(layout)
        assertNoCrossingRelationships(layout)
    }

    func testFortyRecordsWithInvertedParentsKeepEveryContinuationStraightAndEveryForkPlanar() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 1),
                          category(4, parent: 2), category(5, parent: 2), category(6, parent: 3), category(7, parent: 3)]
        let records = (0..<40).map { index in
            let lane = index % 7 + 1
            return record(101 + index, category: lane, time: TimeInterval(index + (lane == 1 || lane == 3 ? 100 : 0)))
        }
        let sizes = Dictionary(uniqueKeysWithValues: records.enumerated().map { offset, record in
            (record.id, CGSize(width: 236, height: CGFloat(90 + offset % 4 * 40)))
        })
        let layout = TimelineLayout(categories: categories, records: records, nodeSizes: sizes)
        XCTAssertEqual(layout.nodes.count, 40)
        XCTAssertEqual(Set(layout.connections.flatMap(\.relationshipIDs)).count, 39)
        try assertCompleteHierarchy(layout)
        for branch in layout.branches {
            let own = layout.nodes.filter { $0.branchID == branch.id }
            let y = try XCTUnwrap(own.first).frame.midY
            XCTAssertTrue(own.allSatisfy { abs($0.frame.midY - y) < 0.001 })
        }
        for continuation in layout.connections where continuation.kind == .continuation {
            XCTAssertEqual(continuation.from.y, continuation.to.y, accuracy: 0.001)
            XCTAssertEqual(continuation.control1.y, continuation.from.y, accuracy: 0.001)
            XCTAssertEqual(continuation.control2.y, continuation.from.y, accuracy: 0.001)
        }
        assertNoOverlaps(layout)
        assertNoCrossingRelationships(layout)
    }


    func testContentParentConnectsEveryEmptyChildAndItsDescendantsFromTheRealFirstCard() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 2)]
        let layout = TimelineLayout(categories: categories, records: [record(101, category: 1, time: 3), record(102, category: 3, time: 1)])
        let parent = try XCTUnwrap(layout.branches.first { $0.categoryID == id(1) })
        let emptyChild = try XCTUnwrap(layout.branches.first { $0.categoryID == id(2) })
        let leaf = try XCTUnwrap(layout.branches.first { $0.categoryID == id(3) })
        try assertCompleteHierarchy(layout)
        assertNoCrossingRelationships(layout)
        XCTAssertEqual(emptyChild.parentID, parent.id)
        XCTAssertEqual(leaf.parentID, emptyChild.id)
        XCTAssertTrue(parent.subtreeFrame.contains(emptyChild.subtreeFrame))
        XCTAssertTrue(emptyChild.subtreeFrame.contains(leaf.subtreeFrame))
        XCTAssertEqual(layout.branches.map(\.depth), [0, 1, 2])
        assertNoOverlaps(layout)
    }


    func testFiveRecordTreeKeepsLifeToWorkSeparateFromThePersonalFirstCardFork() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 2),
                          category(4, parent: 3), category(5, parent: 3), category(6, parent: 1)]
        let records = [record(101, time: 0), record(102, category: 3, time: 10), record(103, category: 6, time: 20),
                       record(104, category: 5, time: 30), record(105, category: 4, time: 40)]
        let layout = TimelineLayout(categories: categories, records: records)
        let life = try XCTUnwrap(layout.branches.first { $0.categoryID == id(1) })
        let family = try XCTUnwrap(layout.branches.first { $0.categoryID == id(2) })
        let personal = try XCTUnwrap(layout.branches.first { $0.categoryID == id(3) })
        let work = try XCTUnwrap(layout.branches.first { $0.categoryID == id(6) })
        XCTAssertEqual(work.parentID, life.id)
        XCTAssertEqual(personal.parentID, family.id)
        let familyPath = hierarchyPath(layout, to: family)
        let personalPath = hierarchyPath(layout, to: personal)
        XCTAssertEqual(familyPath.last?.to, personalPath.first?.from)
        XCTAssertTrue(hierarchyPath(layout, to: work).allSatisfy {
            $0.sourceRecordID != personal.firstRecordID && $0.targetRecordID != personal.firstRecordID
        })
        for child in layout.branches where child.parentID == personal.id {
            XCTAssertEqual(hierarchyPath(layout, to: child).first?.sourceRecordID, personal.firstRecordID)
        }
        let lifeStructure = layout.connections.filter { $0.structuralBranchID == life.id }
        XCTAssertEqual(Set(lifeStructure.flatMap(\.relationshipIDs)), [family.id + "-fork", work.id + "-fork"])
        XCTAssertTrue(layout.connections.filter { $0.structuralBranchID == family.id }.allSatisfy { $0.relationshipIDs.count == 1 })
        try assertCompleteHierarchy(layout)
        assertNoOverlaps(layout)
        assertNoCrossingRelationships(layout)
    }

    func testFortyRecordsKeepEmptyAncestorsCompleteAndAnySharedTrunkDrawnOnce() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 1), category(4, parent: 2),
                          category(5, parent: 2), category(6, parent: 5), category(7, parent: 3)]
        let lanes = [3, 4, 6, 7]
        let records = (0..<40).map { index in
            let lane = lanes[index % lanes.count]
            return record(101 + index, category: lane, time: TimeInterval(index + (lane == 3 ? 100 : 0)))
        }
        let layout = TimelineLayout(categories: categories, records: records)
        XCTAssertEqual(layout.nodes.count, records.count)
        XCTAssertEqual(Set(layout.nodes.map(\.id)).count, records.count)
        XCTAssertEqual(Set(layout.connections.flatMap(\.relationshipIDs)).count, 42)
        for parent in layout.branches where parent.firstRecordID == nil {
            let children = layout.branches.filter { $0.parentID == parent.id }
            let structural = layout.connections.filter { $0.structuralBranchID == parent.id }
            XCTAssertFalse(structural.isEmpty)
            let childEndYs = children.map { child -> CGFloat in
                child.firstRecordID.flatMap { id in layout.nodes.first { $0.id == id }?.frame.midY } ?? child.junction.y
            }
            XCTAssertEqual(structural.flatMap { [$0.from.y, $0.to.y] }.max(), childEndYs.max())
            XCTAssertEqual(parent.junction.x, parent.labelFrame.minX - 8, accuracy: 0.001)
            XCTAssertEqual(parent.junction.y, parent.labelFrame.maxY + 8, accuracy: 0.001)
        }
        try assertCompleteHierarchy(layout)
        assertNoOverlaps(layout)
        assertNoCrossingRelationships(layout)
    }


    func testEmptyParentWithThreeEqualChildrenKeepsItsMiddleArmBelowTheName() throws {
        let categories = [category(1), category(2, parent: 1), category(3, parent: 1), category(4, parent: 1)]
        let records = [record(101, category: 2, time: 1), record(102, category: 3, time: 2), record(103, category: 4, time: 3)]
        let layout = TimelineLayout(categories: categories, records: records)
        let parent = try XCTUnwrap(layout.branches.first { $0.categoryID == id(1) })
        let middle = try XCTUnwrap(layout.nodes.first { $0.id == id(102) })
        XCTAssertEqual(parent.junction.y, middle.frame.midY, accuracy: 0.001)
        XCTAssertEqual(parent.junction.y - parent.labelFrame.maxY, 8, accuracy: 0.001)
        try assertCompleteHierarchy(layout)
        assertNoOverlaps(layout)
        assertNoCrossingRelationships(layout)
    }

}
