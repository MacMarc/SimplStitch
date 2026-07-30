//
//  CanvasHandle.swift
//  SimplStitch
//
//  Die Griffe (Handles) eines selektierten DesignObject: acht Skalier-Griffe
//  (Ecken + Kantenmitten), ein Rotations-Griff und — nur bei Rechtecken —
//  ein Eckenradius-Griff. Siehe CanvasStore für Positionierung und Drag-Logik.
//

import Foundation

enum CanvasHandleKind: Hashable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case rotate
    case cornerRadius
    /// Issue #19 (Punktgenaues Editieren): Ankerpunkt-Griffe für `.path`/`.line` im Punkt-Editier-
    /// Modus (`CanvasStore.pointEditingObjectID`) — der Int ist der Index in `EditablePath.anchors`.
    /// Eigenständig von den Skalier-/Rotations-/Eckenradius-Griffen oben (die bleiben unverändert
    /// für die Ganzobjekt-Transformation zuständig, auch bei einem `.path`/`.line`-Objekt ausserhalb
    /// des Punkt-Editier-Modus).
    case anchor(Int)
    case controlIn(Int)
    case controlOut(Int)
    /// Issue #19 (Linie-Biegepunkte): Biegepunkt-Griff in der Mitte eines aktuell GERADEN Segments
    /// (Int = Index des Start-Ankers dieses Segments) — Ziehen wandelt das Segment in eine Kurve um
    /// (siehe `CanvasStore.applySegmentBend`). Sobald ein Segment gekrümmt ist, verschwindet dieser
    /// Griff wieder zugunsten der echten Kontrollpunkt-Griffe (`controlOut(i)`/`controlIn(i+1)`).
    case segmentMidpoint(Int)

    static let resizeCases: [CanvasHandleKind] = [
        .topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left
    ]

    /// Vorzeichen (-1/0/1) je Achse relativ zur Objektmitte im unrotierten lokalen Raum — nil für rotate/cornerRadius.
    var resizeSign: (x: Double, y: Double)? {
        switch self {
        case .topLeft: return (-1, -1)
        case .top: return (0, -1)
        case .topRight: return (1, -1)
        case .right: return (1, 0)
        case .bottomRight: return (1, 1)
        case .bottom: return (0, 1)
        case .bottomLeft: return (-1, 1)
        case .left: return (-1, 0)
        case .rotate, .cornerRadius, .anchor, .controlIn, .controlOut, .segmentMidpoint: return nil
        }
    }

    /// Nur die vier Kanten-Griffe (nicht Ecken/Rotation/Eckenradius) haben beim Verzerren
    /// (Issue #9, ⌥+Drag) einen eindeutigen Achsenbezug — oben/unten verändert `skewXDegrees`
    /// (horizontale Scherung), links/rechts `skewYDegrees` (vertikale Scherung). Eine Ecke müsste
    /// beide Achsen gleichzeitig bedienen, das ist als Geste nicht eindeutig genug.
    var isEdgeHandle: Bool {
        switch self {
        case .top, .bottom, .left, .right: return true
        default: return false
        }
    }
}
