import AppKit
import SwiftUI
import Combine

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store()
    private var panel: FloatingPanel!
    private var item: NSStatusItem!
    private var token: AnyCancellable?
    private let originKey = "TokenBurnPanelOrigin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 428, height: 190)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let fallback = NSPoint(x: screen.maxX - size.width - 20, y: screen.maxY - 20)
        let saved = UserDefaults.standard.string(forKey: originKey).map(NSPointFromString)
        let top = saved.flatMap { point in
            NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: point.x + 30, y: point.y - 20)) } ? point : nil
        } ?? fallback
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        panel.title = "Token Burn"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let widget = Widget(store: store, resize: { [weak self] size in self?.resize(size) },
                            minimize: { [weak self] in self?.panel.miniaturize(nil) })
        let host = NSHostingView(rootView: widget)
        host.sizingOptions = []
        panel.contentView = host
        panel.setFrameTopLeftPoint(top)
        token = store.$state.map(\.pinned).removeDuplicates().sink { [weak self] pinned in
            self?.panel.level = pinned ? .floating : .normal
        }
        NotificationCenter.default.addObserver(self, selector: #selector(rememberPosition), name: NSWindow.didMoveNotification, object: panel)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let mark = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: BurnMark().path(in: rect.insetBy(dx: 1, dy: 1)).cgPath).fill()
            return true
        }
        mark.isTemplate = true
        item.button?.image = mark
        item.button?.toolTip = "Token Burn"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        installEditMenu()
        panel.orderFrontRegardless()
        store.start()
    }

    private func installEditMenu() {
        let main = NSMenu()
        let root = main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        root.submenu = edit
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
    }

    private func resize(_ size: CGSize) {
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        if let bounds = panel.screen?.visibleFrame {
            frame.origin.y = max(bounds.minY, min(frame.origin.y, bounds.maxY - size.height))
            frame.origin.x = max(bounds.minX, min(frame.origin.x, bounds.maxX - frame.width))
        }
        panel.setFrame(frame, display: true)
    }

    @objc private func rememberPosition() {
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)), forKey: originKey)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (title, action) in [(panel.isMiniaturized ? "Restore Token Burn" : panel.isVisible ? "Hide Token Burn" : "Show Token Burn", #selector(togglePanel)),
                                (store.state.pinned ? "Unpin Window" : "Pin Above Other Windows", #selector(togglePin)),
                                ("Refresh Usage", #selector(refresh))] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Token Burn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }
    @objc private func togglePanel() { if panel.isVisible && !panel.isMiniaturized { panel.orderOut(nil) } else { show() } }
    @objc private func togglePin() { store.setPinned(!store.state.pinned) }
    @objc private func refresh() { store.refresh() }
    private func show() {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
}

@main
struct TokenBurnApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
