import AppKit
import SwiftUI

/// Tracks a local tile drag, keeping account data out of the system pasteboard.
struct AccountDragArea: NSViewRepresentable {
    var source: UUID?
    let help: String
    let click: () -> Void
    let drop: (UUID) -> Bool

    final class PointerView: NSView {
        var source: UUID?
        var click: () -> Void = {}
        var drop: (UUID) -> Bool = { _ in false }
        private var origin: NSPoint?
        private var dragging = false
        private weak var target: PointerView?
        override var mouseDownCanMoveWindow: Bool { false }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            clearDrag()
            origin = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let origin, source != nil else { return }
            let point = event.locationInWindow
            if !dragging {
                guard hypot(point.x - origin.x, point.y - origin.y) >= 5 else { return }
                dragging = true
                window?.makeFirstResponder(self)
                layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
            }
            NSCursor.closedHand.set()
            let candidate = destination(at: point)
            if target !== candidate {
                target?.layer?.borderWidth = 0
                target = candidate
                target?.layer?.borderWidth = 2
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard origin != nil else { return }
            let wasDragging = dragging
            let receiver = wasDragging ? destination(at: event.locationInWindow) : nil
            clearDrag()
            if wasDragging {
                if let source { _ = receiver?.drop(source) }
            } else if bounds.contains(convert(event.locationInWindow, from: nil)) { click() }
        }

        private func destination(at point: NSPoint) -> PointerView? {
            guard let root = window?.contentView else { return nil }
            var hit = root.hitTest(root.convert(point, from: nil))
            while let view = hit {
                if let receiver = view as? PointerView { return receiver === self ? nil : receiver }
                hit = view.superview
            }
            return nil
        }

        override func cancelOperation(_ sender: Any?) { clearDrag() }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { clearDrag() }
            super.viewWillMove(toWindow: newWindow)
        }

        private func clearDrag() {
            origin = nil
            target?.layer?.borderWidth = 0
            target = nil
            if dragging {
                NSCursor.arrow.set()
                layer?.backgroundColor = nil
            }
            dragging = false
        }
    }

    func makeNSView(context: Context) -> PointerView {
        let view = PointerView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.borderColor = NSColor(Color.signal).cgColor
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: PointerView, context: Context) {
        view.source = source
        view.toolTip = help
        view.click = click
        view.drop = drop
    }
}
