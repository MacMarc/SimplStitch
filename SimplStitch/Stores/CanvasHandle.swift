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
        case .rotate, .cornerRadius: return nil
        }
    }
}
