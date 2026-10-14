//
//  ImageTraceServiceTests.swift
//  SimplStitchTests
//
//  Issue #3: Farbreduktion, Hintergrund-Erkennung, Flächen-Kennzahlen, Stichtyp-Regeln,
//  Umwandlung in DesignObjects und ein Vision-Durchlauf mit einem synthetischen Bild.
//

import Testing
import Foundation
import CoreGraphics
@testable import SimplStitch

@MainActor
struct ImageTraceServiceTests {

    private func square(x: Double, y: Double, size: Double) -> [CGPoint] {
        [CGPoint(x: x, y: y), CGPoint(x: x + size, y: y), CGPoint(x: x + size, y: y + size), CGPoint(x: x, y: y + size)]
    }

    private func bitmap(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) -> RGBABitmap {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                pixels += pixel(x, y)
            }
        }
        return RGBABitmap(width: width, height: height, pixels: pixels)
    }

    /// Weisses Bild mit rotem Quadrat in der Mitte (halbe Kantenlänge).
    private func redSquareImage(size: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(srgbRed: 0.85, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: size / 4, y: size / 4, width: size / 2, height: size / 2))
        return context.makeImage()!
    }

    @Test func regionMetricsOfSquare() {
        let region = TracedRegion(points: square(x: 2, y: 3, size: 10), color: TraceColor(red: 0, green: 0, blue: 0))
        #expect(region.area == 100)
        #expect(region.perimeter == 40)
        #expect(region.averageWidth == 5)
        #expect(region.bounds == CGRect(x: 2, y: 3, width: 10, height: 10))
    }

    @Test func ruleSuggesterUsesRunningStitchOnlyForThinLines() {
        let suggester = RuleBasedStitchTypeSuggester()
        let thin = TracedRegion(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 30, y: 0.5), CGPoint(x: 0, y: 0.5)],
            color: TraceColor(red: 0, green: 0, blue: 0)
        )
        let wide = TracedRegion(points: square(x: 0, y: 0, size: 10), color: TraceColor(red: 0, green: 0, blue: 0))
        #expect(suggester.suggestedStitchType(for: thin) == .straight)
        #expect(suggester.suggestedStitchType(for: wide) == .tatami)
    }

    @Test func quantizerSeparatesTwoColors() {
        let image = bitmap(width: 4, height: 4) { x, _ in x < 2 ? [255, 255, 255, 255] : [200, 0, 0, 255] }
        let result = ColorQuantizer.quantize(image, colorCount: 2)
        #expect(result.palette.count == 2)
        #expect(Set(result.palette.map(\.hex)) == ["#FFFFFF", "#C80000"])
        #expect(result.labels[0] != result.labels[3])
        #expect(result.labels[0] == result.labels[1])
    }

    @Test func transparentPixelsAreNeverLabeled() {
        let image = bitmap(width: 2, height: 1) { x, _ in x == 0 ? [0, 0, 0, 0] : [10, 20, 30, 255] }
        let result = ColorQuantizer.quantize(image, colorCount: 2)
        #expect(result.labels[0] == -1)
        #expect(result.labels[1] >= 0)
    }

    @Test func backgroundIsTheDominantBorderCluster() {
        // 4×4, Rand Cluster 0, Mitte Cluster 1.
        let labels = [0, 0, 0, 0,
                      0, 1, 1, 0,
                      0, 1, 1, 0,
                      0, 0, 0, 0]
        #expect(ColorQuantizer.backgroundCluster(labels: labels, width: 4, height: 4) == 0)

        let transparentBorder = labels.map { $0 == 0 ? -1 : $0 }
        #expect(ColorQuantizer.backgroundCluster(labels: transparentBorder, width: 4, height: 4) == nil)
    }

    @Test func majorityFilterRemovesIsolatedPixel() {
        var labels = [Int](repeating: 0, count: 9)
        labels[4] = 1
        #expect(ColorQuantizer.majorityFiltered(labels, width: 3, height: 3)[4] == 0)
    }

    @Test func pathDataIsClosedPolygon() {
        let data = ImageTraceService.pathData(for: square(x: 0, y: 0, size: 2))
        #expect(data == "M0.000,0.000 L2.000,0.000 L2.000,2.000 L0.000,2.000 Z")
    }

    @Test func regionsBecomePathObjectsWithStitchSettings() {
        let region = TracedRegion(points: square(x: 5, y: 6, size: 10), color: TraceColor(red: 200, green: 0, blue: 0))
        let objects = ImageTraceService.designObjects(from: [region])
        #expect(objects.count == 1)
        let object = objects[0]
        #expect(object.kind == .path)
        #expect(object.fillColorHex == "#C80000")
        #expect(object.positionX == 5)
        #expect(object.positionY == 6)
        #expect(object.width == 10)
        #expect(object.height == 10)
        #expect(object.stitchSettings?.stitchType == .tatami)
        #expect(object.pathData?.hasSuffix("Z") == true)
    }

    @Test func tracingFindsTheSquareAndDropsTheBackground() throws {
        let options = ImageTraceOptions(colorCount: 2, removesBackground: true, targetSizeMillimeters: CGSize(width: 100, height: 100))
        let regions = try ImageTraceService.trace(redSquareImage(size: 200), options: options)

        #expect(regions.count == 1)
        let region = try #require(regions.first)
        #expect(region.color.red > 180)
        #expect(region.color.green < 60)
        // Quadrat liegt bei 25…75 mm; Vision/Vereinfachung dürfen um wenige Pixel abweichen.
        let bounds = region.bounds
        #expect(abs(bounds.minX - 25) < 2)
        #expect(abs(bounds.minY - 25) < 2)
        #expect(abs(bounds.width - 50) < 3)
        #expect(abs(bounds.height - 50) < 3)
    }
}
