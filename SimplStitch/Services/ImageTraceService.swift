//
//  ImageTraceService.swift
//  SimplStitch
//
//  Issue #3: Bild → Stichdatei. Reduziert ein Foto/eine Grafik auf wenige Garnfarben
//  (k-means), sucht pro Farbe die Umrisse mit `VNDetectContoursRequest` (Vision-Framework,
//  läuft ohne Apple Intelligence und damit auch in der EU) und liefert sie als geschlossene
//  Polygone in Millimetern. Der Stichtyp pro Fläche kommt aus einem austauschbaren
//  `StitchTypeSuggesting` — vorerst regelbasiert, ein Apple-Intelligence- oder Plugin-Modell
//  kann später dieselbe Schnittstelle bedienen.
//
//  Bewusste Vereinfachungen (v1):
//  - Löcher (innere Konturen) werden nicht ausgespart: kleinere Flächen liegen in der Z-Order
//    über grösseren (nach Fläche absteigend sortiert), wie bei einfachen Auto-Digitizern.
//    `EditablePath` kennt ohnehin nur ein `isClosed` für den letzten Teilpfad.
//  - Gearbeitet wird auf einer auf `workingMaxDimension` verkleinerten Kopie — schneller und
//    glattere Umrisse; für Stickerei ist feineres Detail ohnehin nicht stickbar.
//

import Foundation
import CoreGraphics
import ImageIO
import Vision
import simd

nonisolated struct ImageTraceOptions: Equatable, Sendable {
    static let colorCountRange = 2...8

    var colorCount: Int = 4
    /// Die Farbe, die am Bildrand überwiegt, gilt als Hintergrund und wird nicht nachgezeichnet.
    var removesBackground: Bool = true
    /// Das Bild wird unter Beibehaltung des Seitenverhältnisses in diese Grösse eingepasst.
    var targetSizeMillimeters: CGSize
}

nonisolated struct TraceColor: Equatable, Sendable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
}

/// Eine nachgezeichnete Farbfläche: geschlossenes Polygon (erster Punkt wird nicht wiederholt)
/// in Design-Millimetern, Ursprung oben links wie im restlichen Canvas.
nonisolated struct TracedRegion: Equatable, Sendable {
    var points: [CGPoint]
    var color: TraceColor

    var area: Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    var perimeter: Double {
        guard points.count >= 2 else { return 0 }
        var sum = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += hypot(b.x - a.x, b.y - a.y)
        }
        return sum
    }

    /// Mittlere Breite der Fläche (2·Fläche / Umfang) — bei einem langen schmalen Streifen
    /// ziemlich genau seine Breite, bei einem Kreis der halbe Radius.
    var averageWidth: Double {
        let perimeter = perimeter
        return perimeter > 0 ? 2 * area / perimeter : 0
    }

    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

nonisolated enum ImageTraceError: LocalizedError {
    case unreadableImage
    case noShapesFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage: return String(localized: "imageTrace.error.unreadable")
        case .noShapesFound: return String(localized: "imageTrace.error.noShapes")
        }
    }
}

protocol ImageTracing {
    func traceImage(at url: URL, options: ImageTraceOptions) async throws -> [TracedRegion]
}

/// Schlägt pro nachgezeichneter Fläche einen Stichtyp vor. Eigene Schnittstelle, damit später ein
/// Apple-Intelligence- oder Plugin-Modell die Regeln ersetzen kann, ohne den Rest anzufassen.
protocol StitchTypeSuggesting {
    func suggestedStitchType(for region: TracedRegion) -> StitchType
}

/// Feine Linien (im Mittel schmaler als `runningStitchMaxWidthMillimeters`) werden als Laufstich
/// nachgefahren, alles andere als Tatami-Füllung. Satin bewusst nicht: InkStitchs SatinColumn
/// erwartet zwei Schienen, eine beliebige nachgezeichnete Fläche hat nur einen Umriss.
struct RuleBasedStitchTypeSuggester: StitchTypeSuggesting {
    static let runningStitchMaxWidthMillimeters = 1.0

    func suggestedStitchType(for region: TracedRegion) -> StitchType {
        region.averageWidth < Self.runningStitchMaxWidthMillimeters ? .straight : .tatami
    }
}

