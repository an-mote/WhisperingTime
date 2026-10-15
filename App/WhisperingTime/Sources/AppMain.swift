import SwiftUI
import AppKit

@main
struct WhisperingTimeApp: App {
    @NSApplicationDelegateAdaptor(PrototypeAppDelegate.self) private var delegate
    @State private var store: LibraryStore
    @State private var textScale: CGFloat = 1

    init() {
        let args = ProcessInfo.processInfo.arguments
        var testURL: URL?
        if let index = args.firstIndex(of: "--test-library"), args.indices.contains(index + 1) {
            let safe = args[index + 1].filter { $0.isLetter || $0.isNumber || $0 == "-" }
            testURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.acered.whisperingtime.prototype/UIQA/\(safe)")
        }
        let library = LibraryStore(rootURL: testURL)
        if args.contains("--demo") { library.setDemo(true) }
        _store = State(initialValue: library)
    }

    var body: some Scene {
        Window("印迹", id: "review-main") {
            RootView(store: store)
                .frame(minWidth: 640, minHeight: 480)
                .environment(\.imprintTextScale, textScale)
                .onAppear { if PrototypeQA.largeText { textScale = 2 } }
                .transaction { if PrototypeQA.reduceEffects { $0.disablesAnimations = true } }
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1000, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("补记一条") {
                    NotificationCenter.default.post(name: Notification.Name("newImprintRequested"), object: nil)
                }.keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("关于印迹原型") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "印迹 · 交互原型",
                        .applicationVersion: "0.1.0",
                        .credits: NSAttributedString(string: "回顾生活留下的印迹。\n原型资料仅保存在这台 Mac；同步页面为演示。")
                    ])
                }
            }
        }
    }
}

@MainActor
final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var dirty = false
    private var observers: [NSObjectProtocol] = []
    private var configuredQAWindows: Set<ObjectIdentifier> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        if PrototypeQA.appearance != nil || PrototypeQA.increasedContrast {
            // QA injects one AppKit appearance before window creation; normal launches follow the system.
            let appearanceName: NSAppearance.Name
            switch (PrototypeQA.appearance == .dark, PrototypeQA.increasedContrast) {
            case (false, false): appearanceName = .aqua
            case (true, false): appearanceName = .darkAqua
            case (false, true): appearanceName = .accessibilityHighContrastAqua
            case (true, true): appearanceName = .accessibilityHighContrastDarkAqua
            }
            NSApp.appearance = NSAppearance(named: appearanceName)
        }
        if let size = PrototypeQA.windowSize {
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated {
                    guard let self, window.title == "印迹", self.configuredQAWindows.insert(ObjectIdentifier(window)).inserted else { return }
                    // Apply a QA size after AppKit restores the real window, without replacing SwiftUI's delegate.
                    window.setContentSize(size)
                    if let screen = NSScreen.screens.first(where: { $0.visibleFrame.width >= $0.visibleFrame.height }) ?? NSScreen.main {
                        let area = screen.visibleFrame
                        let frame = window.frame
                        window.setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2))
                    }
                }
            })
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observers.append(NotificationCenter.default.addObserver(forName: .init("imprintEditorDirtyChanged"), object: nil, queue: .main) { [weak self] note in
            let value = note.userInfo?["dirty"] as? Bool ?? false
            MainActor.assumeIsolated { self?.dirty = value }
        })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        checkUnsaved() ? .terminateNow : .terminateCancel
    }

    private func checkUnsaved() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "当前印迹还有未保存的内容"
        alert.informativeText = "请先在编辑窗口保存或放弃修改，再关闭应用。输入会留在原处。"
        alert.addButton(withTitle: "返回编辑")
        alert.runModal()
        return false
    }
}

enum PrototypeQA {
    private static func argument(_ name: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
        #else
        return nil
        #endif
    }
    private static func flag(_ name: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(name)
        #else
        false
        #endif
    }
    static var appearance: ColorScheme? {
        switch argument("--qa-appearance") { case "dark": .dark; case "light": .light; default: nil }
    }
    static var largeText: Bool { flag("--qa-large-text") }
    static var reduceEffects: Bool { flag("--qa-reduce-effects") }
    static var increasedContrast: Bool { flag("--qa-increased-contrast") }
    static var windowSize: NSSize? {
        guard let dimensions = argument("--qa-window-size")?.split(separator: "x"), dimensions.count == 2,
              let width = Double(dimensions[0]), let height = Double(dimensions[1]) else { return nil }
        return NSSize(width: max(640, width), height: max(480, height))
    }
}
