import XCTest
import AppKit

/// Exercises the production SwiftUI screens with an isolated on-disk library, never the user's library.
@MainActor
final class WhisperingTimeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(libraryID: String = UUID().uuidString, demo: Bool = false, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // Isolate system window restoration for UI tests without changing saved user preferences.
        app.launchArguments = ["--test-library", libraryID, "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO"]
        if demo { app.launchArguments.append("--demo") }
        app.launchArguments += arguments
        app.launch()
        app.activate()
        if arguments.contains("--qa-window-size"), !app.windows.firstMatch.waitForExistence(timeout: 2),
           let bundleURL = NSRunningApplication.runningApplications(withBundleIdentifier: "com.acered.whisperingtime.prototype")
            .first(where: { !$0.isTerminated })?.bundleURL {
            // Matrix QA measures an already presented window, not cold launch: request one workspace reopen.
            // The four core flows never take this path and retain their normal launch checks.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.allowsRunningApplicationSubstitution = false
            configuration.addsToRecentItems = false
            let note = XCTAttachment(string: "QA window presentation used one NSWorkspace reopen; this is layout evidence, not cold-launch evidence.")
            note.name = "QA窗口展示辅助"
            note.lifetime = .keepAlways
            add(note)
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration, completionHandler: nil)
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(element("newImprint", in: app).waitForExistence(timeout: 10))
        return app
    }

    /// Builds the fixture in memory; xcresult retains its JSON without requiring Documents access.
    private func prepareTimelineOverflowLibrary() throws -> (id: String, data: String) {
        let fixtureID = UUID().uuidString
        let categoryIDs = (0..<3).map { _ in UUID().uuidString }
        let categories: [[String: Any]] = [
            ["id": categoryIDs[0], "name": "生活"],
            ["id": categoryIDs[1], "name": "随笔", "parentID": categoryIDs[0]],
            ["id": categoryIDs[2], "name": "工作", "parentID": categoryIDs[0]],
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let records: [[String: Any]] = try (0..<40).map { index in
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: -(index + 1), to: today))
            let date = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: day))
            let milliseconds = date.timeIntervalSince1970 * 1_000
            var record: [String: Any] = [
                "id": UUID().uuidString,
                "title": "第\(index + 1)天的回顾",
                "categoryID": categoryIDs[index % categoryIDs.count],
                "occurredAt": milliseconds,
                "updatedAt": milliseconds,
                "body": "第\(index + 1)天留下的一段中文记录。用于回顾连续日期，以及横向滚动时的视口同步。",
                "attachments": [Any](),
                "scales": [Any](),
            ]
            // Keep one oldest unclassified record so filtering excludes the newest selection without emptying the canvas.
            if index == 39 { record.removeValue(forKey: "categoryID") }
            return record
        }
        let manifest: [String: Any] = ["version": 1, "categories": categories, "imprints": records]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "时间轴40篇夹具-\(fixtureID).json"
        attachment.lifetime = .keepAlways
        add(attachment)
        return (id: fixtureID, data: data.base64EncodedString())
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        if id == "bodyEditor" || id == "transcriptEditor" { return app.textViews.matching(identifier: id).firstMatch }
        if id == "titleField" { return app.textFields.matching(identifier: id).firstMatch }
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func accessibleText(_ control: XCUIElement) -> String {
        [control.label, control.title, control.value as? String ?? ""].joined(separator: " ")
    }

    private func timeControl(in app: XCUIApplication) -> XCUIElement {
        let menu = app.menuButtons.matching(identifier: "timeDisplay").firstMatch
        return menu.exists ? menu : element("timeDisplay", in: app)
    }

    private func keepScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitFor(_ predicate: NSPredicate, on object: Any, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: object)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, file: file, line: line)
    }

    /// Pasting supports arbitrary Chinese text independently of the Mac's currently selected input source.
    private func replaceText(_ text: String, in control: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let pasteboard = NSPasteboard.general
        let originals = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                guard let bytes = item.data(forType: type) else { return nil }
                return (type, bytes)
            }
        }
        defer {
            pasteboard.clearContents()
            let items = originals.map { values in
                let item = NSPasteboardItem()
                for (type, bytes) in values { item.setData(bytes, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        app.activate()
        waitFor(NSPredicate(format: "hittable == true"), on: control)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        control.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("v", modifierFlags: .command)
        waitFor(NSPredicate(format: "value == %@", text), on: control)
    }

    private func selectMode(_ title: String, canvas: String, app: XCUIApplication) {
        app.activate()
        let window = app.windows.firstMatch
        let radio = window.radioButtons.matching(NSPredicate(format: "label == %@ OR title == %@", title, title)).firstMatch
        if radio.exists {
            waitFor(NSPredicate(format: "hittable == true"), on: radio)
            radio.click()
        } else {
            // Compact windows use a real toolbar MenuButton. Its Picker may be a named submenu.
            let picker = window.menuButtons.matching(identifier: "modePicker").firstMatch
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            waitFor(NSPredicate(format: "hittable == true"), on: picker)
            picker.click()
            func visibleMenuItem(_ name: String) -> XCUIElement? {
                app.menuItems.matching(NSPredicate(format: "title == %@ OR label == %@", name, name))
                    .allElementsBoundByIndex.first { $0.isHittable && !$0.frame.isEmpty }
            }
            // The app's Display menu repeats these names. A hidden command may report
            // hittable while its frame is empty, invoke the mode, and leave the popup tracking.
            if visibleMenuItem(title) == nil, let submenu = visibleMenuItem("展示方式") { submenu.hover() }
            waitFor(NSPredicate { _, _ in visibleMenuItem(title) != nil }, on: app)
            guard let choice = visibleMenuItem(title) else { return }
            choice.click()
            waitFor(NSPredicate { _, _ in visibleMenuItem(title) == nil }, on: app)
        }
        XCTAssertTrue(element(canvas, in: app).waitForExistence(timeout: 5), "The \(title) view did not become visible")
    }

    private func firstImprint(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imprint-")).firstMatch
    }

    private func imprintButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imprint-"))
    }

    private func sidebarScope(_ title: String, in sidebar: XCUIElement) -> XCUIElement {
        let named = NSPredicate(format: "label BEGINSWITH %@ OR title == %@", title, title)
        let row = sidebar.outlineRows.matching(named).firstMatch
        if row.exists { return row }
        let rowWithText = sidebar.outlineRows.containing(.staticText, identifier: title).firstMatch
        if rowWithText.exists { return rowWithText }
        // Some native List versions expose a button within the row instead of a named row.
        return sidebar.buttons.matching(named).firstMatch
    }

    private func timelineOffset(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CGPoint {
        let value = element("timelineCanvas", in: app).value as? String ?? ""
        let components = value.split(separator: ",").compactMap { component -> Double? in
            guard let number = component.split(separator: "=").last else { return nil }
            return Double(number)
        }
        XCTAssertEqual(components.count, 2, "时间轴必须暴露当前横纵视口：\(value)", file: file, line: line)
        guard components.count == 2 else { return .zero }
        return CGPoint(x: components[0], y: components[1])
    }

    private func moveTimelineToStart(in app: XCUIApplication) {
        let canvas = element("timelineCanvas", in: app)
        let earlier = element("timelineEarlier", in: app)
        // Bound navigation for both the compact demo and the forty-record overflow fixture.
        for _ in 0..<64 where earlier.isEnabled {
            let before = canvas.value as? String ?? ""
            earlier.click()
            waitFor(NSPredicate(format: "value != %@", before), on: canvas)
        }
        XCTAssertFalse(earlier.isEnabled, "较早按钮应能到达时间轴起点")
        XCTAssertEqual(timelineOffset(in: app).x, 0, accuracy: 2)
    }

    private func dragTimelineThumb(to fraction: CGFloat, name: String, app: XCUIApplication) {
        app.activate()
        let scroller = element("timelineScroller", in: app)
        let thumb = scroller.descendants(matching: .valueIndicator).firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 5), "原生滚动条必须暴露实际滑块")
        let trackFrame = scroller.frame
        let thumbFrame = thumb.frame
        XCTAssertGreaterThan(thumbFrame.width, 0)
        XCTAssertGreaterThan(thumbFrame.height, 0)
        XCTAssertTrue(trackFrame.contains(CGPoint(x: thumbFrame.midX, y: thumbFrame.midY)))
        let targetX = trackFrame.minX + 1 + min(max(fraction, 0), 1) * max(0, trackFrame.width - 2)

        func attach(_ phase: String) {
            let note = XCTAttachment(string: """
                phase=\(phase)
                window.frame=\(app.windows.firstMatch.frame)
                scroller.frame=\(scroller.frame)
                scroller.value=\(String(describing: scroller.value))
                scroller.enabled=\(scroller.isEnabled)
                thumb.frame=\(thumb.frame)
                viewport=\(String(describing: element("timelineCanvas", in: app).value))
                drag.from=\(CGPoint(x: thumbFrame.midX, y: thumbFrame.midY))
                drag.to=\(CGPoint(x: targetX, y: thumbFrame.midY))
                """)
            note.name = "时间轴滑块拖动-\(name)-\(phase)"
            note.lifetime = .keepAlways
            add(note)
        }
        attach("之前")
        // Query the native value indicator again for every drag; never assume where its knob lies on the track.
        let start = thumb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = start.withOffset(CGVector(dx: targetX - thumbFrame.midX, dy: 0))
        // AppKit controls need mouse events; press(forDuration:) synthesizes a touch path.
        start.click(forDuration: 0.15, thenDragTo: destination)
        attach("之后")
    }

    private func assertTimelineNavigator(in app: XCUIApplication, configuration: String) {
        let canvas = element("timelineCanvas", in: app)
        let navigator = element("timelineNavigator", in: app)
        let range = element("timelineVisibleRange", in: app)
        XCTAssertTrue(navigator.waitForExistence(timeout: 5), "底部导航未出现：\(configuration)")
        for id in ["timelineEarlier", "timelineLater", "timelineScroller", "timelineVisibleRange"] {
            let control = element(id, in: app)
            XCTAssertTrue(control.waitForExistence(timeout: 5), "时间导航控件未出现：\(configuration) / \(id)")
            // Disabled end buttons remain visible and keyboard discoverable; only enabled controls need a hit target.
            if control.isEnabled { waitFor(NSPredicate(format: "hittable == true"), on: control) }
            XCTAssertTrue(app.windows.firstMatch.frame.intersects(control.frame), "时间导航控件超出窗口：\(configuration) / \(id)")
        }
        XCTAssertGreaterThanOrEqual(navigator.frame.minY, canvas.frame.maxY - 2, "时间导航应固定在画布下方：\(configuration)")
        XCTAssertLessThanOrEqual(navigator.frame.maxY, app.windows.firstMatch.frame.maxY + 1)
        XCTAssertNotNil(accessibleText(range).range(of: #"\d{4}"#, options: .regularExpression), "隐藏时间仍应保留年份导航：\(configuration)")
        XCTAssertTrue(accessibleText(range).contains("月"), "隐藏时间仍应保留月份导航：\(configuration)")
    }

    func testRootTimelineHasOneNodePerImprintAndNavigationDoesNotSelectOrOpen() throws {
        let app = launch(demo: true, arguments: ["--qa-window-size", "640x480"])
        let ids = Set(imprintButtons(in: app).allElementsBoundByIndex.map(\.identifier))
        XCTAssertTrue(accessibleText(timeControl(in: app)).contains("隐藏时间"))
        selectMode("时间轴", canvas: "timelineCanvas", app: app)
        assertTimelineNavigator(in: app, configuration: "最小窗口树根时间轴")
        let nodes = imprintButtons(in: app).allElementsBoundByIndex
        XCTAssertEqual(nodes.count, 5, "分支连接点应复用首篇内容，不得重复渲染")
        XCTAssertEqual(Set(nodes.map(\.identifier)).count, 5, "每篇示例内容只能出现一次")
        XCTAssertTrue(Set(nodes.map(\.identifier)).isSuperset(of: ids))
        XCTAssertTrue(nodes.allSatisfy { !$0.isSelected })
        XCTAssertTrue(element("timelineBranch-unclassified", in: app).exists)

        let canvas = element("timelineCanvas", in: app)
        moveTimelineToStart(in: app)
        let start = timelineOffset(in: app)
        let later = element("timelineLater", in: app)
        if later.isEnabled {
            XCTAssertTrue(element("timelineScroller", in: app).isEnabled)
            let before = canvas.value as? String ?? ""
            later.click()
            waitFor(NSPredicate(format: "value != %@", before), on: canvas)
            let advanced = timelineOffset(in: app)
            XCTAssertGreaterThan(advanced.x, start.x)
            XCTAssertEqual(advanced.y, start.y, accuracy: 2, "底部时间导航须保留纵向位置")
            XCTAssertTrue(imprintButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
            XCTAssertFalse(element("editImprint", in: app).exists, "时间导航不应打开阅读面板")
            let advancedValue = canvas.value as? String ?? ""
            element("timelineEarlier", in: app).click()
            waitFor(NSPredicate(format: "value != %@", advancedValue), on: canvas)
            XCTAssertLessThan(timelineOffset(in: app).x, advanced.x)
        } else {
            XCTAssertFalse(element("timelineEarlier", in: app).isEnabled, "不足一屏时较早导航应停用")
            XCTAssertFalse(element("timelineScroller", in: app).isEnabled, "不足一屏时滚动条应停用")
            XCTAssertEqual(start.x, 0, accuracy: 2)
        }
        XCTAssertTrue(imprintButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        XCTAssertFalse(element("editImprint", in: app).exists)
        keepScreenshot("10-树根时间轴-首篇即连接点与固定导航", app: app)
        app.terminate()
    }

    func testRootTimelineNativeScrollerAndCanvasStayInSync() throws {
        let fixture = try prepareTimelineOverflowLibrary()
        let app = launch(libraryID: fixture.id,
                         arguments: ["--qa-window-size", "640x480", "--qa-library-data", fixture.data])
        selectMode("时间轴", canvas: "timelineCanvas", app: app)
        moveTimelineToStart(in: app)
        let canvas = element("timelineCanvas", in: app)
        let scroller = element("timelineScroller", in: app)
        let navigator = element("timelineNavigator", in: app)
        let footerFrame = navigator.frame
        XCTAssertEqual(imprintButtons(in: app).count, 40)
        XCTAssertTrue(scroller.isEnabled, "长夹具须提供实际横向滚动范围")
        XCTAssertTrue(element("timelineLater", in: app).isEnabled)
        let start = timelineOffset(in: app)
        let initialValue = canvas.value as? String ?? ""
        dragTimelineThumb(to: 1, name: "起点到终点", app: app)
        waitFor(NSPredicate(format: "value != %@", initialValue), on: canvas)
        let end = timelineOffset(in: app)
        XCTAssertGreaterThan(end.x, start.x + 20)
        XCTAssertEqual(end.y, start.y, accuracy: 2)
        waitFor(NSPredicate(format: "enabled == false"), on: element("timelineLater", in: app))
        XCTAssertEqual(navigator.frame.minY, footerFrame.minY, accuracy: 1, "导航不能随画布一起滚走")
        XCTAssertFalse(element("editImprint", in: app).exists)

        let atEndValue = canvas.value as? String ?? ""
        dragTimelineThumb(to: 0, name: "终点到起点", app: app)
        waitFor(NSPredicate(format: "value != %@", atEndValue), on: canvas)
        waitFor(NSPredicate(format: "enabled == false"), on: element("timelineEarlier", in: app))
        XCTAssertEqual(timelineOffset(in: app).x, 0, accuracy: 2)
        XCTAssertEqual(timelineOffset(in: app).y, end.y, accuracy: 2, "拖回起点须保留纵向位置")

        let atStartValue = canvas.value as? String ?? ""
        dragTimelineThumb(to: 0.5, name: "起点到中间", app: app)
        waitFor(NSPredicate(format: "value != %@", atStartValue), on: canvas)
        let middle = timelineOffset(in: app)
        XCTAssertGreaterThan(middle.x, 0)
        XCTAssertLessThan(middle.x, end.x)
        let scrollerBefore = scroller.value ?? ""
        let canvasBefore = canvas.value as? String ?? ""
        // Start inside the range so either system scroll direction moves the canvas in one wheel operation.
        canvas.scroll(byDeltaX: -120, deltaY: 0)
        waitFor(NSPredicate(format: "value != %@", canvasBefore), on: canvas)
        waitFor(NSPredicate(format: "value != %@", argumentArray: [scrollerBefore]), on: scroller)
        XCTAssertNotEqual(timelineOffset(in: app).x, middle.x)
        XCTAssertEqual(timelineOffset(in: app).y, middle.y, accuracy: 2)
        XCTAssertTrue(imprintButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        keepScreenshot("11-树根时间轴-原生滚动条与画布双向同步", app: app)
        app.terminate()
    }

    func testRootTimelineRestoresViewportAndLocatesSelectionFromCardsAndCalendar() throws {
        let fixture = try prepareTimelineOverflowLibrary()
        let app = launch(libraryID: fixture.id,
                         arguments: ["--qa-window-size", "640x480", "--qa-library-data", fixture.data])
        let card = firstImprint(in: app)
        let selectedID = card.identifier
        card.click()
        XCTAssertTrue(element("editImprint", in: app).waitForExistence(timeout: 5))
        app.buttons["完成"].click()
        selectMode("时间轴", canvas: "timelineCanvas", app: app)
        let selected = app.buttons.matching(identifier: selectedID).firstMatch
        waitFor(NSPredicate(format: "selected == true AND hittable == true"), on: selected)
        let canvas = element("timelineCanvas", in: app)
        // Opening and closing is measured while the selected card is known to be visible.
        // A later horizontal move correctly preserves its branch's vertical position and can reveal empty canvas.
        let beforeDetail = timelineOffset(in: app)
        selected.click()
        XCTAssertTrue(element("editImprint", in: app).waitForExistence(timeout: 5))
        app.buttons["完成"].click()
        XCTAssertEqual(timelineOffset(in: app).x, beforeDetail.x, accuracy: 2, "关闭阅读面板应回到原视口")
        XCTAssertEqual(timelineOffset(in: app).y, beforeDetail.y, accuracy: 2)

        let before = canvas.value as? String ?? ""
        XCTAssertTrue(element("timelineEarlier", in: app).isEnabled)
        element("timelineEarlier", in: app).click()
        waitFor(NSPredicate(format: "value != %@", before), on: canvas)
        let remembered = timelineOffset(in: app)
        XCTAssertTrue(selected.isSelected, "滚动画布不能改选内容")
        selectMode("卡片", canvas: "cardsCanvas", app: app)
        selectMode("时间轴", canvas: "timelineCanvas", app: app)
        XCTAssertEqual(timelineOffset(in: app).x, remembered.x, accuracy: 2, "选中项未变化时应恢复视口")
        XCTAssertEqual(timelineOffset(in: app).y, remembered.y, accuracy: 2)

        // Return to the newest card so the calendar starts with yesterday and its neighboring fixture dates.
        selectMode("卡片", canvas: "cardsCanvas", app: app)
        firstImprint(in: app).click()
        XCTAssertTrue(element("editImprint", in: app).waitForExistence(timeout: 5))
        app.buttons["完成"].click()
        selectMode("日历", canvas: "calendarCanvas", app: app)
        let recordedDates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "日，", "1 条印迹"))
        var alternative = recordedDates.allElementsBoundByIndex.first { !$0.isSelected && $0.isHittable }
        if alternative == nil {
            // Consecutive fixture dates can cross a month boundary near the first day.
            app.buttons["上个月"].click()
            alternative = recordedDates.allElementsBoundByIndex.first { !$0.isSelected && $0.isHittable }
        }
        try XCTUnwrap(alternative).click()
        let calendarRecordID = firstImprint(in: app).identifier
        XCTAssertFalse(calendarRecordID.isEmpty)
        selectMode("时间轴", canvas: "timelineCanvas", app: app)
        let calendarSelection = app.buttons.matching(identifier: calendarRecordID).firstMatch
        waitFor(NSPredicate(format: "selected == true AND hittable == true"), on: calendarSelection)
        XCTAssertFalse(element("editImprint", in: app).exists, "同步日历选择应定位内容，不能自动打开面板")
        keepScreenshot("12-树根时间轴-恢复视口与跨展示定位", app: app)
        app.terminate()
    }

    func testRootTimelineLocatesRetainedSelectionWhenReturningFromExcludedCategory() throws {
        // The regular window has room to reveal the native sidebar for filter changes.
        let fixture = try prepareTimelineOverflowLibrary()
        let app = launch(libraryID: fixture.id,
                         arguments: ["--qa-window-size", "1000x760", "--qa-library-data", fixture.data])
        let newest = firstImprint(in: app)
        let selectedID = newest.identifier
        newest.click()
        XCTAssertTrue(element("editImprint", in: app).waitForExistence(timeout: 5))
        app.buttons["完成"].click()
        // Visit the full timeline first so its coordinator has already consumed this selection.
        // Returning from the filter must locate it again, rather than restoring the filtered viewport.
        selectMode("时间轴", canvas: "timelineCanvas", app: app)
        let initialSelection = app.buttons.matching(identifier: selectedID).firstMatch
        waitFor(NSPredicate(format: "selected == true AND hittable == true"), on: initialSelection)
        XCTAssertEqual(imprintButtons(in: app).count, 40)

        // Restrict scope controls to the native sidebar outline; canvas branch labels and review titles repeat these names.
        let sidebar = app.windows.firstMatch.outlines.firstMatch
        if !sidebar.isHittable {
            // The workspace initially presents detailOnly; use its native toggle before addressing sidebar rows.
            let sidebarToggle = app.windows.firstMatch.buttons.matching(NSPredicate(
                format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS %@ OR title CONTAINS[c] %@ OR title CONTAINS %@",
                "sidebar", "sidebar", "边栏", "sidebar", "边栏")).firstMatch
            XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
            waitFor(NSPredicate(format: "hittable == true"), on: sidebarToggle)
            sidebarToggle.click()
        }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        waitFor(NSPredicate(format: "hittable == true"), on: sidebar)
        let unclassified = sidebarScope("未分类", in: sidebar)
        XCTAssertTrue(unclassified.waitForExistence(timeout: 5))
        waitFor(NSPredicate(format: "hittable == true"), on: unclassified)
        unclassified.click()
        waitFor(NSPredicate(format: "count == 1"), on: imprintButtons(in: app))
        XCTAssertFalse(app.buttons.matching(identifier: selectedID).firstMatch.exists, "所选最新内容应位于未分类范围之外")

        XCTAssertTrue(element("timelineCanvas", in: app).exists)
        XCTAssertEqual(imprintButtons(in: app).count, 1)
        XCTAssertTrue(imprintButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected }, "范围外的选中项不应被替换成当前范围内容")
        XCTAssertFalse(element("editImprint", in: app).exists)
        let all = sidebarScope("全部印迹", in: sidebar)
        waitFor(NSPredicate(format: "hittable == true"), on: all)
        all.click()

        let restored = app.buttons.matching(identifier: selectedID).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        waitFor(NSPredicate(format: "selected == true AND hittable == true"), on: restored)
        XCTAssertEqual(imprintButtons(in: app).count, 40)
        XCTAssertFalse(element("editImprint", in: app).exists, "恢复范围只定位选中项，不自动打开阅读面板")
        keepScreenshot("13-树根时间轴-恢复范围后定位保留的选中项", app: app)
        app.terminate()
    }

    func testUntitledChineseRecordPersistsAcrossRelaunchAndCanBeEdited() throws {
        let library = "persistence-\(UUID().uuidString)"
        let app = launch(libraryID: library)
        XCTAssertTrue(app.staticTexts["把值得回看的片刻留在这里"].waitForExistence(timeout: 5))
        element("newImprint", in: app).click()
        let editor = element("bodyEditor", in: app)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let title = element("titleField", in: app)
        XCTAssertEqual(title.value as? String ?? "", "")
        XCTAssertFalse(element("saveImprint", in: app).isEnabled)
        let body = "河边的风很轻，想把这一刻留下来。\n不用标题，也不用先决定放在哪个分类。"
        replaceText(body, in: editor, app: app)
        keepScreenshot("01-中文无标题补记", app: app)
        XCTAssertTrue(element("saveImprint", in: app).isEnabled)
        element("saveImprint", in: app).click()
        XCTAssertTrue(element("cardsCanvas", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(firstImprint(in: app).waitForExistence(timeout: 5))
        app.terminate()

        let reopened = launch(libraryID: library)
        let card = firstImprint(in: reopened)
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.label.contains("河边的风很轻"))
        XCTAssertTrue(card.label.contains("未分类"))
        card.click()
        element("editImprint", in: reopened).click()
        let restoredBody = element("bodyEditor", in: reopened)
        XCTAssertTrue(restoredBody.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredBody.value as? String, body)
        XCTAssertEqual(element("titleField", in: reopened).value as? String ?? "", "")
        replaceText("后来补上的标题", in: element("titleField", in: reopened), app: reopened)
        replaceText(body + "\n后来又补了一句。", in: restoredBody, app: reopened)
        element("saveImprint", in: reopened).click()
        XCTAssertTrue(reopened.buttons["完成"].waitForExistence(timeout: 5))
        reopened.buttons["完成"].click()
        reopened.terminate()

        let finalLaunch = launch(libraryID: library)
        let updated = firstImprint(in: finalLaunch)
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        XCTAssertTrue(updated.label.contains("后来补上的标题"))
        updated.click()
        element("editImprint", in: finalLaunch).click()
        XCTAssertTrue(element("bodyEditor", in: finalLaunch).waitForExistence(timeout: 5))
        XCTAssertEqual(element("bodyEditor", in: finalLaunch).value as? String, body + "\n后来又补了一句。")
        keepScreenshot("02-冷启动恢复与续写", app: finalLaunch)
        finalLaunch.buttons["取消"].click()
        finalLaunch.buttons["完成"].click()
        finalLaunch.terminate()
    }

    func testExampleViewsDefaultToHiddenTimeAndExamplesRemainReadOnly() throws {
        let app = launch()
        let examples = app.buttons.matching(identifier: "showExamples").allElementsBoundByIndex.first { $0.exists && $0.isHittable }
        XCTAssertNotNil(examples)
        try XCTUnwrap(examples).click()
        XCTAssertTrue(element("cardsCanvas", in: app).waitForExistence(timeout: 5))
        let time = timeControl(in: app)
        XCTAssertTrue(accessibleText(time).contains("隐藏时间"), "Time is hidden by default")
        keepScreenshot("03-卡片回顾-默认隐藏时间", app: app)
        let first = firstImprint(in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        let edit = element("editImprint", in: app)
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertFalse(edit.isEnabled)
        app.buttons["完成"].click()

        selectMode("日历", canvas: "calendarCanvas", app: app)
        keepScreenshot("04-日历回顾-保留日期坐标", app: app)
        selectMode("时间轴", canvas: "timelineCanvas", app: app)
        keepScreenshot("05-时间轴回顾-压缩空白间隔", app: app)
        selectMode("播放", canvas: "slideshowCanvas", app: app)
        XCTAssertTrue(app.buttons["自动播放"].waitForExistence(timeout: 5))
        keepScreenshot("06-逐页播放-默认手动", app: app)
        selectMode("卡片", canvas: "cardsCanvas", app: app)
        XCTAssertTrue(accessibleText(time).contains("隐藏时间"))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "几天没写", "连续记录")).count, 0)
        app.buttons["返回我的资料"].click()
        XCTAssertTrue(app.staticTexts["把值得回看的片刻留在这里"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testSlideshowKeyboardNavigationAndPause() throws {
        let app = launch(demo: true)
        selectMode("播放", canvas: "slideshowCanvas", app: app)
        let next = app.buttons["下一条"]
        let previous = app.buttons["上一条"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(previous.isEnabled)
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        waitFor(NSPredicate(format: "enabled == true"), on: previous)
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: [])
        waitFor(NSPredicate(format: "enabled == false"), on: previous)
        app.typeKey(XCUIKeyboardKey.space.rawValue, modifierFlags: [])
        XCTAssertTrue(app.buttons["暂停自动播放"].waitForExistence(timeout: 5))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(element("cardsCanvas", in: app).waitForExistence(timeout: 5))
        keepScreenshot("07-播放键盘操作", app: app)
        app.terminate()
    }


    func testUnsavedCommandQuitPreservesDraft() throws {
        let app = launch()
        element("newImprint", in: app).click()
        let body = element("bodyEditor", in: app)
        let text = "还没有保存的中文草稿。退出时应该留在原处。"
        replaceText(text, in: body, app: app)
        app.typeKey("q", modifierFlags: .command)
        // AppKit can reject quitting while a modal editor is open before the delegate's alert runs.
        // Both native refusal and the explicit alert must preserve the same draft.
        let returnToEditor = app.buttons["返回编辑"]
        if returnToEditor.waitForExistence(timeout: 2) { returnToEditor.click() }
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        keepScreenshot("08-未保存退出保护", app: app)
        XCTAssertEqual(body.value as? String, text)
        XCTAssertTrue(element("saveImprint", in: app).isEnabled)
        // This test ends after verifying quit protection; forced test-process cleanup is not a discard interaction.
        app.terminate()
    }

    func testVisualMinimumLight() throws {
        assertVisualMatrix(name: "最小窗口-浅色", width: 640, height: 480, arguments: ["--qa-appearance", "light"])
    }

    func testVisualRegularLight() throws {
        assertVisualMatrix(name: "常规窗口-浅色", width: 1000, height: 760, arguments: ["--qa-appearance", "light"])
    }

    func testVisualWideDark() throws {
        assertVisualMatrix(name: "宽窗口-深色", width: 1440, height: 900, arguments: ["--qa-appearance", "dark"])
    }

    func testVisualMinimumDarkLargeText() throws {
        assertVisualMatrix(name: "最小窗口-深色大字减少效果", width: 640, height: 480, arguments: ["--qa-appearance", "dark", "--qa-large-text", "--qa-reduce-effects"])
    }

    func testVisualRegularLightLargeTextHighContrast() throws {
        assertVisualMatrix(name: "常规窗口-浅色大字高对比", width: 1000, height: 760, arguments: ["--qa-appearance", "light", "--qa-large-text", "--qa-increased-contrast"])
    }

    private func assertCalendarColumns(in app: XCUIApplication, configuration: String) {
        let dates = app.windows.firstMatch.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "日，", "条印迹"))
        XCTAssertEqual(dates.count, 42, "日历应暴露完整的六周日期按钮：\(configuration)")
        guard dates.count == 42 else { return }
        // Preserve accessibility order: the first seven dates must form one evenly spaced row.
        let frames = (0..<7).map { dates.element(boundBy: $0).frame }
        let geometry = XCTAttachment(string: frames.enumerated().map { "第\($0.offset + 1)列：\($0.element)" }.joined(separator: "\n"))
        geometry.name = "日历首行几何-\(configuration)"
        geometry.lifetime = .keepAlways
        add(geometry)
        let centers = frames.map(\.midX)
        let expectedSpacing = (centers[6] - centers[0]) / 6
        for index in frames.indices {
            XCTAssertGreaterThan(frames[index].width, 0, "日期列宽度必须为正：\(configuration) / \(index + 1)")
            XCTAssertEqual(frames[index].midY, frames[0].midY, accuracy: 2, "首七个日期必须位于同一行：\(configuration)")
            if index > 0 {
                let spacing = centers[index] - centers[index - 1]
                XCTAssertGreaterThan(spacing, 20, "日期列必须从左到右分开排列：\(configuration) / \(index)-\(index + 1)")
                XCTAssertEqual(spacing, expectedSpacing, accuracy: 2, "日期列中心间隔应相等：\(configuration) / \(index)-\(index + 1)")
            }
        }
    }

    private func assertVisualMatrix(name: String, width: CGFloat, height: CGFloat, arguments: [String]) {
        let modes = [("卡片", "cardsCanvas"), ("日历", "calendarCanvas"), ("时间轴", "timelineCanvas"), ("播放", "slideshowCanvas")]
        let size = "\(Int(width))x\(Int(height))"
        let app = launch(demo: true, arguments: ["--qa-window-size", size] + arguments)
        XCTAssertEqual(app.windows.firstMatch.frame.width, width, accuracy: 24, "QA window width was not applied: \(name)")
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.height, height)
        XCTAssertLessThan(app.windows.firstMatch.frame.height, height + 120)
        for (title, canvas) in modes {
            selectMode(title, canvas: canvas, app: app)
            waitFor(NSPredicate(format: "hittable == true"), on: element("newImprint", in: app))
            waitFor(NSPredicate(format: "hittable == true"), on: timeControl(in: app))
            if title == "播放" {
                let controls = app.windows.firstMatch
                for controlName in ["自动播放", "全屏", "退出播放"] {
                    let control = controls.buttons.matching(NSPredicate(format: "label == %@ OR title == %@", controlName, controlName)).firstMatch
                    XCTAssertTrue(control.waitForExistence(timeout: 5), "播放控件未出现：\(name) / \(controlName)")
                    waitFor(NSPredicate(format: "hittable == true"), on: control)
                }
            }
            keepScreenshot("09-视觉矩阵-\(name)-\(title)", app: app)
            if title == "日历" { assertCalendarColumns(in: app, configuration: name) }
            if title == "时间轴" { assertTimelineNavigator(in: app, configuration: name) }
        }
        app.terminate()
    }
}
