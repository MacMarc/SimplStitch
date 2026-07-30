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
//  Issue #28 (RC2, generischer SVG-Import): der Parser unterstützte bis dahin
//  nur `M`/`L`/`C`/`Q`/`Z`, ausschliesslich absolute Koordinaten, Zahlen durch
//  Leerzeichen getrennt — genug für unser eigenes `SVGPathWriter`-Ausgabeformat,
//  aber nicht für reale SVG-Exporte (Illustrator/Inkscape/Figma), die u.a.
//  `H`/`V`/`S`/`T`/`A`, relative Kommandos (Kleinbuchstaben), implizite
//  Kommando-Wiederholung (`L10,20 30,40` = zwei Lineto) und an Kommandos
//  geklebte Zahlen (`M10,20C30,40 …`) verwenden. Jetzt ein echter Tokenizer
//  (`tokenize(_:)`, Kommando-Buchstaben und Zahlen werden unabhängig vom
//  Trennzeichen erkannt) plus vollständige Kommando-Unterstützung:
//  - `H`/`V`: eindimensionale Lineto-Varianten.
//  - `S`/`T`: "glatte" Kurzformen, deren erster Kontrollpunkt an der aktuellen
//    Position gespiegelt wird (nur falls das vorherige Kommando aus derselben
//    Kurvenfamilie stammt, sonst Kontrollpunkt = aktuelle Position, exakt nach
//    SVG-Spec).
//  - `A` (elliptischer Bogen): vollständige Endpunkt-zu-Mittelpunkt-
//    Parametrisierung (SVG-Spec Anhang F.6), in höchstens 90°-Segmente
//    aufgeteilt und je über die Standard-"Kappa"-Näherung in kubische
//    Bézier-Kurven überführt — keine neue Geometrie-Primitive, `EditablePath`
//    kennt weiterhin nur kubische Kurven.
//  Ein decodiertes `Q`/`T` (quadratische Kurve) wird beim Parsen weiterhin
//  EXAKT in eine kubische Bézier überführt (`SVGPathWriter.cubicControlPoints`),
//  damit intern nur ein Kurventyp gehandhabt werden muss — verlustfrei für Q,
//  eine kontrollierte Näherung für A (keine geschlossene kubische Entsprechung
//  einer Ellipse, aber praktisch nicht von der echten Kurve unterscheidbar).
//  Issue #30 (Reimport-Sprünge): mehrere Teilpfade (mehrfaches `M`) in einem
//  einzigen `d`-String werden jetzt UNTERSTÜTZT. Reimportierte Stickdateien
//  kodieren JUMP-Stiche (Nadel bewegt sich ohne Faden) bewusst als eigenes `M`
//  ohne verbindende Linie (siehe `FileImportService.makeObject`). Bislang hängte
//  der Parser jedes weitere `M` wie ein `L` an denselben `anchors`-Array an — der
//  jump-unterbrochene Pfad verschmolz dadurch beim Rendern (`path`), beim
//  Verschieben/Skalieren (`CanvasStore.transformedEditablePath` -> `svgPathData()`)
//  und beim generischen SVG-Import (`SVGDesignSerializer.makePathElement`) zu EINEM
//  durchgezogenen Linienzug — die sichtbare Ursache von "Sprünge werden gestickt
//  dargestellt". Jetzt markiert jeder Anker, der einen neuen Teilpfad beginnt,
//  `startsSubpath == true`; `path`/`svgPathData()` erzeugen dort einen `move`
//  statt einer verbindenden Linie/Kurve. Die flache `anchors`-Struktur bleibt
//  bewusst erhalten (statt eines `subpaths: [[PathAnchor]]`-Umbaus) — die gesamte
//  Punkt-Editier-Infrastruktur (CanvasStore-Anker-Indizes, Handles) arbeitet
//  unverändert index-basiert weiter.
//  Bewusst weiterhin NICHT unterstützt: pro-Teilpfad-Schliessung (`z` mitten im
//  Pfad) — `isClosed` bleibt ein einziges Flag, das nur den LETZTEN Teilpfad
//  schliesst. Für den Kernfall (reimportierte Stiche, nie geschlossen) irrelevant.
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
    /// Issue #30: `true`, wenn dieser Anker einen NEUEN Teilpfad beginnt (ein `M` nach dem ersten
    /// Anker, z.B. ein JUMP-Stich beim Reimport) — dann wird er beim Rendern/Serialisieren über
    /// einen `move` erreicht, nicht über eine verbindende Linie/Kurve vom vorherigen Anker. Der
    /// allererste Anker eines Pfades ist ohnehin immer ein `move` und bleibt daher `false`.
    var startsSubpath: Bool = false
}

