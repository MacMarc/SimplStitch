//
//  EditablePath.swift
//  SimplStitch
//
//  Issue #19 (Punktgenaues Editieren): In-Memory-Modell für punktgenaues
//  Editieren von `.path`/`.line`-Objekten. `DesignObject.pathData` (SVG-
//  Pfadstring) bleibt weiterhin die persistierte Quelle der Wahrheit
//  (content.svg-Roundtrip unverändert, `SVGDesignSerializer` braucht dafür
//  KEINE Änderung — sie schreibt/liest `d` bereits verlustfrei durch, auch
//  mit `C`/`Q`) — `EditablePath` ist nur ein Parse/Editier/Serialisier-
//  Zwischenschritt, keine SwiftData-Persistenz.
//
//  Opus-Konsultation: nur `M`/`L`/`C`/`Q`/`Z`-Kommandos werden unterstützt
//  (absolute Koordinaten, kein SVG-Kommando-Repeat über Kommas hinweg für
//  relative Varianten) — dieselbe bewusste Einschränkung wie der bisherige
//  M/L-only-Parser (`DesignObjectPath.linePath`, "kein vollständiger SVG-
//  Pfad-Parser"), jetzt nur um `C`/`Q` erweitert. Ein decodiertes `Q`
//  (quadratische Kurve) wird beim Parsen EXAKT in eine kubische Bézier
//  überführt (`SVGPathWriter.cubicControlPoints`), damit intern nur ein
//  Kurventyp gehandhabt werden muss (kubisch) — verlustfrei, keine visuelle
//  Abweichung.
//

import CoreGraphics
import SwiftUI

/// Ein Ankerpunkt samt optionaler Bézier-Kontrollpunkte (absolute Design-Koordinaten, mm).
/// `controlOut` ist der Kontrollpunkt der AUSGEHENDEN Kurve zum nächsten Anker, `controlIn` der
/// der EINGEHENDEN Kurve vom vorherigen Anker — beide `nil`, wenn dieser Anker nur über gerade
/// Liniensegmente verbunden ist.
struct PathAnchor: Equatable {
    var point: CGPoint
    var controlIn: CGPoint?
    var controlOut: CGPoint?
}

struct EditablePath: Equatable {
    var anchors: [PathAnchor]
    var isClosed: Bool

    init(anchors: [PathAnchor] = [], isClosed: Bool = false) {
        self.anchors = anchors
        self.isClosed = isClosed
    }

    /// Parst einen SVG-`d`-String (`M`/`L`/`C`/`Q`/`Z`, absolute Koordinaten) in Anker-Punkte.
    /// Leerer String -> leerer Pfad (dieselbe Konvention wie `DesignObjectPath.linePath("")`).
    init(pathData: String) {
        var anchors: [PathAnchor] = []
        var isClosed = false
        var currentCommand: Character?
        var pendingPoints: [CGPoint] = []
        var currentPoint = CGPoint.zero

        func requiredPointCount(for command: Character) -> Int? {
            switch command {
            case "M", "L": return 1
            case "Q": return 2
            case "C": return 3
            default: return nil
            }
        }

        func flushIfComplete() {
            guard let command = currentCommand, let required = requiredPointCount(for: command),
                  pendingPoints.count == required else { return }
            switch command {
            case "M", "L":
                let p = pendingPoints[0]
                anchors.append(PathAnchor(point: p, controlIn: nil, controlOut: nil))
                currentPoint = p
            case "Q":
                let quadControl = pendingPoints[0]
                let p = pendingPoints[1]
                let (c1, c2) = SVGPathWriter.cubicControlPoints(start: currentPoint, quadControl: quadControl, end: p)
                if !anchors.isEmpty { anchors[anchors.count - 1].controlOut = c1 }
                anchors.append(PathAnchor(point: p, controlIn: c2, controlOut: nil))
                currentPoint = p
            case "C":
                let c1 = pendingPoints[0]
                let c2 = pendingPoints[1]
                let p = pendingPoints[2]
                if !anchors.isEmpty { anchors[anchors.count - 1].controlOut = c1 }
                anchors.append(PathAnchor(point: p, controlIn: c2, controlOut: nil))
                currentPoint = p
            default:
                break
            }
            pendingPoints.removeAll()
        }

        func parsePoint(_ string: some StringProtocol) -> CGPoint? {
            let parts = string.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
            return CGPoint(x: x, y: y)
        }

        for rawToken in pathData.split(separator: " ") {
            if rawToken == "Z" || rawToken == "z" {
                isClosed = true
                currentCommand = nil
                pendingPoints.removeAll()
                continue
            }
            if let first = rawToken.first, "MLCQ".contains(first) {
                currentCommand = first
                pendingPoints.removeAll()
                let remainder = rawToken.dropFirst()
                if !remainder.isEmpty, let point = parsePoint(remainder) {
                    pendingPoints.append(point)
                }
            } else if let point = parsePoint(rawToken) {
                pendingPoints.append(point)
            }
            flushIfComplete()
        }

        self.anchors = anchors
        self.isClosed = isClosed
    }

