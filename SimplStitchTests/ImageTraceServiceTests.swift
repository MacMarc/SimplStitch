//
//  ImageTraceServiceTests.swift
//  SimplStitchTests
//
//  Issue #3: Farbreduktion, Hintergrund-Erkennung, Flächen-Kennzahlen, Stichtyp-Regeln,
//  Umwandlung in DesignObjects und ein Vision-Durchlauf mit einem synthetischen Bild.
//  Issue #53: Löcher, Flächen in Löchern, Hintergrund nur am Rand, Kantensäume, Glättung.
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

    /// Transparentes (oder weisses) Bild, darauf nacheinander gefüllte Quadrate in Pixeln
    /// (Ursprung oben links). Eine `nil`-Farbe stanzt ein transparentes Loch.
    private func image(size: Int, opaqueWhiteBackground: Bool = false, squares: [(x: Int, y: Int, size: Int, color: CGColor?)]) -> CGImage {
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        if opaqueWhiteBackground {
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        for square in squares {
            // CGContext zählt y von unten.
            let rect = CGRect(x: square.x, y: size - square.y - square.size, width: square.size, height: square.size)
            if let color = square.color {
                context.setFillColor(color)
                context.fill(rect)
            } else {
                context.clear(rect)
            }
        }
        return context.makeImage()!
    }

    private let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    private let blue = CGColor(srgbRed: 0, green: 0.23, blue: 0.49, alpha: 1)

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

    @Test func holesReduceAreaAndPerimeterAddsUp() {
        let region = TracedRegion(
            points: square(x: 0, y: 0, size: 10),
            color: TraceColor(red: 0, green: 0, blue: 0),
            holes: [square(x: 4, y: 4, size: 2)]
        )
        #expect(region.area == 96)
        #expect(region.perimeter == 48)
    }

    @Test func pathDataWritesHolesAsCounterRotatingSubpaths() throws {
        let outer = square(x: 0, y: 0, size: 10)
        let hole = square(x: 4, y: 4, size: 2) // gleicher Umlaufsinn wie `outer`
        let data = ImageTraceService.pathData(for: outer, holes: [hole])
        let subpaths = data.split(separator: "M").map { "M" + $0.trimmingCharacters(in: .whitespaces) }
        #expect(subpaths.count == 2)

        let parsed = EditablePath(pathData: data)
        let holeStart = try #require(parsed.anchors.firstIndex(where: \.startsSubpath))
        let parsedOuter = parsed.anchors[..<holeStart].map(\.point)
        let parsedHole = parsed.anchors[holeStart...].map(\.point)
        #expect(TracedRegion.signedArea(of: Array(parsedOuter)) > 0)
        #expect(TracedRegion.signedArea(of: Array(parsedHole)) < 0)
    }

    @Test func smoothingKeepsCornersStraightAndRoundsCurves() {
        #expect(!ImageTraceService.pathData(for: square(x: 0, y: 0, size: 2)).contains("C"))

        let circle = (0..<24).map { step -> CGPoint in
            let angle = Double(step) / 24 * 2 * .pi
            return CGPoint(x: 10 + 5 * cos(angle), y: 10 + 5 * sin(angle))
        }
        let data = ImageTraceService.pathData(for: circle)
        #expect(data.contains("C"))
        #expect(!data.contains("L"))
    }

    @Test func majorityFilterRemovesOnePixelSeam() {
        // 5×5: oben Cluster 0, unten Cluster 1, dazwischen eine 1 Pixel breite Linie Cluster 2.
        let labels = [0, 0, 0, 0, 0,
                      0, 0, 0, 0, 0,
                      2, 2, 2, 2, 2,
                      1, 1, 1, 1, 1,
                      1, 1, 1, 1, 1]
        let filtered = ColorQuantizer.majorityFiltered(labels, width: 5, height: 5)
        #expect(!filtered[11...13].contains(2))
    }

    @Test func onlyBorderConnectedBackgroundIsRemoved() {
        // Rand Cluster 0, Ring Cluster 1, Mitte wieder Cluster 0 (umschlossen).
        let labels = [0, 0, 0, 0, 0,
                      0, 1, 1, 1, 0,
                      0, 1, 0, 1, 0,
                      0, 1, 1, 1, 0,
                      0, 0, 0, 0, 0]
        let result = ColorQuantizer.removingBorderConnected(cluster: 0, labels: labels, width: 5, height: 5)
        #expect(result[0] == -1)
        #expect(result[24] == -1)
        #expect(result[6] == 1)
        #expect(result[12] == 0)
    }

    @Test func transparentHoleIsCutOut() throws {
        // Blaues Quadrat 50…150 px mit transparentem Loch 90…110 px (Aussparung wie im "A").
        let picture = image(size: 200, squares: [(50, 50, 100, blue), (90, 90, 20, nil)])
        let options = ImageTraceOptions(colorCount: 2, removesBackground: true, targetSizeMillimeters: CGSize(width: 100, height: 100))
        let regions = try ImageTraceService.trace(picture, options: options)

        #expect(regions.count == 1)
        let region = try #require(regions.first)
        #expect(region.holes.count == 1)
        #expect(abs(region.area - (50 * 50 - 10 * 10)) < 120)
    }

    @Test func islandInsideAHoleIsTraced() throws {
        // Wie das Helm-Logo: weisser Rand um eine blaue Fläche, darin weisse Schrift (Quadrat).
        let picture = image(size: 200, squares: [(20, 20, 160, white), (40, 40, 120, blue), (80, 80, 40, white)])
        let options = ImageTraceOptions(colorCount: 2, removesBackground: true, targetSizeMillimeters: CGSize(width: 100, height: 100))
        let regions = try ImageTraceService.trace(picture, options: options)

        let inner = regions.first { region in
            region.color.blue > 200 && region.color.red > 200
                && abs(region.bounds.minX - 40) < 2 && abs(region.bounds.width - 20) < 3
        }
        #expect(inner != nil)
        // Die innere Fläche liegt über der blauen (kleiner = weiter hinten in der Liste).
        let blueIndex = try #require(regions.firstIndex { $0.color.blue > 100 && $0.color.red < 50 })
        let innerIndex = try #require(regions.firstIndex { $0 == inner })
        #expect(innerIndex > blueIndex)
        #expect(regions[blueIndex].holes.count == 1)
    }

    @Test func enclosedWhiteSurvivesBackgroundRemoval() throws {
        // Weisser Hintergrund, blaues Quadrat, darin weisses Quadrat: nur der Rand-Hintergrund fällt weg.
        let picture = image(size: 200, opaqueWhiteBackground: true, squares: [(50, 50, 100, blue), (90, 90, 20, white)])
        let options = ImageTraceOptions(colorCount: 2, removesBackground: true, targetSizeMillimeters: CGSize(width: 100, height: 100))
        let regions = try ImageTraceService.trace(picture, options: options)

        #expect(regions.count == 2)
        #expect(regions.allSatisfy { $0.bounds.width < 60 })
        let whiteRegion = try #require(regions.first { $0.color.red > 200 })
        #expect(abs(whiteRegion.bounds.width - 10) < 3)
    }
}
