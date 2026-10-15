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
            let choice = app.menuItems.matching(NSPredicate(format: "title == %@ OR label == %@", title, title)).firstMatch
            let submenu = app.menuItems.matching(NSPredicate(format: "title == %@ OR label == %@", "展示方式", "展示方式")).firstMatch
            if submenu.exists && submenu.isHittable && (!choice.exists || !choice.isHittable) { submenu.hover() }
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            waitFor(NSPredicate(format: "hittable == true"), on: choice)
            choice.click()
        }
        XCTAssertTrue(element(canvas, in: app).waitForExistence(timeout: 5), "The \(title) view did not become visible")
    }

    private func firstImprint(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imprint-")).firstMatch
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
        }
        app.terminate()
    }
}
