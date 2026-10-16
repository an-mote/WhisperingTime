import AppKit
import CoreGraphics
import XCTest
@testable import WhisperingTime

@MainActor
final class TimelineScrollBridgeTests: XCTestCase {
    private final class FlippedDocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor private final class BoundsChanges {
        var origins: [CGPoint] = []
    }

    private struct Fixture {
        let window: NSWindow
        let scroll: TimelineNativeScrollView
        let document: NSView
    }

    private func makeFixture() -> Fixture {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: 640, height: 300)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = TimelineNativeScrollView(frame: frame)
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        let document = FlippedDocumentView(frame: CGRect(x: 0, y: 0, width: 2_200, height: 900))
        scroll.documentView = document
        window.contentView = scroll
        scroll.tile()
        scroll.layoutSubtreeIfNeeded()
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.scroll(to: CGPoint(x: 400, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        return Fixture(window: window, scroll: scroll, document: document)
    }

    private func horizontalWheel(_ delta: Int32) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: 0, wheel2: delta, wheel3: 0
        ))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        XCTAssertEqual(event.type, .scrollWheel)
        XCTAssertTrue(event.hasPreciseScrollingDeltas)
        XCTAssertNotEqual(event.scrollingDeltaX, 0)
        XCTAssertEqual(event.scrollingDeltaY, 0)
        return event
    }

    private func observeBounds(of scroll: NSScrollView, changes: BoundsChanges) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak scroll, weak changes] _ in
            MainActor.assumeIsolated {
                guard let scroll, let changes else { return }
                changes.origins.append(scroll.contentView.bounds.origin)
            }
        }
    }

    func testHorizontalPixelWheelMovesTheNativeClipInBothDirectionsWithoutBuiltInScroller() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let scroll = fixture.scroll
        let changes = BoundsChanges()
        let observer = observeBounds(of: scroll, changes: changes)
        defer { NotificationCenter.default.removeObserver(observer) }
        XCTAssertEqual(scroll.contentView.bounds.minX, 400, accuracy: 0.001)
        XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 0.001)
        XCTAssertEqual(fixture.document.frame.size, CGSize(width: 2_200, height: 900))

        let towardEarlier = try horizontalWheel(120)
        XCTAssertGreaterThan(towardEarlier.scrollingDeltaX, 0)
        scroll.scrollWheel(with: towardEarlier)
        let earlierX = scroll.contentView.bounds.minX
        XCTAssertLessThan(earlierX, 400)
        XCTAssertGreaterThan(earlierX, 0)
        XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 0.001)
        XCTAssertTrue(changes.origins.contains { $0.x < 400 && abs($0.y - 100) < 0.001 })

        let towardLater = try horizontalWheel(-120)
        XCTAssertLessThan(towardLater.scrollingDeltaX, 0)
        scroll.scrollWheel(with: towardLater)
        XCTAssertGreaterThan(scroll.contentView.bounds.minX, earlierX)
        XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 0.001)
        XCTAssertTrue(changes.origins.contains { $0.x > earlierX && abs($0.y - 100) < 0.001 })
        XCTAssertGreaterThanOrEqual(changes.origins.count, 2)
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertTrue(scroll.horizontalScroller?.isHidden ?? true)
    }

    func testHorizontalPixelWheelClampsAtBothDocumentEndsAndPreservesVerticalPosition() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let scroll = fixture.scroll
        let changes = BoundsChanges()
        let observer = observeBounds(of: scroll, changes: changes)
        defer { NotificationCenter.default.removeObserver(observer) }

        scroll.scrollWheel(with: try horizontalWheel(100_000))
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 0.001)
        scroll.scrollWheel(with: try horizontalWheel(100_000))
        XCTAssertEqual(scroll.contentView.bounds.minX, 0, accuracy: 0.001)

        scroll.scrollWheel(with: try horizontalWheel(-100_000))
        XCTAssertEqual(scroll.contentView.bounds.maxX, fixture.document.frame.maxX, accuracy: 0.001)
        XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 0.001)
        let rightEdge = scroll.contentView.bounds.minX
        scroll.scrollWheel(with: try horizontalWheel(-100_000))
        XCTAssertEqual(scroll.contentView.bounds.minX, rightEdge, accuracy: 0.001)
        XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 0.001)
        XCTAssertTrue(changes.origins.contains { abs($0.x) < 0.001 && abs($0.y - 100) < 0.001 })
        XCTAssertTrue(changes.origins.contains { abs($0.x - rightEdge) < 0.001 && abs($0.y - 100) < 0.001 })
        XCTAssertFalse(scroll.hasHorizontalScroller)
        XCTAssertTrue(scroll.horizontalScroller?.isHidden ?? true)
    }
}
