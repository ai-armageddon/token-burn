import AppKit

/// Kept in screen points so the grip remains easy to grab at small widget sizes.
final class WindowResizeGrip: NSView {
    var baseSize = CGSize.zero
    var changeScale: ((CGFloat, Bool) -> Void)?
    private var startPoint: CGPoint?
    private var startScale: CGFloat = 1

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.68, alpha: 0.85).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        for length in [4, 8] {
            path.move(to: NSPoint(x: bounds.maxX - 4 - CGFloat(length), y: 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: 4 + CGFloat(length)))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window, baseSize.width > 0 else { return }
        startPoint = window.convertPoint(toScreen: event.locationInWindow)
        startScale = window.frame.width / baseSize.width
    }

    private func update(with event: NSEvent, finished: Bool) {
        guard let window, let startPoint else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let w = baseSize.width, h = baseSize.height
        let delta = ((point.x - startPoint.x) * w + (startPoint.y - point.y) * h) / (w*w + h*h)
        changeScale?(startScale + delta, finished)
    }

    override func mouseDragged(with event: NSEvent) { update(with: event, finished: false) }
    override func mouseUp(with event: NSEvent) {
        update(with: event, finished: true)
        startPoint = nil
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        } else {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
}
