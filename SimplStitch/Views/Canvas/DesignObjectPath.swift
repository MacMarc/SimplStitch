//
//  DesignObjectPath.swift
//  SimplStitch
//
//  Wandelt ein DesignObject in einen SwiftUI Path in Design-Koordinaten (mm,
//  Ursprung oben-links) um — fürs Canvas-Rendering. Bewusst getrennt von
//  SVGDesignSerializer (Services-Schicht, Persistenz-Format) statt dort
//  wiederverwendet: reines View-Rendering gehört nicht in einen Service.
//
//  Die Stern-Geometrie ist dieselbe Formel wie in
//  SVGDesignSerializer.starPathData (dort als SVG-Pfadstring fürs
//  content.svg) — bei Änderungen beide Stellen synchron halten.
//

import SwiftUI

extension DesignObject {
    /// Bringt den unrotierten/unverzerrten `designSpacePath()` auf die sichtbare Ausrichtung: erst
    /// Scherung (`skewXDegrees`/`skewYDegrees`, Issue #9), dann Rotation (`rotationDegrees`), beides
    /// um die Objektmitte — dieselbe Konvention wie `CanvasStore`s Hit-Testing/Handle-Platzierung
    /// (dort bewusst weiterhin nur rotationsbasiert zurückgerechnet, siehe CanvasStore-Kommentar zu
    /// `applySkew`/`localDesignVector`). Hiess bis Issue #9 `rotationTransform` — umbenannt, weil sie
    /// jetzt mehr als nur Rotation ausdrückt.
    var visualTransform: CGAffineTransform {
        guard rotationDegrees != 0 || skewXDegrees != 0 || skewYDegrees != 0 else { return .identity }
        let center = CGPoint(x: positionX + width / 2, y: positionY + height / 2)
        var transform = CGAffineTransform(translationX: -center.x, y: -center.y)
        if skewXDegrees != 0 || skewYDegrees != 0 {
            let tanX = tan(skewXDegrees * .pi / 180)
            let tanY = tan(skewYDegrees * .pi / 180)
            transform = transform.concatenating(CGAffineTransform(a: 1, b: tanY, c: tanX, d: 1, tx: 0, ty: 0))
        }
        if rotationDegrees != 0 {
            transform = transform.concatenating(CGAffineTransform(rotationAngle: rotationDegrees * .pi / 180))
        }
        return transform.concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }

    func designSpacePath() -> Path {
        switch kind {
        case .rectangle:
            return Path(
                roundedRect: CGRect(x: positionX, y: positionY, width: width, height: height),
                cornerRadius: max(cornerRadius, 0)
            )
        case .circle:
            return Path(ellipseIn: CGRect(x: positionX, y: positionY, width: width, height: height))
        case .star:
            return Self.starPath(x: positionX, y: positionY, width: width, height: height, pointCount: starPointCount ?? 5)
        case .path:
            return Self.linePath(fromPathData: pathData ?? "")
        case .text:
            // Text hat keinen Füll-/Strichpfad — CanvasView zeichnet Glyphen direkt über
            // GraphicsContext.draw(Text:in:), Selektionsrahmen/Handles nutzen die Bounding-Box.
            return Path()
        }
    }

    static func starPath(x: Double, y: Double, width: Double, height: Double, pointCount: Int) -> Path {
        let cx = x + width / 2
        let cy = y + height / 2
        let outerRadius = min(width, height) / 2
        let innerRadius = outerRadius * 0.5
        let n = max(pointCount, 3)

        var path = Path()
        for i in 0..<(n * 2) {
            let angle = (Double(i) * .pi / Double(n)) - (.pi / 2)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let point = CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    /// Parst die simplen "Mx,y Lx,y …"-Pfadstrings, die CanvasStore für Freihand-Pfade erzeugt
    /// (siehe CanvasStore.pathData) — kein vollständiger SVG-Pfad-Parser.
    static func linePath(fromPathData d: String) -> Path {
        var path = Path()
        var isFirst = true
        for token in d.split(separator: " ") {
            if token == "Z" {
                path.closeSubpath()
                continue
            }
            let coordinatePart = token.drop { $0 == "M" || $0 == "L" }
            let parts = coordinatePart.split(separator: ",")
            guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { continue }
            let point = CGPoint(x: x, y: y)
            if isFirst {
                path.move(to: point)
                isFirst = false
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
