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
//  Vereinfachung: Rotation/Skew werden NICHT in eine SVG-`transform`-Matrix
//  gebacken, sondern roh als data-ss-Attribute mitgeführt. Für pixelgenaues
//  Rendering (Canvas-Engine, Phase 5) und für den echten InkStitch-Aufruf
//  (Phase 6) muss das ggf. in eine korrekte transform-Komposition überführt
//  werden — hier zählt nur verlustfreier Roundtrip der Werte.
//

import Foundation
import CoreGraphics

protocol SVGDesignSerializing {
    func encode(objects: [DesignObject], canvasSize: CGSize, backgroundImageFileName: String?, defaultThreadPaletteID: UUID?) -> String
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
}

struct SVGDecodedDesign {
    var canvasSize: CGSize
    var objects: [DesignObject]
    var backgroundImageFileName: String?
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

    // MARK: Encode

    func encode(objects: [DesignObject], canvasSize: CGSize, backgroundImageFileName: String?, defaultThreadPaletteID: UUID? = nil) -> String {
        let defaultPaletteAttr = defaultThreadPaletteID.map { " data-ss-default-palette=\"\($0.uuidString)\"" } ?? ""
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkstitch="\(Self.inkstitchNamespace)" width="\(fmt(canvasSize.width))mm" height="\(fmt(canvasSize.height))mm" viewBox="0 0 \(fmt(canvasSize.width)) \(fmt(canvasSize.height))" data-ss-version="1"\(defaultPaletteAttr)>\n
        """

        if let backgroundImageFileName {
            svg += "  <image href=\"assets/\(xmlEscapeAttribute(backgroundImageFileName))\" x=\"0\" y=\"0\" width=\"\(fmt(canvasSize.width))\" height=\"\(fmt(canvasSize.height))\" data-ss-role=\"background\" />\n"
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
            defaultThreadPaletteID: delegate.defaultThreadPaletteID
        )
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var canvasSize: CGSize = .zero
        var objects: [DesignObject] = []
        var backgroundImageFileName: String?
        var defaultThreadPaletteID: UUID?

        private var currentTextObject: DesignObject?
        private var currentTextBuffer = ""

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "svg":
                canvasSize = CGSize(
                    width: Self.parseDouble(attributeDict["width"]) ?? 0,
                    height: Self.parseDouble(attributeDict["height"]) ?? 0
                )
                defaultThreadPaletteID = attributeDict["data-ss-default-palette"].flatMap { UUID(uuidString: $0) }
            case "image":
                if attributeDict["data-ss-role"] == "background" {
                    let href = attributeDict["href"] ?? ""
                    backgroundImageFileName = href.replacingOccurrences(of: "assets/", with: "")
                }
            case "rect":
                objects.append(Self.makeRectangle(attributeDict))
            case "ellipse":
                objects.append(Self.makeCircle(attributeDict))
            case "path":
                objects.append(Self.makePathElement(attributeDict))
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
            guard elementName == "text", let object = currentTextObject else { return }
            object.text = currentTextBuffer
            objects.append(object)
            currentTextObject = nil
            currentTextBuffer = ""
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
            object.fillColorHex = attrs["fill"] ?? object.fillColorHex
            if let groupIDString = attrs["data-ss-group"], let groupID = UUID(uuidString: groupIDString) {
                object.groupID = groupID
            }
            object.hasFill = (attrs["data-ss-has-fill"] ?? "true") == "true"
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

        private static func makeRectangle(_ attrs: [String: String]) -> DesignObject {
            let x = parseDouble(attrs["x"]) ?? 0
            let y = parseDouble(attrs["y"]) ?? 0
            let width = parseDouble(attrs["width"]) ?? 0
            let height = parseDouble(attrs["height"]) ?? 0
            let object = DesignObject(name: "", kind: .rectangle, positionX: x, positionY: y, width: width, height: height)
            object.cornerRadius = parseDouble(attrs["rx"]) ?? 0
            applyCommonAttributes(attrs, to: object)
            return object
        }

        private static func makeCircle(_ attrs: [String: String]) -> DesignObject {
            let cx = parseDouble(attrs["cx"]) ?? 0
            let cy = parseDouble(attrs["cy"]) ?? 0
            let rx = parseDouble(attrs["rx"]) ?? 0
            let ry = parseDouble(attrs["ry"]) ?? 0
            let object = DesignObject(name: "", kind: .circle, positionX: cx - rx, positionY: cy - ry, width: rx * 2, height: ry * 2)
            applyCommonAttributes(attrs, to: object)
            return object
        }

        private static func makePathElement(_ attrs: [String: String]) -> DesignObject {
            let x = parseDouble(attrs["data-ss-x"]) ?? 0
            let y = parseDouble(attrs["data-ss-y"]) ?? 0
            let width = parseDouble(attrs["data-ss-w"]) ?? 0
            let height = parseDouble(attrs["data-ss-h"]) ?? 0
            let isStar = attrs["data-ss-star-points"] != nil
            let isLine = attrs["data-ss-line"] == "true"
            let kind: DesignObjectKind = isStar ? .star : (isLine ? .line : .path)
            let object = DesignObject(name: "", kind: kind, positionX: x, positionY: y, width: width, height: height)
            if isStar {
                object.starPointCount = Int(attrs["data-ss-star-points"] ?? "") ?? 5
            } else {
                object.pathData = attrs["d"]
            }
            applyCommonAttributes(attrs, to: object)
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
            applyCommonAttributes(attrs, to: object)
            return object
        }

        private static func parseDouble(_ string: String?) -> Double? {
            guard let string else { return nil }
            let numericPart = string.prefix { $0.isNumber || $0 == "." || $0 == "-" }
            return Double(numericPart)
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
