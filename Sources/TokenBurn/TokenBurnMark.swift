import AppKit

enum TokenBurnMark {
    // Normalized on a square canvas with its origin in the upper left.
    static func draw(in context: CGContext, rect: CGRect) {
        let side = min(rect.width, rect.height)
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX - side / 2, y: rect.midY - side / 2)
        context.scaleBy(x: side / 100, y: side / 100)
        context.setLineCap(.round)
        context.setLineWidth(6.8)

        let rings: [(CGFloat, CGFloat, CGFloat)] = [(24, 24, 0.89), (76, 24, 0.65),
                                                    (24, 76, 0.74), (76, 76, 0.48)]
        let green = NSColor(srgbRed: 34/255, green: 216/255, blue: 106/255, alpha: 1)
        for (x, y, remaining) in rings {
            let center = CGPoint(x: x, y: y)
            context.setStrokeColor(green.withAlphaComponent(0.25).cgColor)
            context.strokeEllipse(in: CGRect(x: x - 19, y: y - 19, width: 38, height: 38))
            context.setStrokeColor(green.cgColor)
            context.addArc(center: center, radius: 19, startAngle: -.pi / 2,
                           endAngle: -.pi / 2 + 2 * .pi * remaining, clockwise: false)
            context.strokePath()
        }
    }

    static let image = NSImage(size: NSSize(width: 20, height: 20), flipped: true) { rect in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        draw(in: context, rect: rect)
        return true
    }
}
