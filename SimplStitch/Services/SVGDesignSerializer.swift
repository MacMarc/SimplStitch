//
//  SVGDesignSerializer.swift
//  SimplStitch
//
//  Konvertiert [DesignObject] ↔ content.svg. SVG nutzt native Elemente
//  (rect/ellipse/path/text) statt alles auf <path> zu reduzieren — bleibt
//  so lesbar und in Inkscape/InkStitch direkt öffenbar. Objekt-Metadaten
//  (Name, Z-Order, Rotation, Skew, Sperren/Sichtbarkeit) landen als
//  `data-ss-*`-Attribute, Sticheinstellungen als `inkstitch:*`-Attribute.
//
//  Vereinfachung (content.svg-Roundtrip): Rotation/Skew werden für `element(for:)`/
//  `borderElement(for:)` NICHT in eine SVG-`transform`-Matrix gebacken, sondern roh als
//  data-ss-Attribute mitgeführt — position/width/height bleiben so die kanonischen, unrotierten
//  Werte für Editier-UI/Handles (`CanvasStore`). Für den echten InkStitch-Aufruf reicht das nicht:
//  `generationElement(for:)`/`generationBorderElement(for:)` (Issue #30, Punkt 1) hängen dafür
//  zusätzlich ein natives `transform="matrix(...)"`-Attribut an (`withGenerationTransform`),
//  identisch zur Canvas-Vorschau (`DesignObject.visualTransform`).
//

import Foundation
import CoreGraphics

protocol SVGDesignSerializing {
    func encode(
        objects: [DesignObject],
        canvasSize: CGSize,
        backgroundImageFileName: String?,
        backgroundImageOpacity: Double,
        isBackgroundImageVisible: Bool,
        defaultThreadPaletteID: UUID?
    ) -> String
    func decode(svg: String) throws -> SVGDecodedDesign
    /// Markup für ein einzelnes Objekt (dasselbe Fragment, das `encode` pro Objekt in `content.svg`
    /// schreibt) — von `StitchGenerationService` wiederverwendet, um InkStitch dieselben
    /// `inkstitch:*`-Attribute zu übergeben, die auch im gespeicherten Projekt landen. Trägt immer
    /// die FÜLL-Sticheinstellungen (`object.stitchSettings`).
    func element(for object: DesignObject) -> String
    /// Issue #18: dieselbe Geometrie wie `element(for:)`, aber mit den RAND-Sticheinstellungen
    /// (`object.borderStitchSettings`) als `inkstitch:*`-Attribute statt der Füll-Einstellungen —
    /// eigener Aufruf für `StitchGenerationService`s zweiten (Rand-)Stichgenerierungs-Pass. `nil`,
    /// wenn das Objekt keine Randeinstellungen hat.
    func borderElement(for object: DesignObject) -> String?
    /// Text embroiderable: dieselbe Rolle wie `element(for:)`, aber Text wird hier NICHT als
    /// `<text>` geschrieben, sondern als `<path>` mit den echten Glyphen-Umrissen (siehe
    /// `GlyphOutlining`) — nur für die Stichgenerierung, `content.svg` bleibt unverändert
    /// `<text>` (editierbar). `nil`, wenn kein Pfad erzeugt werden kann (z.B. leerer Text).
    /// Für alle anderen Objektarten identisch zu `element(for:)`.
    func generationElement(for object: DesignObject) -> String?
    /// Rand-Pendant zu `generationElement(for:)` — für Text ebenfalls über die echten Glyphen-
    /// Umrisse, für alle anderen Objektarten identisch zu `borderElement(for:)`.
    func generationBorderElement(for object: DesignObject) -> String?
}

struct SVGDecodedDesign {
    var canvasSize: CGSize
    var objects: [DesignObject]
    var backgroundImageFileName: String?
    /// Issue #10: Default 1.0 für Dateien aus einer Zeit vor diesem Feld (kein `data-ss-bg-opacity`
    /// im `<image>`-Element -> volle Deckkraft, unverändertes Verhalten).
    var backgroundImageOpacity: Double = 1.0
    var isBackgroundImageVisible: Bool = true
    var defaultThreadPaletteID: UUID?
}

enum SVGDesignSerializerError: Error, LocalizedError {
    case invalidEncoding
    case parsingFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "SVG-Daten sind kein gültiges UTF-8."
        case .parsingFailed(let error):
            return "SVG konnte nicht geparst werden: \(error?.localizedDescription ?? "unbekannter Fehler")"
        }
    }
}

final class SVGDesignSerializer: SVGDesignSerializing {

    static let inkstitchNamespace = "http://inkstitch.org/namespace"

    private let glyphOutlineService: GlyphOutlining

    init(glyphOutlineService: GlyphOutlining = GlyphOutlineService()) {
        self.glyphOutlineService = glyphOutlineService
    }

    // MARK: Encode

