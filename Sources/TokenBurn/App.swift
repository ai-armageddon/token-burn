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
    private var host: NSHostingView<Widget>?
    private let canvas = NSView()
    private let grip = WindowResizeGrip()
    private var layoutSize = CGSize(width: 428, height: 241)
    private let scaleKey = "TokenBurnWindowScale"
    private var scale: CGFloat = 1
    private var item: NSStatusItem!
    private var token: AnyCancellable?
    private let originKey = "TokenBurnPanelOrigin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedScale = UserDefaults.standard.double(forKey: scaleKey)
        if savedScale.isFinite && savedScale > 0 { scale = min(2, max(0.65, savedScale)) }
        let size = NSSize(width: layoutSize.width * scale, height: layoutSize.height * scale)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let fallback = NSPoint(x: screen.maxX - size.width - 20, y: screen.maxY - 20)
        let saved = UserDefaults.standard.string(forKey: originKey).map(NSPointFromString)
        let top = saved.flatMap { point in
            NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(NSPoint(x: point.x + 30, y: point.y - 20)) } ? point : nil
        } ?? fallback
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: false)
        panel.title = "Token Burn — Deck"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let widget = Widget(store: store, resize: { [weak self] size in self?.resize(size) },
                            minimize: { [weak self] in self?.panel.miniaturize(nil) })
        let host = NSHostingView(rootView: widget)
        host.sizingOptions = []
        self.host = host
        panel.contentView = canvas
        canvas.addSubview(host)
        canvas.addSubview(grip, positioned: .above, relativeTo: host)
        grip.toolTip = "Drag to resize Token Burn"
        grip.changeScale = { [weak self] value, finished in
            guard let self else { return }
            self.scale = min(2, max(0.65, value))
            self.resize(self.layoutSize)
            if finished { UserDefaults.standard.set(self.scale, forKey: self.scaleKey) }
        }
        panel.setFrameTopLeftPoint(top)
        resize(layoutSize)
        token = store.$state.map(\.pinned).removeDuplicates().sink { [weak self] pinned in
            self?.panel.level = pinned ? .floating : .normal
        }
        NotificationCenter.default.addObserver(self, selector: #selector(rememberPosition), name: NSWindow.didMoveNotification, object: panel)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = TokenBurnMark.image
        item.button?.toolTip = "Token Burn — Deck"
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
        layoutSize = size
        guard let host else { return }
        let bounds = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let appliedScale = min(scale, (bounds?.width ?? size.width * scale) / size.width,
                               (bounds?.height ?? size.height * scale) / size.height)
        var frame = panel.frame
        let top = frame.maxY
        frame.size = CGSize(width: (size.width * appliedScale).rounded(), height: (size.height * appliedScale).rounded())
        frame.origin.y = top - frame.height
        if let bounds {
            frame.origin.y = max(bounds.minY, min(frame.origin.y, bounds.maxY - frame.height))
            frame.origin.x = max(bounds.minX, min(frame.origin.x, bounds.maxX - frame.width))
        }
        panel.setFrame(frame, display: true)
        // SwiftUI lays out in logical points. AppKit scales the host and its native
        // mouse targets together, preserving tile dragging and editable controls.
        host.frame = canvas.bounds
        host.bounds = CGRect(origin: .zero, size: size)
        grip.baseSize = size
        grip.frame = CGRect(x: canvas.bounds.maxX - 18, y: 0, width: 18, height: 18)
        panel.invalidateCursorRects(for: grip)
    }

    @objc private func rememberPosition() {
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)), forKey: originKey)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (title, action) in [(panel.isMiniaturized ? "Restore Deck" : panel.isVisible ? "Hide Deck" : "Show Deck", #selector(togglePanel)),
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
