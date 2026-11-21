import AppKit
import SwiftUI

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        private var grabOffset: NSPoint?
        override func mouseDown(with event: NSEvent) {
            grabOffset = event.locationInWindow
        }
        override func mouseDragged(with event: NSEvent) {
            guard let window, let grabOffset else { return }
            let point = window.convertPoint(toScreen: event.locationInWindow)
            window.setFrameOrigin(NSPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y))
        }
        override func mouseUp(with event: NSEvent) { grabOffset = nil }
        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.toolTip = "Drag to move Token Burn"
        return view
    }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
