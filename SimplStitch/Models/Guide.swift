//
//  Guide.swift
//  SimplStitch
//
//  Issue #31 (Phase 1): Hilfslinie im Photoshop/Illustrator-Stil, aus dem Lineal auf den Canvas
//  gezogen. Bewusst kein eigenes `@Model`, sondern ein reiner Value-Type: Quelle der Wahrheit für
//  den Projektinhalt ist `content.svg` (siehe StitchProject), eine Hilfslinie ist nur eine Zahl plus
//  Orientierung und braucht weder Identity-Tracking noch Relationships.
//

import Foundation

struct Guide: Identifiable, Equatable, Codable {
    enum Orientation: String, Codable {
        /// Waagerechte Linie, definiert durch eine Y-Koordinate (aus dem oberen Lineal gezogen).
        case horizontal
        /// Senkrechte Linie, definiert durch eine X-Koordinate (aus dem linken Lineal gezogen).
        case vertical
    }

    var id: UUID = UUID()
    var orientation: Orientation
    /// Design-Koordinate in Millimetern (Y bei horizontal, X bei vertikal) — dieselbe mm-Konvention
    /// und derselbe Ursprung (obere linke Canvas-Ecke) wie `DesignObject.positionX`/`positionY`.
    var position: Double
}