nonisolated struct ImageTraceService: ImageTracing {
    static let workingMaxDimension = 512
    /// Toleranz der Polygon-Vereinfachung, relativ zur Bildgrösse (Vision-Normalkoordinaten).
    static let simplificationEpsilon: Float = 0.0015
    /// Flächen unter diesem Anteil der Zielfläche (oder unter 1 mm²) sind Rauschen.
    static let minimumRegionAreaFraction = 0.0005
    static let minimumRegionAreaMillimeters2 = 1.0
    static let maximumRegionCount = 300

    func traceImage(at url: URL, options: ImageTraceOptions) async throws -> [TracedRegion] {
        try await Task.detached(priority: .userInitiated) {
            guard let image = Self.loadImage(at: url) else { throw ImageTraceError.unreadableImage }
            return try Self.trace(image, options: options)
        }.value
    }

    static func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: workingMaxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    static func trace(_ image: CGImage, options: ImageTraceOptions) throws -> [TracedRegion] {
        guard let bitmap = RGBABitmap(image: image) else { throw ImageTraceError.unreadableImage }
        let colorCount = min(max(options.colorCount, ImageTraceOptions.colorCountRange.lowerBound), ImageTraceOptions.colorCountRange.upperBound)
        let quantized = ColorQuantizer.quantize(bitmap, colorCount: colorCount)
        let labels = ColorQuantizer.majorityFiltered(quantized.labels, width: bitmap.width, height: bitmap.height)
        let background = options.removesBackground
            ? ColorQuantizer.backgroundCluster(labels: labels, width: bitmap.width, height: bitmap.height)
            : nil

        let target = options.targetSizeMillimeters
        let millimetersPerPixel = min(target.width / Double(bitmap.width), target.height / Double(bitmap.height))
        let imageWidthMillimeters = Double(bitmap.width) * millimetersPerPixel
        let imageHeightMillimeters = Double(bitmap.height) * millimetersPerPixel
        let minimumArea = max(
            minimumRegionAreaMillimeters2,
            imageWidthMillimeters * imageHeightMillimeters * minimumRegionAreaFraction
        )

        var regions: [TracedRegion] = []
        for cluster in quantized.palette.indices where cluster != background {
            guard let mask = makeMask(labels: labels, cluster: cluster, width: bitmap.width, height: bitmap.height) else { continue }
            let request = VNDetectContoursRequest()
            request.detectsDarkOnLight = true
            request.contrastAdjustment = 1
            request.maximumImageDimension = max(bitmap.width, bitmap.height)
            try VNImageRequestHandler(cgImage: mask, options: [:]).perform([request])
            guard let observation = request.results?.first else { continue }

            for contour in observation.topLevelContours {
                let simplified = (try? contour.polygonApproximation(epsilon: simplificationEpsilon)) ?? contour
                // Vision: normalisiert 0…1, Ursprung unten links → Design: mm, Ursprung oben links.
                let points = simplified.normalizedPoints.map { point in
                    CGPoint(
                        x: Double(point.x) * imageWidthMillimeters,
                        y: (1 - Double(point.y)) * imageHeightMillimeters
                    )
                }
                let region = TracedRegion(points: points, color: quantized.palette[cluster])
                guard points.count >= 3, region.area >= minimumArea else { continue }
                regions.append(region)
            }
        }

        regions.sort { $0.area > $1.area }
        guard !regions.isEmpty else { throw ImageTraceError.noShapesFound }
        return Array(regions.prefix(maximumRegionCount))
    }

    /// Graustufen-Maske: Pixel des Clusters schwarz, alles andere weiss.
    static func makeMask(labels: [Int], cluster: Int, width: Int, height: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height)
        var hasPixels = false
        for index in labels.indices where labels[index] == cluster {
            pixels[index] = 0
            hasPixels = true
        }
        guard hasPixels else { return nil }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

// MARK: Nachgezeichnete Flächen → DesignObjects

extension ImageTraceService {
    /// Läuft auf dem MainActor (DesignObject ist ein SwiftData-Model). Reihenfolge = Z-Order:
    /// grosse Flächen zuerst (hinten), kleinere darüber.
    @MainActor
    static func designObjects(from regions: [TracedRegion], suggester: StitchTypeSuggesting = RuleBasedStitchTypeSuggester()) -> [DesignObject] {
        regions.map { region in
            let bounds = region.bounds
            let object = DesignObject(
                name: String(localized: "imageTrace.object.defaultName"),
                kind: .path,
                positionX: bounds.minX,
                positionY: bounds.minY,
                width: max(bounds.width, 0.01),
                height: max(bounds.height, 0.01)
            )
            object.pathData = pathData(for: region.points)
            object.fillColorHex = region.color.hex

            let stitchType = suggester.suggestedStitchType(for: region)
            let settings = StitchSettings(
                stitchType: stitchType,
                // Beim Laufstich ist `density` die Stichlänge (siehe SVGDesignSerializer).
                density: stitchType == .straight ? 2.5 : 0.4,
                angleDegrees: 0,
                underlayType: UnderlayType.suggested(for: stitchType)
            )
            settings.designObject = object
            object.stitchSettings = settings
            return object
        }
    }

    static func pathData(for points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        var parts = ["M\(format(first.x)),\(format(first.y))"]
        for point in points.dropFirst() {
            parts.append("L\(format(point.x)),\(format(point.y))")
        }
        parts.append("Z")
        return parts.joined(separator: " ")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

// MARK: Bitmap + Farbreduktion

nonisolated struct RGBABitmap {
    let width: Int
    let height: Int
    /// RGBA, 8 Bit pro Kanal, zeilenweise von oben nach unten.
    let pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }
}

nonisolated enum ColorQuantizer {
    /// Pixel mit weniger Deckkraft gelten als transparent (Label -1, nie nachgezeichnet).
    static let opaqueAlphaThreshold: UInt8 = 128
    static let iterationCount = 12

    nonisolated struct Result {
        var palette: [TraceColor]
        /// Ein Cluster-Index pro Pixel, -1 für transparent.
        var labels: [Int]
    }

    /// k-means im RGB-Raum. Deterministisch: Startzentren sind Helligkeits-Quantile, damit
    /// dasselbe Bild immer dieselben Formen liefert (und Tests stabil sind).
    static func quantize(_ bitmap: RGBABitmap, colorCount: Int) -> Result {
        let pixelCount = bitmap.width * bitmap.height
        var colors: [SIMD3<Double>] = []
        var opaqueIndices: [Int] = []
        colors.reserveCapacity(pixelCount)
        opaqueIndices.reserveCapacity(pixelCount)
        for index in 0..<pixelCount {
            let offset = index * 4
            let alpha = bitmap.pixels[offset + 3]
            guard alpha >= opaqueAlphaThreshold else { continue }
            // Premultiplied → zurückrechnen, sonst werden halbtransparente Kanten zu dunkel.
            let scale = 255 / Double(alpha)
            colors.append(SIMD3(
                min(Double(bitmap.pixels[offset]) * scale, 255),
                min(Double(bitmap.pixels[offset + 1]) * scale, 255),
                min(Double(bitmap.pixels[offset + 2]) * scale, 255)
            ))
            opaqueIndices.append(index)
        }

        var labels = [Int](repeating: -1, count: pixelCount)
        guard !colors.isEmpty else { return Result(palette: [], labels: labels) }

        let k = max(1, colorCount)
        let byLuminance = colors.sorted { luminance($0) < luminance($1) }
        var centers: [SIMD3<Double>] = (0..<k).map { cluster in
            byLuminance[min(byLuminance.count - 1, (cluster * 2 + 1) * byLuminance.count / (2 * k))]
        }

        // Zentren auf einer Stichprobe anpassen (schneller), danach alle Pixel zuordnen.
        let sampleStride = max(1, colors.count / 20_000)
        for _ in 0..<iterationCount {
            var sums = [SIMD3<Double>](repeating: .zero, count: k)
            var counts = [Int](repeating: 0, count: k)
            var index = 0
            while index < colors.count {
                let nearest = nearestCenter(to: colors[index], in: centers)
                sums[nearest] += colors[index]
                counts[nearest] += 1
                index += sampleStride
            }
            var moved = false
            for cluster in 0..<k where counts[cluster] > 0 {
                let newCenter = sums[cluster] / Double(counts[cluster])
                if simd_distance(newCenter, centers[cluster]) > 0.5 { moved = true }
                centers[cluster] = newCenter
            }
            if !moved { break }
        }

        for (colorIndex, pixelIndex) in opaqueIndices.enumerated() {
            labels[pixelIndex] = nearestCenter(to: colors[colorIndex], in: centers)
        }
        let palette = centers.map { center in
            TraceColor(
                red: UInt8(center.x.rounded().clamped(to: 0...255)),
                green: UInt8(center.y.rounded().clamped(to: 0...255)),
                blue: UInt8(center.z.rounded().clamped(to: 0...255))
            )
        }
        return Result(palette: palette, labels: labels)
    }

    /// Ein Durchgang 3×3-Mehrheitsfilter: entfernt Einzelpixel-Rauschen, das sonst zu unzähligen
    /// winzigen Konturen würde. Bei Gleichstand bleibt das eigene Label.
    static func majorityFiltered(_ labels: [Int], width: Int, height: Int) -> [Int] {
        guard width > 2, height > 2 else { return labels }
        var result = labels
        var counts: [Int: Int] = [:]
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                counts.removeAll(keepingCapacity: true)
                for dy in -1...1 {
                    for dx in -1...1 {
                        counts[labels[(y + dy) * width + x + dx], default: 0] += 1
                    }
                }
                let own = labels[y * width + x]
                if let best = counts.max(by: { $0.value < $1.value }), best.value > counts[own, default: 0] {
                    result[y * width + x] = best.key
                }
            }
        }
        return result
    }

    /// Häufigster Cluster am Bildrand. `nil`, wenn der Rand überwiegend transparent ist — dann
    /// ist die Transparenz der Hintergrund und keine echte Farbe soll wegfallen.
    static func backgroundCluster(labels: [Int], width: Int, height: Int) -> Int? {
        guard width > 0, height > 0 else { return nil }
        var counts: [Int: Int] = [:]
        var borderCount = 0
        func count(_ x: Int, _ y: Int) {
            counts[labels[y * width + x], default: 0] += 1
            borderCount += 1
        }
        for x in 0..<width {
            count(x, 0)
            if height > 1 { count(x, height - 1) }
        }
        if height > 2 {
            for y in 1..<(height - 1) {
                count(0, y)
                if width > 1 { count(width - 1, y) }
            }
        }
        if counts[-1, default: 0] * 2 > borderCount { return nil }
        counts[-1] = nil
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func nearestCenter(to color: SIMD3<Double>, in centers: [SIMD3<Double>]) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for (index, center) in centers.enumerated() {
            let distance = simd_distance_squared(color, center)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func luminance(_ color: SIMD3<Double>) -> Double {
        0.299 * color.x + 0.587 * color.y + 0.114 * color.z
    }
}

private extension Double {
    nonisolated func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