    func encode(
        objects: [DesignObject],
        canvasSize: CGSize,
        backgroundImageFileName: String?,
        backgroundImageOpacity: Double = 1.0,
        isBackgroundImageVisible: Bool = true,
        defaultThreadPaletteID: UUID? = nil
    ) -> String {
        let defaultPaletteAttr = defaultThreadPaletteID.map { " data-ss-default-palette=\"\($0.uuidString)\"" } ?? ""
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkstitch="\(Self.inkstitchNamespace)" width="\(fmt(canvasSize.width))mm" height="\(fmt(canvasSize.height))mm" viewBox="0 0 \(fmt(canvasSize.width)) \(fmt(canvasSize.height))" data-ss-version="1"\(defaultPaletteAttr)>\n
        """

        if let backgroundImageFileName {
            // Issue #10: width/height entsprechen weiterhin der vollen Canvasgrösse — SVGs eigener
            // `preserveAspectRatio`-Default (`xMidYMid meet`) sorgt bei jedem echten SVG-Renderer
            // bereits für seitenverhältnis-erhaltendes Einpassen, ohne dass wir hier selbst eine
            // kleinere Bounding-Box berechnen müssten. `CanvasView` (unser eigener, kein SVG-
            // Renderer) muss dasselbe Einpassen manuell nachbilden, siehe dort. `opacity`/
            // `display` sind die nativen SVG-Attribute (falls die Datei je in einem echten
            // SVG-Viewer geöffnet wird), `data-ss-bg-*` die für unseren eigenen Decode robusten,
            // eindeutigen Pendants.
            let displayAttr = isBackgroundImageVisible ? "" : " display=\"none\""
            svg += "  <image href=\"assets/\(xmlEscapeAttribute(backgroundImageFileName))\" x=\"0\" y=\"0\" width=\"\(fmt(canvasSize.width))\" height=\"\(fmt(canvasSize.height))\" opacity=\"\(fmt(backgroundImageOpacity))\"\(displayAttr) data-ss-bg-opacity=\"\(fmt(backgroundImageOpacity))\" data-ss-bg-visible=\"\(isBackgroundImageVisible)\" data-ss-role=\"background\" />\n"
        }

        for object in objects.sorted(by: { $0.zIndex < $1.zIndex }) {
            svg += "  " + element(for: object) + "\n"
        }
        svg += "</svg>\n"
        return svg
    }

    func element(for object: DesignObject) -> String {
        let common = commonAttributes(for: object)
        switch object.kind {
        case .rectangle:
            return "<rect x=\"\(fmt(object.positionX))\" y=\"\(fmt(object.positionY))\" width=\"\(fmt(object.width))\" height=\"\(fmt(object.height))\" rx=\"\(fmt(object.cornerRadius))\" ry=\"\(fmt(object.cornerRadius))\" \(common) />"
        case .circle:
            let rx = object.width / 2
            let ry = object.height / 2
            return "<ellipse cx=\"\(fmt(object.positionX + rx))\" cy=\"\(fmt(object.positionY + ry))\" rx=\"\(fmt(rx))\" ry=\"\(fmt(ry))\" \(common) />"
        case .star:
            let pointCount = object.starPointCount ?? 5
            let d = Self.starPathData(x: object.positionX, y: object.positionY, width: object.width, height: object.height, pointCount: pointCount)
            return "<path d=\"\(d)\" data-ss-x=\"\(fmt(object.positionX))\" data-ss-y=\"\(fmt(object.positionY))\" data-ss-w=\"\(fmt(object.width))\" data-ss-h=\"\(fmt(object.height))\" data-ss-star-points=\"\(pointCount)\" \(common) />"
        case .path:
            let d = object.pathData ?? ""
            return "<path d=\"\(xmlEscapeAttribute(d))\" data-ss-x=\"\(fmt(object.positionX))\" data-ss-y=\"\(fmt(object.positionY))\" data-ss-w=\"\(fmt(object.width))\" data-ss-h=\"\(fmt(object.height))\" \(common) />"
        case .line:
            let d = object.pathData ?? ""
            return "<path d=\"\(xmlEscapeAttribute(d))\" data-ss-x=\"\(fmt(object.positionX))\" data-ss-y=\"\(fmt(object.positionY))\" data-ss-w=\"\(fmt(object.width))\" data-ss-h=\"\(fmt(object.height))\" data-ss-line=\"true\" \(common) />"
        case .text:
            let fontFamily = object.fontName ?? "Helvetica"
            let fontSize = object.fontSize ?? 12
            let text = xmlEscapeText(object.text ?? "")
            return "<text x=\"\(fmt(object.positionX))\" y=\"\(fmt(object.positionY))\" font-family=\"\(xmlEscapeAttribute(fontFamily))\" font-size=\"\(fmt(fontSize))\" data-ss-w=\"\(fmt(object.width))\" data-ss-h=\"\(fmt(object.height))\" \(common)>\(text)</text>"
        }
    }

    /// Siehe Protokoll-Dokumentation — dieselbe Geometrie wie `element(for:)`, aber mit den Rand-
    /// statt Füll-Sticheinstellungen. Bewusst eine leicht duplizierte Geometrie-Switch statt einer
    /// gemeinsamen Abstraktion mit `element(for:)`: die beiden Methoden unterscheiden sich nur in
    /// der Attribut-Quelle (Füll- vs. Randeinstellungen), eine Parametrisierung wäre hier mehr
    /// Indirektion als Ersparnis.
    func borderElement(for object: DesignObject) -> String? {
        guard let settings = object.borderStitchSettings else { return nil }
        let common = borderGenerationAttributes(for: object, settings: settings)
        switch object.kind {
        case .rectangle:
            return "<rect x=\"\(fmt(object.positionX))\" y=\"\(fmt(object.positionY))\" width=\"\(fmt(object.width))\" height=\"\(fmt(object.height))\" rx=\"\(fmt(object.cornerRadius))\" ry=\"\(fmt(object.cornerRadius))\" \(common) />"
        case .circle:
            let rx = object.width / 2
            let ry = object.height / 2
            return "<ellipse cx=\"\(fmt(object.positionX + rx))\" cy=\"\(fmt(object.positionY + ry))\" rx=\"\(fmt(rx))\" ry=\"\(fmt(ry))\" \(common) />"
        case .star:
            let pointCount = object.starPointCount ?? 5
            let d = Self.starPathData(x: object.positionX, y: object.positionY, width: object.width, height: object.height, pointCount: pointCount)
            return "<path d=\"\(d)\" \(common) />"
        case .path, .line:
            let d = object.pathData ?? ""
            return "<path d=\"\(xmlEscapeAttribute(d))\" \(common) />"
        case .text:
            // Text hat keinen Rand-Pfad (kein Vektorpfad ohne Text-zu-Pfad-Konvertierung, siehe 5d).
            return nil
        }
    }

    /// Text embroiderable: für alle Nicht-Text-Objekte identisch zu `element(for:)`. Für Text wird
    /// statt `<text>` ein `<path>` mit den echten Glyphen-Umrissen geschrieben (`GlyphOutlining`) —
    /// nur der Stichgenerierungs-Pass sieht das, `content.svg` (`element(for:)`) bleibt `<text>`.
    func generationElement(for object: DesignObject) -> String? {
        guard object.kind == .text else { return withGenerationTransform(element(for: object), for: object) }
        guard let glyphPath = glyphOutlineService.glyphOutlinePath(for: object) else { return nil }
        var attrs = [
            "id=\"\(object.id.uuidString)\"",
            "fill=\"\(object.fillColorHex)\"",
        ]
        if let settings = object.stitchSettings {
            attrs.append(contentsOf: stitchAttributes(for: settings))
        }
        return withGenerationTransform("<path d=\"\(xmlEscapeAttribute(glyphPath.svgPathData()))\" \(attrs.joined(separator: " ")) />", for: object)
    }

    /// Rand-Pendant zu `generationElement(for:)` — schliesst dieselbe, bislang dokumentierte Lücke
    /// ("Text hat keinen Rand-Pfad ohne Text-zu-Pfad-Konvertierung", siehe `borderElement(for:)`)
    /// jetzt für den Generierungs-Pass: die echten Glyphen-Umrisse sind ein valider Rand-Pfad.
    func generationBorderElement(for object: DesignObject) -> String? {
        guard object.kind == .text else {
            return borderElement(for: object).map { withGenerationTransform($0, for: object) }
        }
        guard let settings = object.borderStitchSettings,
              let glyphPath = glyphOutlineService.glyphOutlinePath(for: object) else { return nil }
        let attrs = [
            "id=\"\(object.id.uuidString)\"",
            "fill=\"\(object.borderColorHex ?? object.fillColorHex)\"",
        ] + stitchAttributes(for: settings)
        return withGenerationTransform("<path d=\"\(xmlEscapeAttribute(glyphPath.svgPathData()))\" \(attrs.joined(separator: " ")) />", for: object)
    }

    /// Issue #30 (Punkt 1): InkStitch (echter SVG-Parser) versteht ein natives `transform`-Attribut,
    /// unser `data-ss-rotation`/`data-ss-skew-*` dagegen nicht (siehe Dateikopf-Kommentar) — ohne
    /// dieses Attribut generierte InkStitch Stiche aus der ungedrehten/unverzerrten Rohgeometrie,
    /// während die Canvas-Vorschau (`DesignObject.visualTransform`) bereits korrekt drehte/scherte:
    /// optisch passend, aber der tatsächliche Stichpfad blieb an der alten Ausrichtung stehen. Nur
    /// für den Generierungs-Pass angehängt — `content.svg` selbst (`element(for:)`/
    /// `borderElement(for:)`, von `encode`/`decode` genutzt) bleibt bewusst unverändert, da
    /// position/width/height dort die kanonischen, unrotierten Werte für Editier-UI/Handles
    /// bleiben müssen (siehe `TransformSnapshot` in CanvasStore).
    private func withGenerationTransform(_ markup: String, for object: DesignObject) -> String {
        let transform = object.visualTransform
        guard !transform.isIdentity else { return markup }
        let matrix = "matrix(\(fmt(Double(transform.a))),\(fmt(Double(transform.b))),\(fmt(Double(transform.c))),\(fmt(Double(transform.d))),\(fmt(Double(transform.tx))),\(fmt(Double(transform.ty))))"
        guard let closingRange = markup.range(of: "/>", options: .backwards) else { return markup }
        return markup.replacingCharacters(in: closingRange, with: "transform=\"\(matrix)\" />")
    }

    private func borderGenerationAttributes(for object: DesignObject, settings: StitchSettings) -> String {
        var attrs = [
            "id=\"\(object.id.uuidString)\"",
            "data-ss-name=\"\(xmlEscapeAttribute(object.name))\"",
            "data-ss-rotation=\"\(fmt(object.rotationDegrees))\"",
            "data-ss-skew-x=\"\(fmt(object.skewXDegrees))\"",
            "data-ss-skew-y=\"\(fmt(object.skewYDegrees))\"",
            "fill=\"\(object.borderColorHex ?? object.fillColorHex)\"",
        ]
        attrs.append(contentsOf: stitchAttributes(for: settings))
        return attrs.joined(separator: " ")
    }

    private func commonAttributes(for object: DesignObject) -> String {
        var attrs = [
            "id=\"\(object.id.uuidString)\"",
            "data-ss-name=\"\(xmlEscapeAttribute(object.name))\"",
            "data-ss-z=\"\(object.zIndex)\"",
            "data-ss-visible=\"\(object.isVisible)\"",
            "data-ss-locked=\"\(object.isLocked)\"",
            "data-ss-rotation=\"\(fmt(object.rotationDegrees))\"",
            "data-ss-skew-x=\"\(fmt(object.skewXDegrees))\"",
            "data-ss-skew-y=\"\(fmt(object.skewYDegrees))\"",
            "fill=\"\(object.fillColorHex)\"",
            "data-ss-has-fill=\"\(object.hasFill)\"",
            "data-ss-has-border=\"\(object.hasBorder)\"",
            "data-ss-border-width=\"\(fmt(object.borderWidthMillimeters))\"",
        ]
        if let groupID = object.groupID {
            attrs.append("data-ss-group=\"\(groupID.uuidString)\"")
        }
        if let borderColorHex = object.borderColorHex {
            attrs.append("data-ss-border-color=\"\(borderColorHex)\"")
        }
        // Issue #18: Rand-Sticheinstellungen werden als eigenständige data-ss-border-*-Attribute
        // persistiert (rohe StitchType/UnderlayType-Rawvalues, kein inkstitch:*-Namespace) — die
        // Übersetzung in echte inkstitch:*-Attribute passiert erst bei der tatsächlichen Rand-
        // Stichgenerierung (`borderElement(for:)`), nicht beim content.svg-Roundtrip selbst.
        if let borderSettings = object.borderStitchSettings {
            attrs.append("data-ss-border-stitch-type=\"\(borderSettings.stitchType.rawValue)\"")
            attrs.append("data-ss-border-density=\"\(fmt(borderSettings.density))\"")
            attrs.append("data-ss-border-angle=\"\(fmt(borderSettings.angleDegrees))\"")
            attrs.append("data-ss-border-underlay=\"\(borderSettings.underlayType.rawValue)\"")
        }
        if let settings = object.stitchSettings {
            attrs.append(contentsOf: stitchAttributes(for: settings))
        }
        return attrs.joined(separator: " ")
    }

    /// `inkstitch:*`-Attribute passend zu echtem InkStitch (siehe Phase 6c) — jeder Stichtyp
    /// hat dort ein eigenes, nicht überlappendes Attribut-Set (kein gemeinsames `fill_method`/
    /// `angle`/`underlay` über alle Typen hinweg wie in der ursprünglichen, unverifizierten
    /// Phase-4-Fassung). `density` wird je Typ auf das jeweils passende reale Attribut gemappt.
    private func stitchAttributes(for settings: StitchSettings) -> [String] {
        switch settings.stitchType {
        case .tatami:
            var attrs = [
                "inkstitch:fill_method=\"tatami_fill\"",
                "inkstitch:angle=\"\(fmt(settings.angleDegrees))\"",
                "inkstitch:row_spacing_mm=\"\(fmt(settings.density))\"",
            ]
            // Real InkStitch kennt nur ein Bool (An/Aus), keine Typwahl — jeder Nicht-.none-Wert
            // schaltet die Unterlage ein (siehe Phase-6c-Kontext im Implementierungsplan).
            if settings.underlayType != .none {
                attrs.append("inkstitch:fill_underlay=\"true\"")
            }
            return attrs
        case .straight:
            // Laufstich kennt weder Winkel noch Unterlage — `density` wird zur Stichlänge.
            return ["inkstitch:running_stitch_length_mm=\"\(fmt(settings.density))\""]
        case .satin:
            // Satin kennt keinen Winkel (folgt der Pfadrichtung) und drei unabhängige,
            // kombinierbare Unterlage-Bools statt eines einzelnen Typs — unser `UnderlayType`
            // kann nur einen davon gleichzeitig ausdrücken (siehe Decode-Seite).
            var attrs = ["inkstitch:zigzag_spacing_mm=\"\(fmt(settings.density))\""]
            switch settings.underlayType {
            case .none:
                break
            case .centerWalk:
                attrs.append("inkstitch:center_walk_underlay=\"true\"")
            case .edgeWalk:
                attrs.append("inkstitch:contour_underlay=\"true\"")
            case .zigzagNet:
                attrs.append("inkstitch:zigzag_underlay=\"true\"")
            }
            return attrs
        }
    }

    static func starPathData(x: Double, y: Double, width: Double, height: Double, pointCount: Int) -> String {
        let cx = x + width / 2
        let cy = y + height / 2
        let outerRadius = min(width, height) / 2
        let innerRadius = outerRadius * 0.5
        let n = max(pointCount, 3)

        var command = "M"
        var path = ""
        for i in 0..<(n * 2) {
            let angle = (Double(i) * .pi / Double(n)) - (.pi / 2)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let px = cx + radius * cos(angle)
            let py = cy + radius * sin(angle)
            path += "\(command)\(String(format: "%.4f", px)),\(String(format: "%.4f", py)) "
            command = "L"
        }
        return path.trimmingCharacters(in: .whitespaces) + " Z"
    }

    // MARK: Decode

    func decode(svg: String) throws -> SVGDecodedDesign {
        guard let data = svg.data(using: .utf8) else {
            throw SVGDesignSerializerError.invalidEncoding
        }
        let parser = XMLParser(data: data)
        let delegate = ParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw SVGDesignSerializerError.parsingFailed(parser.parserError)
        }
        return SVGDecodedDesign(
            canvasSize: delegate.canvasSize,
            objects: delegate.objects,
            backgroundImageFileName: delegate.backgroundImageFileName,
            backgroundImageOpacity: delegate.backgroundImageOpacity,
            isBackgroundImageVisible: delegate.isBackgroundImageVisible,
            defaultThreadPaletteID: delegate.defaultThreadPaletteID
        )
    }

    /// Issue #6: generischer SVG-Import (beliebige Illustrator/Inkscape-Dateien, nicht nur unser
    /// eigenes `content.svg`-Schema). Für unsere eigenen Dateien bleibt das Verhalten unverändert
    /// (width/height in "mm", `viewBox` deckungsgleich mit den mm-Werten, keine `<g>`-Elemente) —
    /// `unitsToMillimeters` errechnet sich dabei immer exakt zu 1.0 und `transformStack` bleibt
    /// bei `[.identity]`, die neue Umrechnung ist also ein reiner No-op für den bestehenden
    /// Roundtrip (siehe `DocumentPackageManagerTests`).
    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var canvasSize: CGSize = .zero
        var objects: [DesignObject] = []
        var backgroundImageFileName: String?
        var backgroundImageOpacity: Double = 1.0
        var isBackgroundImageVisible: Bool = true
        var defaultThreadPaletteID: UUID?

        private var currentTextObject: DesignObject?
        private var currentTextBuffer = ""

        /// Skalierungsfaktor von SVG-"user units" (bestimmt durch `viewBox`, falls vorhanden, sonst
        /// durch die Einheit von `width`/`height`) zu Millimetern.
        private var unitsToMillimeters: Double = 1
        private var viewBoxOriginX: Double = 0
        private var viewBoxOriginY: Double = 0

        /// Akkumulierte `<g transform="…">`-Verschachtelung. **Vereinfachung:** nur `translate`/
        /// `scale` (sowie ein reines `matrix(a,0,0,d,e,f)` ohne Rotations-/Scherungsanteil) werden
        /// komponiert — deckt das häufigste Illustrator/Inkscape-Gruppierungsmuster ab (positionierte/
        /// skalierte Objektgruppen), `rotate()`/`skewX()`/`skewY()`/ein `matrix()` mit b≠0 oder c≠0
        /// werden als Identität behandelt (Position bleibt unverändert) statt eine vollständige
        /// Affine-Transform-Dekomposition in Rotation/Skew zu versuchen.
        private var transformStack: [CGAffineTransform] = [.identity]

        private enum LengthAxis { case x, y }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "svg":
                let (widthValue, widthUnit) = Self.parseLengthWithUnit(attributeDict["width"])
                let (heightValue, heightUnit) = Self.parseLengthWithUnit(attributeDict["height"])
                let viewBoxParts = attributeDict["viewBox"]?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap({ Double($0) })
                let hasValidViewBox = viewBoxParts?.count == 4 && (viewBoxParts?[2] ?? 0) > 0 && (viewBoxParts?[3] ?? 0) > 0

                if let widthValue, let heightValue {
                    // width/height explizit vorhanden (unser eigenes content.svg-Schema, oder eine
                    // fremde SVG-Datei, die ihre reale Grösse nennt) — unverändertes Verhalten.
                    let widthMM = widthValue * Self.millimetersPerUnit(widthUnit)
                    let heightMM = heightValue * Self.millimetersPerUnit(heightUnit)
                    canvasSize = CGSize(width: widthMM, height: heightMM)
                    if hasValidViewBox, let viewBoxParts {
                        viewBoxOriginX = viewBoxParts[0]
                        viewBoxOriginY = viewBoxParts[1]
                        unitsToMillimeters = widthMM / viewBoxParts[2]
                    } else {
                        unitsToMillimeters = Self.millimetersPerUnit(widthUnit)
                    }
                } else if hasValidViewBox, let viewBoxParts {
                    // Issue #28 (RC3): width/height fehlen komplett — bei Figma-/Web-Icon-Exporten
                    // sehr verbreitet (z.B. `<svg viewBox="0 0 24 24">` ohne width/height), aber es
                    // gibt eine gültige viewBox. Ohne diesen Fall wäre widthMM 0 und damit sowohl
                    // unitsToMillimeters als auch canvasSize auf 0 kollabiert — alle Objekte hätten
                    // auf dem Nullpunkt mit Grösse 0 gelandet (leere/unsichtbare Zeichenfläche).
                    // Fallback: viewBox-Ausdehnung direkt 1:1 als mm-Canvasgrösse übernehmen
                    // (1 SVG-User-Unit = 1mm) — ohne reale Grössenangabe in der Datei gibt es
                    // ohnehin keine "richtige" physische Grösse, das ist die plausibelste Annahme.
                    viewBoxOriginX = viewBoxParts[0]
                    viewBoxOriginY = viewBoxParts[1]
                    unitsToMillimeters = 1
                    canvasSize = CGSize(width: viewBoxParts[2], height: viewBoxParts[3])
                } else {
                    // Weder width/height noch viewBox — degenerierter Fall, bisheriges Verhalten
                    // (leere Canvasgrösse) unverändert beibehalten.
                    canvasSize = .zero
                    unitsToMillimeters = Self.millimetersPerUnit(widthUnit)
                }
                defaultThreadPaletteID = attributeDict["data-ss-default-palette"].flatMap { UUID(uuidString: $0) }
            case "g":
                let transform = Self.parseTransform(attributeDict["transform"])
                transformStack.append(transform.concatenating(transformStack.last ?? .identity))
            case "image":
                if attributeDict["data-ss-role"] == "background" {
                    let href = attributeDict["href"] ?? ""
                    backgroundImageFileName = href.replacingOccurrences(of: "assets/", with: "")
                    backgroundImageOpacity = Self.parseDouble(attributeDict["data-ss-bg-opacity"]) ?? 1.0
                    isBackgroundImageVisible = (attributeDict["data-ss-bg-visible"] ?? "true") == "true"
                }
            case "rect":
                objects.append(makeRectangle(attributeDict))
            case "ellipse":
                objects.append(makeEllipse(attributeDict))
            case "circle":
                objects.append(makeCircleShorthand(attributeDict))
            case "polygon":
                objects.append(makePolyShape(attributeDict, closed: true))
            case "polyline":
                objects.append(makePolyShape(attributeDict, closed: false))
            case "path":
                objects.append(makePathElement(attributeDict))
            case "text":
                let object = Self.makeText(attributeDict)
                currentTextObject = object
                currentTextBuffer = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentTextObject != nil else { return }
            currentTextBuffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "g":
                if transformStack.count > 1 {
                    transformStack.removeLast()
                }
            case "text":
                guard let object = currentTextObject else { return }
                object.text = currentTextBuffer
                objects.append(object)
                currentTextObject = nil
                currentTextBuffer = ""
            default:
                break
            }
        }

        /// Wendet die aktuell akkumulierte Gruppen-Transformation sowie die `viewBox`/Einheiten-
        /// Umrechnung auf einen Punkt an (in dieser Reihenfolge — die Gruppen-Transformation
        /// operiert in SVG-"user units", die `viewBox` bildet diese erst danach auf Millimeter ab).
        private func toDesignPoint(x: Double, y: Double) -> CGPoint {
            let transformed = CGPoint(x: x, y: y).applying(transformStack.last ?? .identity)
            return CGPoint(
                x: (transformed.x - viewBoxOriginX) * unitsToMillimeters,
                y: (transformed.y - viewBoxOriginY) * unitsToMillimeters
            )
        }

        /// Längen (Breite/Höhe/Radius) haben keine Position, nur eine Skalierung — nutzt die
        /// jeweilige Achsen-Skalierung der aktuellen Transformation (`a` bzw. `d`; exakt für die
        /// unterstützte translate/scale-Untermenge, siehe `transformStack`-Doku).
        private func toDesignLength(_ value: Double, axis: LengthAxis) -> Double {
            let t = transformStack.last ?? .identity
            let scale = axis == .x ? t.a : t.d
            return abs(value * scale * unitsToMillimeters)
        }

        private static func applyCommonAttributes(_ attrs: [String: String], to object: DesignObject) {
            if let idString = attrs["id"], let uuid = UUID(uuidString: idString) {
                object.id = uuid
            }
            object.name = attrs["data-ss-name"] ?? object.name
            object.zIndex = Int(attrs["data-ss-z"] ?? "") ?? 0
            object.isVisible = (attrs["data-ss-visible"] ?? "true") == "true"
            object.isLocked = (attrs["data-ss-locked"] ?? "false") == "true"
            object.rotationDegrees = parseDouble(attrs["data-ss-rotation"]) ?? 0
            object.skewXDegrees = parseDouble(attrs["data-ss-skew-x"]) ?? 0
            object.skewYDegrees = parseDouble(attrs["data-ss-skew-y"]) ?? 0
            object.fillColorHex = resolvedFillHex(attrs) ?? object.fillColorHex
            if let groupIDString = attrs["data-ss-group"], let groupID = UUID(uuidString: groupIDString) {
                object.groupID = groupID
            }
            object.hasFill = (attrs["data-ss-has-fill"] ?? "true") == "true"
            // Issue #6: fremde SVGs (kein data-ss-has-fill) mit fill:none/fill="none" — typisch für
            // reine Strichzeichnungen/Icons — werden als "keine Füllung" statt schwarz gefüllt erkannt.
            if attrs["data-ss-has-fill"] == nil, isFillExplicitlyNone(attrs) {
                object.hasFill = false
            }
            object.hasBorder = (attrs["data-ss-has-border"] ?? "false") == "true"
            object.borderWidthMillimeters = parseDouble(attrs["data-ss-border-width"]) ?? 0.3
            object.borderColorHex = attrs["data-ss-border-color"]
            if let borderStitchTypeRaw = attrs["data-ss-border-stitch-type"],
               let borderStitchType = StitchType(rawValue: borderStitchTypeRaw) {
                let borderSettings = StitchSettings(
                    stitchType: borderStitchType,
                    density: parseDouble(attrs["data-ss-border-density"]) ?? 0.4,
                    angleDegrees: parseDouble(attrs["data-ss-border-angle"]) ?? 0,
                    underlayType: UnderlayType(rawValue: attrs["data-ss-border-underlay"] ?? "") ?? .none
                )
                borderSettings.borderOwner = object
                object.borderStitchSettings = borderSettings
            }

            if let settings = Self.stitchSettings(from: attrs) {
                settings.designObject = object
                object.stitchSettings = settings
            }
        }

        /// Erkennt den Stichtyp anhand dessen, welches (nicht überlappende) reale InkStitch-
        /// Attribut vorhanden ist — es gibt kein gemeinsames Typ-Attribut mehr über alle drei
        /// Stichtypen hinweg (siehe `stitchAttributes(for:)` auf der Encode-Seite, Phase 6c).
        private static func stitchSettings(from attrs: [String: String]) -> StitchSettings? {
            if attrs["inkstitch:fill_method"] != nil {
                return StitchSettings(
                    stitchType: .tatami,
                    density: parseDouble(attrs["inkstitch:row_spacing_mm"]) ?? 0.4,
                    angleDegrees: parseDouble(attrs["inkstitch:angle"]) ?? 0,
                    underlayType: attrs["inkstitch:fill_underlay"] == "true" ? .centerWalk : .none
                )
            }
            if attrs["inkstitch:zigzag_spacing_mm"] != nil {
                let underlayType: UnderlayType
                if attrs["inkstitch:center_walk_underlay"] == "true" {
                    underlayType = .centerWalk
                } else if attrs["inkstitch:contour_underlay"] == "true" {
                    underlayType = .edgeWalk
                } else if attrs["inkstitch:zigzag_underlay"] == "true" {
                    underlayType = .zigzagNet
                } else {
                    underlayType = .none
                }
                return StitchSettings(
                    stitchType: .satin,
                    density: parseDouble(attrs["inkstitch:zigzag_spacing_mm"]) ?? 0.4,
                    angleDegrees: 0,
                    underlayType: underlayType
                )
            }
            if let length = attrs["inkstitch:running_stitch_length_mm"] {
                return StitchSettings(stitchType: .straight, density: parseDouble(length) ?? 0.4, angleDegrees: 0, underlayType: .none)
            }
            return nil
        }

        /// Instanzmethode (nicht `static`) — braucht `toDesignPoint`/`toDesignLength` fürs
        /// `<g transform="…">`/Einheiten-Handling (Issue #6). Für unsere eigenen Dateien (mm-
        /// Einheiten, keine `<g>`-Verschachtelung) ist das ein No-op, siehe Klassendoku.
        private func makeRectangle(_ attrs: [String: String]) -> DesignObject {
            let rawX = Self.parseDouble(attrs["x"]) ?? 0
            let rawY = Self.parseDouble(attrs["y"]) ?? 0
            let origin = toDesignPoint(x: rawX, y: rawY)
            let width = toDesignLength(Self.parseDouble(attrs["width"]) ?? 0, axis: .x)
            let height = toDesignLength(Self.parseDouble(attrs["height"]) ?? 0, axis: .y)
            let object = DesignObject(name: "", kind: .rectangle, positionX: origin.x, positionY: origin.y, width: width, height: height)
            object.cornerRadius = toDesignLength(Self.parseDouble(attrs["rx"]) ?? 0, axis: .x)
            Self.applyCommonAttributes(attrs, to: object)
            return object
        }

        private func makeEllipse(_ attrs: [String: String]) -> DesignObject {
            let cx = Self.parseDouble(attrs["cx"]) ?? 0
            let cy = Self.parseDouble(attrs["cy"]) ?? 0
            let rx = toDesignLength(Self.parseDouble(attrs["rx"]) ?? 0, axis: .x)
            let ry = toDesignLength(Self.parseDouble(attrs["ry"]) ?? 0, axis: .y)
            let center = toDesignPoint(x: cx, y: cy)
            let object = DesignObject(name: "", kind: .circle, positionX: center.x - rx, positionY: center.y - ry, width: rx * 2, height: ry * 2)
            Self.applyCommonAttributes(attrs, to: object)
            return object
        }

        /// Issue #6: `<circle cx cy r>` — bislang gar nicht erkannt (nur `<ellipse>`).
        private func makeCircleShorthand(_ attrs: [String: String]) -> DesignObject {
            let cx = Self.parseDouble(attrs["cx"]) ?? 0
            let cy = Self.parseDouble(attrs["cy"]) ?? 0
            let r = Self.parseDouble(attrs["r"]) ?? 0
            let rx = toDesignLength(r, axis: .x)
            let ry = toDesignLength(r, axis: .y)
            let center = toDesignPoint(x: cx, y: cy)
            let object = DesignObject(name: "", kind: .circle, positionX: center.x - rx, positionY: center.y - ry, width: rx * 2, height: ry * 2)
            Self.applyCommonAttributes(attrs, to: object)
            return object
        }

        /// Issue #6: `<polygon points="…">` (geschlossen) / `<polyline points="…">` (offen) — als
        /// `.path`-Objekt nachgezeichnet (M/L[/Z]), dieselbe Pfad-Maschinerie wie Freihand-Pfade.
        private func makePolyShape(_ attrs: [String: String], closed: Bool) -> DesignObject {
            let rawPoints = Self.parsePointsList(attrs["points"] ?? "")
            let points = rawPoints.map { toDesignPoint(x: $0.x, y: $0.y) }

            var pathData = ""
            for (index, point) in points.enumerated() {
                pathData += "\(index == 0 ? "M" : "L")\(String(format: "%.4f", point.x)),\(String(format: "%.4f", point.y)) "
            }
            if closed {
                pathData += "Z"
            }

            let minX = points.map(\.x).min() ?? 0
            let minY = points.map(\.y).min() ?? 0
            let maxX = points.map(\.x).max() ?? 0
            let maxY = points.map(\.y).max() ?? 0
            let object = DesignObject(
                name: "",
                kind: .path,
                positionX: minX,
                positionY: minY,
                width: max(maxX - minX, 0.01),
                height: max(maxY - minY, 0.01)
            )
            object.pathData = pathData.trimmingCharacters(in: .whitespaces)
            Self.applyCommonAttributes(attrs, to: object)
            return object
        }

        /// Issue #28 (RC1): Instanzmethode (nicht mehr `static`) — braucht `toDesignPoint` fürs
        /// `<g transform="…">`/Einheiten-Handling für fremde SVGs, dieselbe Begründung wie
        /// `makeRectangle`/`makePolyShape`.
        private func makePathElement(_ attrs: [String: String]) -> DesignObject {
            if let xString = attrs["data-ss-x"] {
                // Unser eigenes Schema — unverändertes Verhalten: `d` wird 1:1 durchgereicht statt
                // neu geparst/serialisiert, das garantiert den bisherigen VERLUSTFREIEN Roundtrip
                // (exakter String-Vergleich in DocumentPackageManagerTests). Für unsere eigenen
                // Dateien wäre eine Neu-Transformation ohnehin ein reiner No-op (unitsToMillimeters
                // == 1, kein `<g>`), aber eben nicht notwendigerweise byte-identisch neu formatiert.
                let x = Self.parseDouble(xString) ?? 0
                let y = Self.parseDouble(attrs["data-ss-y"]) ?? 0
                let width = Self.parseDouble(attrs["data-ss-w"]) ?? 0
                let height = Self.parseDouble(attrs["data-ss-h"]) ?? 0
                let isStar = attrs["data-ss-star-points"] != nil
                let isLine = attrs["data-ss-line"] == "true"
                let kind: DesignObjectKind = isStar ? .star : (isLine ? .line : .path)
                let object = DesignObject(name: "", kind: kind, positionX: x, positionY: y, width: width, height: height)
                if isStar {
                    object.starPointCount = Int(attrs["data-ss-star-points"] ?? "") ?? 5
                } else {
                    object.pathData = attrs["d"]
                }
                Self.applyCommonAttributes(attrs, to: object)
                return object
            }

            // Fremde SVG-Datei ohne unser Schema (kein data-ss-x): `d` tatsächlich parsen (RC2s
            // EditablePath-Parser, versteht jetzt reale SVG-Pfad-Syntax) und jeden Anker- sowie
            // Kontrollpunkt durch dieselbe Transform-/Einheiten-Pipeline schicken wie jedes andere
            // Element (`toDesignPoint`) — vorher blieben x/y/width/height bei 0, weil sie
            // ausschliesslich aus den (bei fremden Dateien nie vorhandenen) data-ss-*-Attributen
            // gelesen wurden. Bounding-Box danach aus den TRANSFORMIERTEN Punkten ableiten, analog
            // zu `makePolyShape`.
            var editable = EditablePath(pathData: attrs["d"] ?? "")
            for index in editable.anchors.indices {
                editable.anchors[index].point = toDesignPoint(x: editable.anchors[index].point.x, y: editable.anchors[index].point.y)
                if let controlIn = editable.anchors[index].controlIn {
                    editable.anchors[index].controlIn = toDesignPoint(x: controlIn.x, y: controlIn.y)
                }
                if let controlOut = editable.anchors[index].controlOut {
                    editable.anchors[index].controlOut = toDesignPoint(x: controlOut.x, y: controlOut.y)
                }
            }
            let bounds = editable.boundingBox
            let object = DesignObject(
                name: "",
                kind: .path,
                positionX: bounds.minX,
                positionY: bounds.minY,
                width: max(bounds.width, 0.01),
                height: max(bounds.height, 0.01)
            )
            object.pathData = editable.svgPathData()
            Self.applyCommonAttributes(attrs, to: object)
            return object
        }

        private static func makeText(_ attrs: [String: String]) -> DesignObject {
            let x = parseDouble(attrs["x"]) ?? 0
            let y = parseDouble(attrs["y"]) ?? 0
            let width = parseDouble(attrs["data-ss-w"]) ?? 0
            let height = parseDouble(attrs["data-ss-h"]) ?? 0
            let object = DesignObject(name: "", kind: .text, positionX: x, positionY: y, width: width, height: height)
            object.fontName = attrs["font-family"]
            object.fontSize = parseDouble(attrs["font-size"])
            Self.applyCommonAttributes(attrs, to: object)
            return object
        }

        private static func parseDouble(_ string: String?) -> Double? {
            guard let string else { return nil }
            let numericPart = string.prefix { $0.isNumber || $0 == "." || $0 == "-" }
            return Double(numericPart)
        }

        /// Trennt eine SVG-Länge ("12.5", "200px", "150pt", "10mm", …) in Zahl und Einheit —
        /// fehlt die Einheit, gilt sie per SVG-Spezifikation als "px" (siehe `millimetersPerUnit`).
        private static func parseLengthWithUnit(_ string: String?) -> (Double?, String?) {
            guard let string else { return (nil, nil) }
            let numericPart = string.prefix { $0.isNumber || $0 == "." || $0 == "-" }
            let unitPart = string.dropFirst(numericPart.count).trimmingCharacters(in: .whitespaces)
            return (Double(numericPart), unitPart.isEmpty ? nil : unitPart)
        }

        private static func millimetersPerUnit(_ unit: String?) -> Double {
            switch unit {
            case "mm": return 1
            case "cm": return 10
            case "in": return 25.4
            case "pt": return 25.4 / 72
            case "pc": return 25.4 / 6
            default: return 25.4 / 96 // "px" bzw. unitless (SVG-Default)
            }
        }

        /// Manueller Scanner statt `NSRegularExpression` (passt zum übrigen Pfad-Parsing-Stil,
        /// z.B. `DesignObjectPath`s M/L-Parser) — liest `name(arg, arg, …)`-Aufrufe nacheinander
        /// und komponiert sie zu einer einzigen `CGAffineTransform`. Siehe `transformStack`-Doku
        /// für die bewusst unterstützte Untermenge (translate/scale/reines matrix ohne Rotation).
        private static func parseTransform(_ string: String?) -> CGAffineTransform {
            guard let string else { return .identity }
            var transform = CGAffineTransform.identity
            var remainder = Substring(string)
            while let openParen = remainder.firstIndex(of: "("), let closeParen = remainder.firstIndex(of: ")"), openParen < closeParen {
                let name = remainder[remainder.startIndex..<openParen].trimmingCharacters(in: .whitespaces)
                let argsString = remainder[remainder.index(after: openParen)..<closeParen]
                let args = argsString.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
                // SVG-Transform-Listen wirken wie verschachtelte Gruppen: das RECHTESTE Funktionsargument
                // wirkt auf einen Punkt zuerst, das linkeste zuletzt (`translate(10,20) scale(2)` skaliert
                // zuerst, verschiebt danach) — deshalb wird jede neu geparste Funktion VOR die bisher
                // akkumulierte Transformation gesetzt (`newT.concatenating(transform)`), nicht dahinter.
                switch name {
                case "translate":
                    let tx = args.first ?? 0
                    let ty = args.count > 1 ? args[1] : 0
                    transform = CGAffineTransform(translationX: tx, y: ty).concatenating(transform)
                case "scale":
                    let sx = args.first ?? 1
                    let sy = args.count > 1 ? args[1] : sx
                    transform = CGAffineTransform(scaleX: sx, y: sy).concatenating(transform)
                case "matrix":
                    if args.count == 6, args[1] == 0, args[2] == 0 {
                        transform = CGAffineTransform(a: args[0], b: 0, c: 0, d: args[3], tx: args[4], ty: args[5]).concatenating(transform)
                    }
                // `rotate`/`skewX`/`skewY`/ein `matrix()` mit Rotations-/Scherungsanteil: bewusst
                // ignoriert (Identität) statt eine vollständige Dekomposition zu versuchen.
                default:
                    break
                }
                remainder = remainder[remainder.index(after: closeParen)...]
            }
            return transform
        }

        /// `points="x1,y1 x2,y2 …"` (Komma und/oder Whitespace getrennt, beides kommt in freier
        /// Wildbahn vor) → Punktliste in SVG-user-units (noch ohne Transform/Einheiten-Umrechnung).
        private static func parsePointsList(_ string: String) -> [CGPoint] {
            let numbers = string.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }).compactMap { Double($0) }
            var points: [CGPoint] = []
            var index = 0
            while index + 1 < numbers.count {
                points.append(CGPoint(x: numbers[index], y: numbers[index + 1]))
                index += 2
            }
            return points
        }

        /// Issue #6: Füllfarbe auch aus einem CSS-`style="fill:#…"`-Attribut lesen, nicht nur aus
        /// dem Präsentationsattribut `fill="…"` — Illustrator/Inkscape exportieren beides, je nach
        /// Einstellung. `style` hat Vorrang (SVG-Kaskadierungsregel: Inline-Style schlägt Präsentations-
        /// attribut). Benannte CSS-Farben (z.B. "red") werden bewusst nicht aufgelöst — nur Hex-Werte.
        private static func resolvedFillHex(_ attrs: [String: String]) -> String? {
            if let style = attrs["style"] {
                for rule in style.split(separator: ";") {
                    let parts = rule.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2, parts[0] == "fill", parts[1].hasPrefix("#") {
                        return parts[1]
                    }
                }
            }
            if let fill = attrs["fill"], fill.hasPrefix("#") {
                return fill
            }
            return nil
        }

        /// Erkennt `fill:none`/`fill="none"` (Style hat wieder Vorrang) — häufig bei reinen
        /// Strichzeichnungen/Icons. Nur relevant für fremde SVGs (kein `data-ss-has-fill`), unser
        /// eigenes Schema persistiert `hasFill` bereits explizit.
        private static func isFillExplicitlyNone(_ attrs: [String: String]) -> Bool {
            if let style = attrs["style"] {
                for rule in style.split(separator: ";") {
                    let parts = rule.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2, parts[0] == "fill" {
                        return parts[1] == "none"
                    }
                }
            }
            return attrs["fill"] == "none"
        }
    }
}

private func fmt(_ value: Double) -> String {
    String(format: "%.4f", value)
}

private func xmlEscapeAttribute(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func xmlEscapeText(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
