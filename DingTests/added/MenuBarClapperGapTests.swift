import XCTest
import AppKit
@testable import Ding

/// The bell's clapper stays a separate shape from the lip in the menu bar template image.
final class MenuBarClapperGapTests: XCTestCase {
    private let menuBarPointSize: CGFloat = 18
    private let scale = 2

    /// Alpha of every pixel of the template image rendered at the menu bar size and the given scale. Row 0 is the top.
    private func renderedAlpha() throws -> [[CGFloat]] {
        let image = MenuBarGlyph.image(pointSize: menuBarPointSize)
        XCTAssertTrue(image.isTemplate)
        let px = Int(menuBarPointSize) * scale
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<px).map { y in (0..<px).map { x in rep.colorAt(x: x, y: y)?.alphaComponent ?? 0 } }
    }

    /// Pixels with any alpha connected (8-way) to the opaque pixels of the glyph's lowest row.
    private func lowestComponent(_ map: [[CGFloat]]) -> Set<[Int]> {
        let size = map.count
        guard let bottom = (0..<size).last(where: { y in map[y].contains { $0 > 0 } }) else { return [] }
        var seen = Set<[Int]>()
        var stack = (0..<size).filter { map[bottom][$0] > 0 }.map { [$0, bottom] }
        while let p = stack.popLast() {
            guard !seen.contains(p) else { continue }
            seen.insert(p)
            for dy in -1...1 { for dx in -1...1 {
                let x = p[0] + dx, y = p[1] + dy
                if x >= 0, y >= 0, x < size, y < size, map[y][x] > 0, !seen.contains([x, y]) { stack.append([x, y]) }
            } }
        }
        return seen
    }

    func test_DING_MENUBAR_003_keeps_aTransparentRowSeparatesTheClapperFromTheLip() throws {
        let map = try renderedAlpha()
        let opaque = map.flatMap { $0 }.filter { $0 > 0 }.count
        XCTAssertGreaterThan(opaque, 0, "DING-MENUBAR-003: the glyph draws something")

        // The clapper is the lowest shape of the bell, hanging below the lip; the clock hands are cut out of the dome
        // far above, so any gap they make is not the one this test looks for.
        let clapper = lowestComponent(map)
        XCTAssertLessThan(clapper.count, opaque, "DING-MENUBAR-003: the clapper's pixels do not touch the lip's")
        let minX = clapper.map { $0[0] }.min() ?? 0, maxX = clapper.map { $0[0] }.max() ?? 0
        let top = clapper.map { $0[1] }.min() ?? 0

        // Rows above the clapper, across its width: first a fully transparent row, then the lip.
        var gapRow: Int?
        var lipRow: Int?
        for y in stride(from: top - 1, through: 0, by: -1) {
            let row = (minX...maxX).map { map[y][$0] }
            if gapRow == nil {
                if row.allSatisfy({ $0 == 0 }) { gapRow = y } else { break }
            } else if row.contains(where: { $0 > 0 }) {
                lipRow = y
                break
            }
        }
        XCTAssertNotNil(gapRow, "DING-MENUBAR-003: a fully transparent row sits right above the clapper")
        XCTAssertNotNil(lipRow, "DING-MENUBAR-003: the lip is above that gap")
    }
}
