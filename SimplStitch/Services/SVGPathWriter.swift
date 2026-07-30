//
//  SVGPathWriter.swift
//  SimplStitch
//
//  Gemeinsamer Baustein für Text-zu-Stich (Issue: Text embroiderable) und
//  Issue #19 (Punktgenaues Editieren): ein Bézier-fähiger SVG-Pfad-Schreiber
//  (Segmentliste -> "d"-String, inkl. `C`). Opus-Konsultation ergab: das ist
//  der EINZIGE tatsächlich geteilte Baustein zwischen beiden Features — der
//  Rest (Glyphen-Extraktion, Anker-Editing-Modell) ist featurespezifisch.
//
//  `CGPath.svgPathSegments()`/`svgPathData()` sind der Adapter für Feature A
//  (Glyphen-Pfade, siehe GlyphOutlineService) — reine CGPath-Elemente, keine
//  Design-Objekt-Kenntnis. `EditablePath.svgPathData()` (DesignObjectPath.swift,
//  Issue #19) nutzt denselben `SVGPathWriter.string(from:)` für die
//  Anker-Punkt-Serialisierung.
//

import Foundation
import CoreGraphics

enum SVGPathSegment {
    case moveTo(CGPoint)
    case lineTo(CGPoint)
    case curveTo(CGPoint, control1: CGPoint, control2: CGPoint)
    case closePath
}

enum SVGPathWriter {
    static func string(from segments: [SVGPathSegment]) -> String {
        var tokens: [String] = []
        for segment in segments {
            switch segment {
            case .moveTo(let p):
                tokens.append("M\(fmt(p.x)),\(fmt(p.y))")
            case .lineTo(let p):
                tokens.append("L\(fmt(p.x)),\(fmt(p.y))")
            case .curveTo(let p, let c1, let c2):
                tokens.append("C\(fmt(c1.x)),\(fmt(c1.y)) \(fmt(c2.x)),\(fmt(c2.y)) \(fmt(p.x)),\(fmt(p.y))")
            case .closePath:
                tokens.append("Z")
            }
        }
        return tokens.joined(separator: " ")
    }

    /// Exakte kubische Bézier-Entsprechung einer quadratischen Kurve (P0 Start, Qc Kontrollpunkt,
    /// P2 Ende) — `C1 = P0 + 2/3(Qc-P0)`, `C2 = P2 + 2/3(Qc-P2)`. Genutzt sowohl beim `CGPath`-Import
    /// (`addQuadCurveToPoint`) als auch beim Decodieren von SVG-`Q`-Kommandos (Issue #19), damit
    /// intern nur ein Kurventyp (kubisch) gehandhabt werden muss.
    static func cubicControlPoints(start: CGPoint, quadControl: CGPoint, end: CGPoint) -> (CGPoint, CGPoint) {
        let c1 = CGPoint(x: start.x + 2.0 / 3.0 * (quadControl.x - start.x), y: start.y + 2.0 / 3.0 * (quadControl.y - start.y))
        let c2 = CGPoint(x: end.x + 2.0 / 3.0 * (quadControl.x - end.x), y: end.y + 2.0 / 3.0 * (quadControl.y - end.y))
        return (c1, c2)
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.4f", Double(value))
    }
}

extension CGPath {
    /// Elemente einer bereits in Design-Raum transformierten `CGPath` als SVG-Pfad-Segmente —
    /// `addQuadCurveToPoint` wird über `SVGPathWriter.cubicControlPoints` exakt in eine kubische
    /// Bézier überführt, da unser Schreiber nur `C` emittiert (kein `Q`).
    func svgPathSegments() -> [SVGPathSegment] {
        var segments: [SVGPathSegment] = []
        var current: CGPoint = .zero
        var subpathStart: CGPoint = .zero

        applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                let p = element.points[0]
                segments.append(.moveTo(p))
                current = p
                subpathStart = p
            case .addLineToPoint:
                let p = element.points[0]
                segments.append(.lineTo(p))
                current = p
            case .addQuadCurveToPoint:
                let quadControl = element.points[0]
                let p = element.points[1]
                let (c1, c2) = SVGPathWriter.cubicControlPoints(start: current, quadControl: quadControl, end: p)
                segments.append(.curveTo(p, control1: c1, control2: c2))
                current = p
            case .addCurveToPoint:
                let c1 = element.points[0]
                let c2 = element.points[1]
                let p = element.points[2]
                segments.append(.curveTo(p, control1: c1, control2: c2))
                current = p
            case .closeSubpath:
                segments.append(.closePath)
                current = subpathStart
            @unknown default:
                break
            }
        }
        return segments
    }

    func svgPathData() -> String {
        SVGPathWriter.string(from: svgPathSegments())
    }
}