    /// Liefert für ein Anker-Paar entweder eine Gerade (beide angrenzenden Kontrollpunkte `nil`)
    /// oder eine kubische Kurve — fehlt nur EIN Kontrollpunkt, defaultet er auf den jeweiligen
    /// Endpunkt selbst (Standardkonvention für "einseitig" gesetzte Kontrollpunkte).
    private func segment(from previous: PathAnchor, to current: PathAnchor) -> SVGPathSegment {
        let c1 = previous.controlOut
        let c2 = current.controlIn
        guard c1 != nil || c2 != nil else { return .lineTo(current.point) }
        return .curveTo(current.point, control1: c1 ?? previous.point, control2: c2 ?? current.point)
    }

    /// Serialisiert zurück in einen SVG-`d`-String über den gemeinsamen `SVGPathWriter`
    /// (Text-embroiderable + Issue #19 teilen sich diesen Baustein, siehe SVGPathWriter.swift).
    func svgPathData() -> String {
        guard let first = anchors.first else { return "" }
        var segments: [SVGPathSegment] = [.moveTo(first.point)]
        var previous = first
        for anchor in anchors.dropFirst() {
            segments.append(segment(from: previous, to: anchor))
            previous = anchor
        }
        if isClosed { segments.append(.closePath) }
        return SVGPathWriter.string(from: segments)
    }

    /// SwiftUI-`Path` fürs Canvas-Rendering — ersetzt `DesignObjectPath.linePath`s bisherigen
    /// reinen M/L-Parser, jetzt mit `addCurve` für jeden kurvigen Abschnitt.
    var path: Path {
        var path = Path()
        guard let first = anchors.first else { return path }
        path.move(to: first.point)
        var previous = first
        for anchor in anchors.dropFirst() {
            switch segment(from: previous, to: anchor) {
            case .lineTo(let p):
                path.addLine(to: p)
            case .curveTo(let p, let c1, let c2):
                path.addCurve(to: p, control1: c1, control2: c2)
            case .moveTo, .closePath:
                break // segment(from:to:) erzeugt nur .lineTo/.curveTo
            }
            previous = anchor
        }
        if isClosed { path.closeSubpath() }
        return path
    }

    /// Umschliessendes Rechteck über ALLE Punkte (Anker + Kontrollpunkte) — eine kubische Bézier-
    /// Kurve liegt immer innerhalb der konvexen Hülle ihrer 4 Kontrollpunkte, das Ergebnis ist
    /// also eine korrekte (ggf. leicht konservative) obere Schranke, ohne die Kurve selbst
    /// abtasten zu müssen. Genutzt von `CanvasStore`, um `position`/`width`/`height` nach einem
    /// Punkt-Edit neu zu berechnen (Issue #19, Schritt B2).
    var boundingBox: CGRect {
        var points: [CGPoint] = []
        for anchor in anchors {
            points.append(anchor.point)
            if let c = anchor.controlIn { points.append(c) }
            if let c = anchor.controlOut { points.append(c) }
        }
        guard !points.isEmpty else { return .zero }
        let minX = points.map(\.x).min()!
        let maxX = points.map(\.x).max()!
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