struct EditablePath: Equatable {
    var anchors: [PathAnchor]
    var isClosed: Bool

    init(anchors: [PathAnchor] = [], isClosed: Bool = false) {
        self.anchors = anchors
        self.isClosed = isClosed
    }

    private enum PathToken {
        case command(Character)
        case number(Double)
    }

    private static let commandLetters = Set("MmLlHhVvCcSsQqTtAaZz")

    /// Echter SVG-Pfad-Tokenizer (Issue #28, RC2): erkennt Kommando-Buchstaben unabhängig vom
    /// Trennzeichen und liest Zahlen mit einem eigenen Scanner statt eines blossen `split(" ")` —
    /// versteht dadurch an Kommandos geklebte Zahlen (`M10,20`), aneinandergereihte Dezimalzahlen
    /// ohne Trennzeichen (`.5.5` -> `.5`, `.5`) sowie ein Minuszeichen ohne vorheriges Trennzeichen
    /// als Start einer neuen Zahl (`10-20` -> `10`, `-20`). Kommas und Leerraum sind gleichwertige
    /// Trennzeichen und werden übersprungen.
    private static func tokenize(_ d: String) -> [PathToken] {
        var tokens: [PathToken] = []
        let chars = Array(d)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace || c == "," {
                i += 1
                continue
            }
            if commandLetters.contains(c) {
                tokens.append(.command(c))
                i += 1
                continue
            }
            var j = i
            if chars[j] == "+" || chars[j] == "-" { j += 1 }
            while j < chars.count, chars[j].isNumber { j += 1 }
            if j < chars.count, chars[j] == "." {
                j += 1
                while j < chars.count, chars[j].isNumber { j += 1 }
            }
            if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                var k = j + 1
                if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                if k < chars.count, chars[k].isNumber {
                    while k < chars.count, chars[k].isNumber { k += 1 }
                    j = k
                }
            }
            guard j > i, let value = Double(String(chars[i..<j])) else {
                i += 1 // unerkanntes Zeichen: überspringen statt das gesamte Parsing abzubrechen
                continue
            }
            tokens.append(.number(value))
            i = j
        }
        return tokens
    }

    /// Parst einen SVG-`d`-String in Anker-Punkte — unterstützt `M`/`L`/`H`/`V`/`C`/`S`/`Q`/`T`/
    /// `A`/`Z`, jeweils absolut (Grossbuchstabe) oder relativ (Kleinbuchstabe), inkl. impliziter
    /// Kommando-Wiederholung (SVG-Spec: auf `M` folgende Koordinatenpaare ohne neues Kommando sind
    /// implizite `L`, bei allen anderen Kommandos wiederholt sich dasselbe Kommando). Leerer String
    /// -> leerer Pfad (dieselbe Konvention wie zuvor).
    init(pathData: String) {
        let tokens = Self.tokenize(pathData)
        var anchors: [PathAnchor] = []
        var isClosed = false
        var i = 0
        var currentPoint = CGPoint.zero
        // Für `S`/`T`: der zu spiegelnde Kontrollpunkt der vorherigen Kurve (absolut) plus welches
        // Kommando ihn erzeugt hat — nur gültig, wenn das vorherige Kommando aus derselben
        // Kurvenfamilie stammt (C/S für S, Q/T für T), sonst spiegelt sich die aktuelle Position
        // selbst (SVG-Spec).
        var previousCommand: Character?
        var previousControlForReflection: CGPoint?

        func nextNumber() -> Double? {
            guard i < tokens.count, case .number(let value) = tokens[i] else { return nil }
            i += 1
            return value
        }

        func appendLineAnchor(_ p: CGPoint) {
            anchors.append(PathAnchor(point: p))
            currentPoint = p
        }

        /// Issue #30: ein `M`/`m` — startet einen neuen Teilpfad. Der erste Anker eines Pfades ist
        /// implizit ebenfalls ein Move, wird aber NICHT markiert (er beginnt keinen "weiteren"
        /// Teilpfad, sondern den Pfad selbst); erst ein `M` nach bereits vorhandenen Ankern erzeugt
        /// eine echte Sprung-Grenze.
        func appendMoveAnchor(_ p: CGPoint) {
            var anchor = PathAnchor(point: p)
            if !anchors.isEmpty { anchor.startsSubpath = true }
            anchors.append(anchor)
            currentPoint = p
        }

        func appendCubicAnchor(control1: CGPoint, control2: CGPoint, end: CGPoint) {
            if !anchors.isEmpty { anchors[anchors.count - 1].controlOut = control1 }
            anchors.append(PathAnchor(point: end, controlIn: control2))
            currentPoint = end
        }

        /// Führt genau eine Instanz von `command` mit den nächsten Zahlen-Tokens aus. Liefert
        /// `false`, wenn nicht genug Zahlen vorhanden waren (unvollständiger/kaputter `d`-String) —
        /// bricht dann das gesamte Parsing kontrolliert ab, statt in einer Endlosschleife zu hängen.
        @discardableResult
        func execute(_ command: Character) -> Bool {
            let isRelative = command.isLowercase
            func resolved(_ p: CGPoint) -> CGPoint {
                isRelative ? CGPoint(x: currentPoint.x + p.x, y: currentPoint.y + p.y) : p
            }

            switch Character(command.uppercased()) {
            case "M":
                guard let x = nextNumber(), let y = nextNumber() else { return false }
                appendMoveAnchor(resolved(CGPoint(x: x, y: y)))
            case "L":
                guard let x = nextNumber(), let y = nextNumber() else { return false }
                appendLineAnchor(resolved(CGPoint(x: x, y: y)))
            case "H":
                guard let x = nextNumber() else { return false }
                appendLineAnchor(CGPoint(x: isRelative ? currentPoint.x + x : x, y: currentPoint.y))
            case "V":
                guard let y = nextNumber() else { return false }
                appendLineAnchor(CGPoint(x: currentPoint.x, y: isRelative ? currentPoint.y + y : y))
            case "C":
                guard let x1 = nextNumber(), let y1 = nextNumber(),
                      let x2 = nextNumber(), let y2 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { return false }
                let c1 = resolved(CGPoint(x: x1, y: y1))
                let c2 = resolved(CGPoint(x: x2, y: y2))
                appendCubicAnchor(control1: c1, control2: c2, end: resolved(CGPoint(x: x, y: y)))
                previousControlForReflection = c2
            case "S":
                guard let x2 = nextNumber(), let y2 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { return false }
                let c2 = resolved(CGPoint(x: x2, y: y2))
                let c1: CGPoint
                if let previousCommand, "CcSs".contains(previousCommand), let reflect = previousControlForReflection {
                    c1 = CGPoint(x: 2 * currentPoint.x - reflect.x, y: 2 * currentPoint.y - reflect.y)
                } else {
                    c1 = currentPoint
                }
                appendCubicAnchor(control1: c1, control2: c2, end: resolved(CGPoint(x: x, y: y)))
                previousControlForReflection = c2
            case "Q":
                guard let x1 = nextNumber(), let y1 = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { return false }
                let control = resolved(CGPoint(x: x1, y: y1))
                let end = resolved(CGPoint(x: x, y: y))
                let (c1, c2) = SVGPathWriter.cubicControlPoints(start: currentPoint, quadControl: control, end: end)
                appendCubicAnchor(control1: c1, control2: c2, end: end)
                previousControlForReflection = control
            case "T":
                guard let x = nextNumber(), let y = nextNumber() else { return false }
                let control: CGPoint
                if let previousCommand, "QqTt".contains(previousCommand), let reflect = previousControlForReflection {
                    control = CGPoint(x: 2 * currentPoint.x - reflect.x, y: 2 * currentPoint.y - reflect.y)
                } else {
                    control = currentPoint
                }
                let end = resolved(CGPoint(x: x, y: y))
                let (c1, c2) = SVGPathWriter.cubicControlPoints(start: currentPoint, quadControl: control, end: end)
                appendCubicAnchor(control1: c1, control2: c2, end: end)
                previousControlForReflection = control
            case "A":
                guard let rx = nextNumber(), let ry = nextNumber(), let xAxisRotation = nextNumber(),
                      let largeArcFlag = nextNumber(), let sweepFlag = nextNumber(),
                      let x = nextNumber(), let y = nextNumber() else { return false }
                let end = resolved(CGPoint(x: x, y: y))
                let segments = Self.arcToBezierSegments(
                    from: currentPoint, rx: abs(rx), ry: abs(ry), xAxisRotationDegrees: xAxisRotation,
                    largeArc: largeArcFlag != 0, sweep: sweepFlag != 0, to: end
                )
                for segment in segments {
                    appendCubicAnchor(control1: segment.control1, control2: segment.control2, end: segment.end)
                }
                previousControlForReflection = nil
            default:
                return false
            }
            previousCommand = command
            return true
        }

        while i < tokens.count {
            switch tokens[i] {
            case .command(let letter):
                if letter == "Z" || letter == "z" {
                    isClosed = true
                    previousCommand = nil
                    previousControlForReflection = nil
                    i += 1
                    continue
                }
                i += 1
                guard execute(letter) else { i = tokens.count; continue }
            case .number:
                // Implizite Kommando-Wiederholung: kein neues Kommando-Token, das vorherige
                // Kommando läuft mit den nächsten Zahlen weiter — `M` wird dabei zu `L` (SVG-Spec).
                guard let previousCommand else { i = tokens.count; continue }
                let effective: Character = previousCommand == "M" ? "L" : (previousCommand == "m" ? "l" : previousCommand)
                guard execute(effective) else { i = tokens.count; continue }
            }
        }

        self.anchors = anchors
        self.isClosed = isClosed
    }

    /// Elliptischer Bogen (`A`/`a`) -> ein oder mehrere kubische Bézier-Segmente. Vollständige
    /// Endpunkt-zu-Mittelpunkt-Parametrisierung nach SVG-Spec Anhang F.6, danach Aufteilung in
    /// höchstens 90°-Abschnitte, je über die verbreitete "Kappa"-Näherung (`4/3 * tan(Δθ/4)`) für
    /// Einheitskreisbögen approximiert und zurück in den ursprünglichen (rotierten/skalierten) Raum
    /// transformiert. Identische Start-/Endpunkte liefern per Spec keine Kurve; ein Radius von 0
    /// degeneriert zu einer Geraden.
    private static func arcToBezierSegments(
        from start: CGPoint,
        rx: Double,
        ry: Double,
        xAxisRotationDegrees: Double,
        largeArc: Bool,
        sweep: Bool,
        to end: CGPoint
    ) -> [(control1: CGPoint, control2: CGPoint, end: CGPoint)] {
        guard start != end else { return [] }
        guard rx > 0, ry > 0 else { return [(start, end, end)] }
        var rx = rx
        var ry = ry

        let phi = xAxisRotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }

        let rxSq = rx * rx
        let rySq = ry * ry
        let x1pSq = x1p * x1p
        let y1pSq = y1p * y1p
        let sign: Double = largeArc == sweep ? -1 : 1
        let numerator = max(0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq)
        let denominator = rxSq * y1pSq + rySq * x1pSq
        let coef = denominator == 0 ? 0 : sign * (numerator / denominator).squareRoot()
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)

        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let cx = cosPhi * cxp - sinPhi * cyp + midX
        let cy = sinPhi * cxp + cosPhi * cyp + midY

        func vectorAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            guard len > 0 else { return 0 }
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let startVectorX = (x1p - cxp) / rx
        let startVectorY = (y1p - cyp) / ry
        let endVectorX = (-x1p - cxp) / rx
        let endVectorY = (-y1p - cyp) / ry
        let theta1 = vectorAngle(1, 0, startVectorX, startVectorY)
        var deltaTheta = vectorAngle(startVectorX, startVectorY, endVectorX, endVectorY)
        if !sweep, deltaTheta > 0 { deltaTheta -= 2 * .pi }
        if sweep, deltaTheta < 0 { deltaTheta += 2 * .pi }

        let segmentCount = max(1, Int(ceil(abs(deltaTheta) / (.pi / 2))))
        let segmentAngle = deltaTheta / Double(segmentCount)
        let alpha = 4.0 / 3.0 * tan(segmentAngle / 4)

        func pointOnEllipse(_ theta: Double) -> CGPoint {
            let ex = rx * cos(theta)
            let ey = ry * sin(theta)
            return CGPoint(x: cosPhi * ex - sinPhi * ey + cx, y: sinPhi * ex + cosPhi * ey + cy)
        }
        func tangent(_ theta: Double) -> CGPoint {
            let ex = -rx * sin(theta)
            let ey = ry * cos(theta)
            return CGPoint(x: cosPhi * ex - sinPhi * ey, y: sinPhi * ex + cosPhi * ey)
        }

        var results: [(control1: CGPoint, control2: CGPoint, end: CGPoint)] = []
        var theta = theta1
        var segmentStart = start
        for _ in 0..<segmentCount {
            let thetaEnd = theta + segmentAngle
            let segmentEnd = pointOnEllipse(thetaEnd)
            let startTangent = tangent(theta)
            let endTangent = tangent(thetaEnd)
            let c1 = CGPoint(x: segmentStart.x + alpha * startTangent.x, y: segmentStart.y + alpha * startTangent.y)
            let c2 = CGPoint(x: segmentEnd.x - alpha * endTangent.x, y: segmentEnd.y - alpha * endTangent.y)
            results.append((c1, c2, segmentEnd))
            theta = thetaEnd
            segmentStart = segmentEnd
        }
        // Rundungsfehler der trigonometrischen Berechnung sonst minimal sichtbar am Zielpunkt.
        if !results.isEmpty {
            results[results.count - 1].end = end
        }
        return results
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
            // Issue #30: ein Teilpfad-Start wird als eigenes `M` geschrieben (Sprung ohne verbindende
            // Linie), sonst als Linie/Kurve vom vorherigen Anker. So bleibt die Jump-Lücke auch nach
            // dem Roundtrip via CanvasStore.transformedEditablePath (Verschieben/Skalieren) erhalten.
            if anchor.startsSubpath {
                segments.append(.moveTo(anchor.point))
            } else {
                segments.append(segment(from: previous, to: anchor))
            }
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
            // Issue #30: ein Teilpfad-Start wird per `move` erreicht (Sprung ohne gezeichnete Linie) —
            // ohne das würde die Jump-Lücke eines reimportierten Pfades als durchgezogener Strich
            // gerendert ("Sprünge werden gestickt dargestellt").
            if anchor.startsSubpath {
                path.move(to: anchor.point)
                previous = anchor
                continue
            }
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
