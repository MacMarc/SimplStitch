//
//  ImageTraceService.swift
//  SimplStitch
//
//  Issue #3: Bild → Stichdatei. Reduziert ein Foto/eine Grafik auf wenige Garnfarben
//  (k-means), sucht pro Farbe die Umrisse mit `VNDetectContoursRequest` (Vision-Framework,
//  läuft ohne Apple Intelligence und damit auch in der EU) und liefert sie als geschlossene
//  Polygone in Millimetern. Stichart, Dichte, Winkel und Unterlage pro Fläche kommen aus einem
//  `StitchAdvising` (StitchAdvisor.swift): immer die Stickregeln nach Ink/Stitch, auf Wunsch
//  zusätzlich Apple Intelligence.
//
//  Issue #53: Löcher werden ausgespart (weitere Teilpfade im `d`, Ink/Stitch zieht alle
//  kleineren Teilpfade vom grössten ab), und Flächen IN Löchern (z.B. weisse Schrift auf einem
//  Helm, der selbst in einem weissen Rand liegt) werden ebenfalls nachgezeichnet — vorher kamen
//  nur Vision-`topLevelContours` an, verschachtelte Flächen fielen weg. Der Hintergrund fällt nur
//  dort weg, wo er mit dem Bildrand verbunden ist: weisse Schrift auf weissem Hintergrund bleibt.
//  Umrisse werden geglättet (Bézier-Kurven), Ecken bleiben spitz.
//
//  Bewusste Vereinfachungen:
//  - Kleinere Flächen liegen in der Z-Order über grösseren (nach Fläche absteigend sortiert),
//    wie bei einfachen Auto-Digitizern.
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
    static let defaultColorCount = 4

    var colorCount: Int = defaultColorCount
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
/// in Design-Millimetern, Ursprung oben links wie im restlichen Canvas. `holes`: ausgesparte
/// Löcher, ebenfalls geschlossene Polygone innerhalb von `points`.
nonisolated struct TracedRegion: Equatable, Sendable {
    var points: [CGPoint]
    var color: TraceColor
    var holes: [[CGPoint]] = []

    /// Fläche ohne Löcher.
    var area: Double {
        holes.reduce(abs(Self.signedArea(of: points))) { $0 - abs(Self.signedArea(of: $1)) }
    }

    /// Umfang samt Lochrändern.
    var perimeter: Double {
        holes.reduce(Self.perimeter(of: points)) { $0 + Self.perimeter(of: $1) }
    }

    /// Shoelace-Formel; das Vorzeichen gibt den Umlaufsinn an.
    static func signedArea(of polygon: [CGPoint]) -> Double {
        guard polygon.count >= 3 else { return 0 }
        var sum = 0.0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    static func perimeter(of polygon: [CGPoint]) -> Double {
        guard polygon.count >= 2 else { return 0 }
        var sum = 0.0
        for index in polygon.indices {
            let a = polygon[index]
            let b = polygon[(index + 1) % polygon.count]
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

/// Schlägt pro nachgezeichneter Fläche einen Stichtyp vor (Grundregel für `RuleBasedStitchAdvisor`).
nonisolated protocol StitchTypeSuggesting {
    func suggestedStitchType(for region: TracedRegion) -> StitchType
}

/// Feine Linien (im Mittel schmaler als `runningStitchMaxWidthMillimeters`) werden als Laufstich
/// nachgefahren, alles andere als Tatami-Füllung. Satin bewusst nicht: InkStitchs SatinColumn
/// erwartet zwei Schienen, eine beliebige nachgezeichnete Fläche hat nur einen Umriss.
nonisolated struct RuleBasedStitchTypeSuggester: StitchTypeSuggesting {
    static let runningStitchMaxWidthMillimeters = 1.0

    func suggestedStitchType(for region: TracedRegion) -> StitchType {
        region.averageWidth < Self.runningStitchMaxWidthMillimeters ? .straight : .tatami
    }
}

nonisolated struct ImageTraceService: ImageTracing {
    static let workingMaxDimension = 1024
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
        var labels = ColorQuantizer.majorityFiltered(quantized.labels, width: bitmap.width, height: bitmap.height)
        if options.removesBackground,
           let background = ColorQuantizer.backgroundCluster(labels: labels, width: bitmap.width, height: bitmap.height) {
            labels = ColorQuantizer.removingBorderConnected(cluster: background, labels: labels, width: bitmap.width, height: bitmap.height)
        }

        let target = options.targetSizeMillimeters
        let millimetersPerPixel = min(target.width / Double(bitmap.width), target.height / Double(bitmap.height))
        let imageWidthMillimeters = Double(bitmap.width) * millimetersPerPixel
        let imageHeightMillimeters = Double(bitmap.height) * millimetersPerPixel
        let minimumArea = max(
            minimumRegionAreaMillimeters2,
            imageWidthMillimeters * imageHeightMillimeters * minimumRegionAreaFraction
        )

        let millimeterArea = millimetersPerPixel * millimetersPerPixel
        var regions: [TracedRegion] = []
        // Issue #53: jede zusammenhängende Fläche einzeln an Vision geben (zugeschnittene Maske nur
        // mit dieser Fläche). So ist ihre äussere Kontur sicher die einzige oberste Kontur und alle
        // Kinder sind ihre Löcher — Flächen in Löchern einer gleichfarbigen Fläche (weisses "ny" im
        // weissen Helm-Rand) sind eigene Komponenten und gehen nicht mehr verloren. Auf Visions
        // Verschachtelung über mehrere Ebenen verlassen wir uns bewusst nicht.
        for cluster in quantized.palette.indices {
            let color = quantized.palette[cluster]
            for component in ConnectedComponents.find(label: cluster, in: labels, width: bitmap.width, height: bitmap.height) {
                guard Double(component.pixels.count) * millimeterArea >= minimumArea,
                      let cropped = component.mask() else { continue }
                let request = VNDetectContoursRequest()
                request.detectsDarkOnLight = true
                request.contrastAdjustment = 1
                request.maximumImageDimension = max(cropped.width, cropped.height)
                try VNImageRequestHandler(cgImage: cropped.image, options: [:]).perform([request])
                guard let outer = request.results?.first?.topLevelContours.max(by: { $0.pointCount < $1.pointCount }) else { continue }

                // Gleiche Vereinfachungs-Toleranz in Pixeln wie auf dem ganzen Bild.
                let epsilon = simplificationEpsilon * Float(max(bitmap.width, bitmap.height)) / Float(max(cropped.width, cropped.height))
                func millimeterPoints(of contour: VNContour) -> [CGPoint] {
                    let simplified = (try? contour.polygonApproximation(epsilon: epsilon)) ?? contour
                    // Vision: normalisiert 0…1 in der Maske, Ursprung unten links → Design: mm,
                    // Ursprung oben links.
                    return simplified.normalizedPoints.map { point in
                        CGPoint(
                            x: (Double(cropped.originX) + Double(point.x) * Double(cropped.width)) * millimetersPerPixel,
                            y: (Double(cropped.originY) + (1 - Double(point.y)) * Double(cropped.height)) * millimetersPerPixel
                        )
                    }
                }

                let holes = outer.childContours
                    .map(millimeterPoints(of:))
                    .filter { $0.count >= 3 && abs(TracedRegion.signedArea(of: $0)) >= minimumArea }
                let region = TracedRegion(points: millimeterPoints(of: outer), color: color, holes: holes)
                guard region.points.count >= 3, region.area >= minimumArea else { continue }
                regions.append(region)
            }
        }

        regions.sort { $0.area > $1.area }
        guard !regions.isEmpty else { throw ImageTraceError.noShapesFound }
        return Array(regions.prefix(maximumRegionCount))
    }
}

/// Zusammenhängende Flächen eines Labels (8er-Nachbarschaft, wie Vision Konturen verfolgt).
nonisolated enum ConnectedComponents {
    nonisolated struct Component {
        /// Pixel-Indizes im ganzen Bild.
        var pixels: [Int]
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int
        let imageWidth: Int

        /// Maske nur dieser Fläche, auf ihr Rechteck zugeschnitten plus 1 Pixel weisser Rand, damit
        /// Vision den Umriss auch am Bildrand geschlossen findet. `origin` = Lage der Maske im Bild.
        func mask() -> (image: CGImage, originX: Int, originY: Int, width: Int, height: Int)? {
            let originX = minX - 1
            let originY = minY - 1
            let width = maxX - minX + 3
            let height = maxY - minY + 3
            var bytes = [UInt8](repeating: 255, count: width * height)
            for index in pixels {
                let x = index % imageWidth - originX
                let y = index / imageWidth - originY
                bytes[y * width + x] = 0
            }
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let image = CGImage(
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
                  ) else { return nil }
            return (image, originX, originY, width, height)
        }
    }

    static func find(label: Int, in labels: [Int], width: Int, height: Int) -> [Component] {
        var visited = [Bool](repeating: false, count: labels.count)
        var components: [Component] = []
        var stack: [Int] = []
        for seed in labels.indices where labels[seed] == label && !visited[seed] {
            visited[seed] = true
            stack.append(seed)
            var component = Component(pixels: [], minX: width, minY: height, maxX: 0, maxY: 0, imageWidth: width)
            while let index = stack.popLast() {
                component.pixels.append(index)
                let x = index % width
                let y = index / width
                component.minX = min(component.minX, x)
                component.minY = min(component.minY, y)
                component.maxX = max(component.maxX, x)
                component.maxY = max(component.maxY, y)
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let neighbor = ny * width + nx
                        if !visited[neighbor] && labels[neighbor] == label {
                            visited[neighbor] = true
                            stack.append(neighbor)
                        }
                    }
                }
            }
            components.append(component)
        }
        return components
    }
}

// MARK: Nachgezeichnete Flächen → DesignObjects

extension ImageTraceService {
    /// Läuft auf dem MainActor (DesignObject ist ein SwiftData-Model). Reihenfolge = Z-Order:
    /// grosse Flächen zuerst (hinten), kleinere darüber.
    /// `advice` gehört Index für Index zu `regions` (siehe `StitchAdvising`); ohne (oder bei
    /// abweichender Länge) gelten die Stickregeln.
    /// `threads`: Garne der Standard-Garnliste — jede Fläche bekommt das nächstliegende davon, damit
    /// das Ergebnis ohne Nacharbeit mit echten Garnen exportiert werden kann. Leer → Bildfarbe.
    @MainActor
    static func designObjects(
        from regions: [TracedRegion],
        advice: [RegionStitchAdvice]? = nil,
        threads: [ThreadCandidate] = []
    ) -> [DesignObject] {
        let advice = advice.flatMap { $0.count == regions.count ? $0 : nil }
            ?? RuleBasedStitchAdvisor().ruleAdvice(for: regions)
        return zip(regions, advice).map { region, regionAdvice in
            let bounds = region.bounds
            let object = DesignObject(
                name: String(localized: "imageTrace.object.defaultName"),
                kind: .path,
                positionX: bounds.minX,
                positionY: bounds.minY,
                width: max(bounds.width, 0.01),
                height: max(bounds.height, 0.01)
            )
            object.pathData = pathData(for: region.points, holes: region.holes)
            if let thread = ThreadCandidate.nearest(to: region.color, in: threads) {
                object.fillColorHex = thread.hex
                object.threadColor = ThreadColor(
                    name: thread.name,
                    red: thread.red,
                    green: thread.green,
                    blue: thread.blue,
                    catalogNumber: thread.catalogNumber
                )
            } else {
                object.fillColorHex = region.color.hex
            }

            // Beim Laufstich ist `density` die Stichlänge (siehe SVGDesignSerializer).
            let settings = StitchSettings(
                stitchType: regionAdvice.stitchType,
                density: regionAdvice.density,
                angleDegrees: regionAdvice.angleDegrees,
                underlayType: regionAdvice.underlayType
            )
            settings.designObject = object
            object.stitchSettings = settings
            return object
        }
    }

    /// Knickt der Umriss an einem Punkt stärker ab, bleibt dort eine Ecke; sonst wird geglättet.
    static let cornerAngleDegrees = 50.0

    /// Ein geschlossener Teilpfad pro Polygon: zuerst der Umriss, danach die Löcher — gegenläufig
    /// zum Umriss, damit sie auch beim Canvas-Füllen (Nonzero-Regel) frei bleiben. Ink/Stitch zieht
    /// alle kleineren Teilpfade vom grössten ab (FillStitch.original_shape).
    static func pathData(for points: [CGPoint], holes: [[CGPoint]] = []) -> String {
        guard points.count >= 3 else { return "" }
        let outerIsPositive = TracedRegion.signedArea(of: points) >= 0
        var subpaths = [smoothSubpath(points)]
        for hole in holes where hole.count >= 3 {
            let holeIsPositive = TracedRegion.signedArea(of: hole) >= 0
            subpaths.append(smoothSubpath(holeIsPositive == outerIsPositive ? Array(hole.reversed()) : hole))
        }
        return subpaths.joined(separator: " ")
    }

    /// Geschlossener Teilpfad durch alle Punkte. An Ecken (Knick über `cornerAngleDegrees`) gerade
    /// Linien, sonst kubische Bézier-Kurven mit Tangente parallel zur Verbindung der Nachbarpunkte —
    /// so werden Rundungen aus der Pixeltreppe wieder rund, Ecken bleiben spitz. Ein geschlossenes
    /// Kurvenende wird ausgeschrieben, weil `Z` nur eine Gerade zurück zum Start zieht.
    static func smoothSubpath(_ points: [CGPoint]) -> String {
        let count = points.count
        let tangents: [CGVector?] = points.indices.map { index in
            let previous = points[(index + count - 1) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let incoming = CGVector(dx: current.x - previous.x, dy: current.y - previous.y)
            let outgoing = CGVector(dx: next.x - current.x, dy: next.y - current.y)
            let incomingLength = hypot(incoming.dx, incoming.dy)
            let outgoingLength = hypot(outgoing.dx, outgoing.dy)
            guard incomingLength > 0, outgoingLength > 0 else { return nil }
            let cosine = Double((incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) / (incomingLength * outgoingLength))
            // Knickwinkel ≤ Grenze ⇔ Kosinus ≥ Kosinus der Grenze.
            guard cosine >= Foundation.cos(cornerAngleDegrees * Double.pi / 180) else { return nil }
            let direction = CGVector(dx: next.x - previous.x, dy: next.y - previous.y)
            let length = hypot(direction.dx, direction.dy)
            return length > 0 ? CGVector(dx: direction.dx / length, dy: direction.dy / length) : nil
        }

        var parts = ["M\(format(points[0].x)),\(format(points[0].y))"]
        for index in points.indices {
            let start = points[index]
            let endIndex = (index + 1) % count
            let end = points[endIndex]
            let isClosingSegment = endIndex == 0
            guard tangents[index] != nil || tangents[endIndex] != nil else {
                if !isClosingSegment { parts.append("L\(format(end.x)),\(format(end.y))") }
                continue
            }
            let handle = hypot(end.x - start.x, end.y - start.y) / 3
            let tangentStart = tangents[index] ?? CGVector(dx: 0, dy: 0)
            let tangentEnd = tangents[endIndex] ?? CGVector(dx: 0, dy: 0)
            let control1 = CGPoint(x: start.x + tangentStart.dx * handle, y: start.y + tangentStart.dy * handle)
            let control2 = CGPoint(x: end.x - tangentEnd.dx * handle, y: end.y - tangentEnd.dy * handle)
            parts.append("C\(format(control1.x)),\(format(control1.y)) \(format(control2.x)),\(format(control2.y)) \(format(end.x)),\(format(end.y))")
        }
        parts.append("Z")
        return parts.joined(separator: " ")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

// MARK: Garnzuordnung

/// Wertkopie einer `ThreadColor` (SwiftData-Model), damit die Zuordnung ohne ModelContext testbar ist.
nonisolated struct ThreadCandidate: Equatable, Sendable {
    var name: String
    var red: Int
    var green: Int
    var blue: Int
    var catalogNumber: String?

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    /// Nächstes Garn nach "Redmean"-Abstand — eine einfache, wahrnehmungsnähere Gewichtung als der
    /// reine RGB-Abstand (Rot/Blau je nach Rotanteil unterschiedlich stark).
    static func nearest(to color: TraceColor, in candidates: [ThreadCandidate]) -> ThreadCandidate? {
        candidates.min { distance($0, color) < distance($1, color) }
    }

    static func distance(_ candidate: ThreadCandidate, _ color: TraceColor) -> Double {
        let redMean = (Double(candidate.red) + Double(color.red)) / 2
        let dr = Double(candidate.red) - Double(color.red)
        let dg = Double(candidate.green) - Double(color.green)
        let db = Double(candidate.blue) - Double(color.blue)
        return (2 + redMean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - redMean) / 256) * db * db
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
    /// winzigen Konturen würde. Bei Gleichstand bleibt das eigene Label — ausser das Pixel gehört zu
    /// einer höchstens 1 Pixel breiten Linie (höchstens 3 gleiche in der 3×3-Nachbarschaft): solche
    /// Säume entstehen an geglätteten Kanten zwischen zwei Farben (Issue #53, z.B. rötliche Ränder
    /// um graue Gitterstäbe) und wären ohnehin nicht stickbar.
    static func majorityFiltered(_ labels: [Int], width: Int, height: Int) -> [Int] {
        guard width > 2, height > 2, let maxLabel = labels.max() else { return labels }
        var result = labels
        // Labels reichen von -1 (transparent) bis `maxLabel`; Zähler-Index = Label + 1.
        var counts = [Int](repeating: 0, count: maxLabel + 2)
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                for slot in counts.indices { counts[slot] = 0 }
                for dy in -1...1 {
                    let row = (y + dy) * width + x
                    for dx in -1...1 {
                        counts[labels[row + dx] + 1] += 1
                    }
                }
                let own = labels[y * width + x]
                let ownCount = counts[own + 1]
                var bestLabel = own
                var bestCount = 0
                for slot in counts.indices where slot != own + 1 && counts[slot] > bestCount {
                    bestLabel = slot - 1
                    bestCount = counts[slot]
                }
                if bestCount > ownCount || (ownCount <= 3 && bestCount > 0) {
                    result[y * width + x] = bestLabel
                }
            }
        }
        return result
    }

    /// Issue #53: Nur der mit dem Bildrand verbundene Teil des Hintergrund-Clusters wird entfernt
    /// (Label -1). Gleichfarbige Flächen, die ganz von anderen Farben umschlossen sind — weisse
    /// Schrift auf einem Logo vor weissem Hintergrund — bleiben erhalten. Transparente Pixel
    /// verbinden mit, sie sind ohnehin Hintergrund.
    static func removingBorderConnected(cluster: Int, labels: [Int], width: Int, height: Int) -> [Int] {
        guard width > 0, height > 0 else { return labels }
        var result = labels
        var visited = [Bool](repeating: false, count: labels.count)
        var stack: [Int] = []
        func visit(_ index: Int) {
            guard !visited[index], labels[index] == cluster || labels[index] == -1 else { return }
            visited[index] = true
            stack.append(index)
        }
        for x in 0..<width {
            visit(x)
            visit((height - 1) * width + x)
        }
        for y in 0..<height {
            visit(y * width)
            visit(y * width + width - 1)
        }
        while let index = stack.popLast() {
            result[index] = -1
            let x = index % width
            let y = index / width
            if x > 0 { visit(index - 1) }
            if x < width - 1 { visit(index + 1) }
            if y > 0 { visit(index - width) }
            if y < height - 1 { visit(index + width) }
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
