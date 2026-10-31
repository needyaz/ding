import AppKit

/// The menu bar icon: the app icon's bell silhouette with a clock-hand cutout, drawn as a
/// template image so macOS tints it for light, dark and highlighted menu bars.
enum MenuBarGlyph {
    /// Drawing space. The bell is laid out in a 100-unit box (y up) and scaled to fit.
    private static let box: CGFloat = 100

    static func image(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ding"
        return image
    }

    static func draw(in rect: NSRect) {
        // Fit the artwork (x 8...92, y 12...90) into the rect with a small margin.
        let artwork = NSRect(x: 8, y: 12, width: 84, height: 78)
        let scale = min(rect.width, rect.height) * 0.9 / max(artwork.width, artwork.height)
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX - artwork.midX * scale, yBy: rect.midY - artwork.midY * scale)
        transform.scale(by: scale)

        NSColor.black.setFill()
        let body = bellBody()
        body.transform(using: transform as AffineTransform)
        body.fill()
        let clapper = clapperPath()
        clapper.transform(using: transform as AffineTransform)
        clapper.fill()

        // Clock hands, knocked out of the dome.
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.compositingOperation = .clear
        let hands = handsPath()
        hands.transform(using: transform as AffineTransform)
        hands.lineWidth = 5.5 * scale
        hands.lineCapStyle = .round
        hands.lineJoinStyle = .round
        hands.stroke()
        context.restoreGraphicsState()
    }

    /// Dome and flared lip as one shape.
    static func bellBody() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 14, y: 30))                                        // lip, lower left
        path.line(to: NSPoint(x: 86, y: 30))                                        // lip bottom edge
        path.curve(to: NSPoint(x: 92, y: 37), controlPoint1: NSPoint(x: 90, y: 30), controlPoint2: NSPoint(x: 92, y: 33))
        path.curve(to: NSPoint(x: 74, y: 52), controlPoint1: NSPoint(x: 92, y: 42), controlPoint2: NSPoint(x: 74, y: 44))
        path.line(to: NSPoint(x: 74, y: 64))                                        // right side
        path.appendArc(withCenter: NSPoint(x: 50, y: 64), radius: 24, startAngle: 0, endAngle: 180)  // dome
        path.line(to: NSPoint(x: 26, y: 52))                                        // left side
        path.curve(to: NSPoint(x: 8, y: 37), controlPoint1: NSPoint(x: 26, y: 44), controlPoint2: NSPoint(x: 8, y: 42))
        path.curve(to: NSPoint(x: 14, y: 30), controlPoint1: NSPoint(x: 8, y: 33), controlPoint2: NSPoint(x: 10, y: 30))
        path.close()
        return path
    }

    /// Half-disc clapper, separated from the lip so it survives at small sizes.
    static func clapperPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.appendArc(withCenter: NSPoint(x: 50, y: 25), radius: 12, startAngle: 180, endAngle: 360)
        path.close()
        return path
    }

    static func handsPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 50, y: 76))
        path.line(to: NSPoint(x: 50, y: 60))
        path.line(to: NSPoint(x: 62, y: 50))
        return path
    }
}
