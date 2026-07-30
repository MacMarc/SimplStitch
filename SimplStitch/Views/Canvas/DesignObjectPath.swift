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
    // `visualTransform` (Scherung + Rotation um die Objektmitte) lebt seit Issue #30 im Model
    // (`DesignObject.swift`), nicht mehr hier — `SVGDesignSerializer` (Services-Schicht, kein
    // SwiftUI) braucht dieselbe Transformation für die Stichgenerierung, siehe dortiger Kommentar.

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
        case .path, .line:
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

    /// Issue #19: nutzt jetzt `EditablePath` (unterstützt `M`/`L`/`C`/`Q`/`Z`, vorher nur `M`/`L`)
    /// statt eines eigenen, noch einfacheren Parsers — ein editierter/importierter Pfad mit echten
    /// Kurvensegmenten wird dadurch auch tatsächlich gekrümmt gerendert statt fälschlich mit
    /// geraden Linien zwischen den Endpunkten.
    static func linePath(fromPathData d: String) -> Path {
        EditablePath(pathData: d).path
    }
}
