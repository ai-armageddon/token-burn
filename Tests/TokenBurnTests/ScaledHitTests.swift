import AppKit
import SwiftUI
import Testing
@testable import TokenBurn

/// The Deck is scaled by the resize grip. Clicks must land on the control drawn
/// under the cursor, not on whatever sits at the unscaled position.
@MainActor
struct ScaledHitTests {
    @Test(arguments: [0.65, 0.7, 0.985, 1.0, 1.27, 1.8, 2.0])
    func topBarButtonsFollowTheCursorAtAnyScale(scale: Double) throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = Store(toolPaths: ToolPaths(bins: [], helpers: []), defaults: defaults, stateDirectory: folder)
        var minimized = 0
        let widget = Widget(store: store, resize: { _ in }, minimize: { minimized += 1 })
        let deckScale = DeckScale()
        deckScale.value = scale
        deckScale.size = CGSize(width: 428, height: 241)
        let size = CGSize(width: 428 * scale, height: 241 * scale)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: ScaledWidget(scale: deckScale, widget: widget))
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        // Minus button center in Deck points from the top left: 15pt padding,
        // five 27pt buttons 3pt apart, minus first, in a 44pt bar.
        let minus = CGPoint(x: 428 - 15 - 13.5 - 4 * 30, y: 22)
        let point = NSPoint(x: minus.x * scale, y: size.height - minus.y * scale)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        #expect(minimized == 1, "Click at the drawn minus button (scale \(scale)) did not reach it")
    }

}
