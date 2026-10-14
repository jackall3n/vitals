import AppKit
import Testing
@testable import RunCatKit

@Suite struct IndicatorRendererTests {
    typealias Bar = IndicatorRenderer.Bar

    @Test func widthGrowsWithBarCount() {
        let one: CGFloat = 3 + 2            // one bar + 1pt padding each side
        let three: CGFloat = 3 * 3 + 2 * 2 + 2 // three bars, two gaps, padding
        #expect(IndicatorRenderer.imageWidth(barCount: 0) == 0)
        #expect(IndicatorRenderer.imageWidth(barCount: 1) == one)
        #expect(IndicatorRenderer.imageWidth(barCount: 3) == three)
    }

    @Test func rendersNothingForNoBars() {
        #expect(IndicatorRenderer.render(bars: []) == nil)
    }

    @Test func rendersImageOfExpectedSizeInBothAppearances() throws {
        let bars = [Bar(load: 0.2, level: .normal), Bar(load: 0.7, level: .warning), Bar(load: 1, level: .critical)]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            let image = try #require(IndicatorRenderer.render(bars: bars, appearance: appearance))
            #expect(image.size == NSSize(width: IndicatorRenderer.imageWidth(barCount: 3), height: IndicatorRenderer.imageHeight))
            #expect(!image.isTemplate, "coloured bars must not be tinted by the system")
        }
    }

    @Test func fillHeightTracksLoadAndIsNeverInvisible() throws {
        // Render single bars at different loads and compare the number of opaque pixels.
        func opaquePixels(load: Double) throws -> Int {
            let image = try #require(IndicatorRenderer.render(bars: [Bar(load: load, level: .critical)], appearance: NSAppearance(named: .aqua)))
            let rep = try #require(NSBitmapImageRep(data: image.tiffRepresentation!))
            var count = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y) else { continue }
                    // systemRed fill is distinctly red; the grey track and clear background are not.
                    if c.redComponent > 0.6, c.greenComponent < 0.5, c.alphaComponent > 0.5 { count += 1 }
                }
            }
            return count
        }
        let idle = try opaquePixels(load: 0)
        let half = try opaquePixels(load: 0.5)
        let full = try opaquePixels(load: 1)
        #expect(idle > 0, "idle bars still show a minimum nub")
        #expect(half > idle)
        #expect(full > half)
    }
}
