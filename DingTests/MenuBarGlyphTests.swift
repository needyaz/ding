import XCTest
import AppKit
@testable import Ding

final class MenuBarGlyphTests: XCTestCase {
    /// Renders the glyph (or any drawing) into an alpha-only bitmap.
    private func alphaMap(px: Int = 72, draw: (NSRect) -> Void) throws -> [[CGFloat]] {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<px).map { y in (0..<px).map { x in rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 } }
    }

    private func coverage(_ map: [[CGFloat]]) -> Double {
        let total = Double(map.count * map.count)
        return Double(map.flatMap { $0 }.filter { $0 > 0.5 }.count) / total
    }

    func testIsATemplateImageAtMenuBarSize() {
        let image = MenuBarGlyph.image()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(image.accessibilityDescription, "Ding")
    }

    func testCustomPointSize() {
        XCTAssertEqual(MenuBarGlyph.image(pointSize: 22).size, NSSize(width: 22, height: 22))
    }

    func testBellFillsAReasonableShareOfTheCanvas() throws {
        let map = try alphaMap { MenuBarGlyph.draw(in: $0) }
        let share = coverage(map)
        XCTAssertGreaterThan(share, 0.25, "glyph is too faint to read in the menu bar")
        XCTAssertLessThan(share, 0.65, "glyph is a blob")
    }

    func testCornersAreTransparentAndNothingTouchesTheEdge() throws {
        let map = try alphaMap { MenuBarGlyph.draw(in: $0) }
        let last = map.count - 1
        for (x, y) in [(0, 0), (last, 0), (0, last), (last, last)] {
            XCTAssertEqual(map[y][x], 0, accuracy: 0.01)
        }
        // A margin so the glyph never clips at the menu bar's edges.
        for i in 0...last {
            XCTAssertEqual(map[0][i], 0, accuracy: 0.01)
            XCTAssertEqual(map[last][i], 0, accuracy: 0.01)
            XCTAssertEqual(map[i][0], 0, accuracy: 0.01)
            XCTAssertEqual(map[i][last], 0, accuracy: 0.01)
        }
    }

    func testClockHandsAreKnockedOutOfTheDome() throws {
        let full = try alphaMap { MenuBarGlyph.draw(in: $0) }
        let withoutHands = try alphaMap { rect in
            // Same transform as `draw`, minus the cutout.
            let artwork = NSRect(x: 8, y: 12, width: 84, height: 78)
            let scale = min(rect.width, rect.height) * 0.9 / max(artwork.width, artwork.height)
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX - artwork.midX * scale, yBy: rect.midY - artwork.midY * scale)
            transform.scale(by: scale)
            NSColor.black.setFill()
            for path in [MenuBarGlyph.bellBody(), MenuBarGlyph.clapperPath()] {
                path.transform(using: transform as AffineTransform)
                path.fill()
            }
        }
        XCTAssertLessThan(coverage(full), coverage(withoutHands) - 0.01, "the hands should remove visible area")
    }

    func testClapperIsSeparatedFromTheLip() throws {
        // Down the vertical centerline there must be a gap between the lip and the clapper.
        let map = try alphaMap { MenuBarGlyph.draw(in: $0) }
        let mid = map.count / 2
        var runs = 0
        var inside = false
        for y in 0..<map.count {
            let solid = map[y][mid] > 0.5
            if solid && !inside { runs += 1 }
            inside = solid
        }
        // dome/lip run, clapper run (hands add a gap inside the dome, so at least 2).
        XCTAssertGreaterThanOrEqual(runs, 2)
    }

    func testPathsStayInsideTheDesignBox() {
        for path in [MenuBarGlyph.bellBody(), MenuBarGlyph.clapperPath(), MenuBarGlyph.handsPath()] {
            XCTAssertGreaterThanOrEqual(path.bounds.minX, 0)
            XCTAssertGreaterThanOrEqual(path.bounds.minY, 0)
            XCTAssertLessThanOrEqual(path.bounds.maxX, 100)
            XCTAssertLessThanOrEqual(path.bounds.maxY, 100)
        }
    }

    func testBellIsHorizontallyCentered() {
        XCTAssertEqual(MenuBarGlyph.bellBody().bounds.midX, 50, accuracy: 0.5)
        XCTAssertEqual(MenuBarGlyph.clapperPath().bounds.midX, 50, accuracy: 0.5)
    }
}
