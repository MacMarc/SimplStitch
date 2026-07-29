//
//  StitchSettings.swift
//  SimplStitch
//
//  Stichtyp, Dichte, Winkel und Unterlagentyp — jeweils pro DesignObject.
//

import Foundation
import SwiftData

enum StitchType: String, Codable, CaseIterable {
    case straight   // Laufstich
    case satin      // Satinstich
    case tatami     // Füllung

    /// Automatischer Stichtyp-Vorschlag je nach Objekt-Geometrie (Issue #11) — reine Heuristik zur
    /// Vorbelegung beim Erzeugen einer Form (siehe `CanvasStore.makeShapeObject`), im Objekt-
    /// Inspektor jederzeit manuell überschreibbar. Schmale, längliche Formen (kürzere Seite höchstens
    /// `satinMaxShortSideMillimeters` UND mindestens `1/satinAspectRatioThreshold`-mal länger als
    /// breit) eignen sich für Satin (Zickzag entlang der Längsachse — ein klassischer schmaler
    /// Steg/Balken); alles andere für eine flächige Tatami-Füllung. Gilt nur für geschlossene Formen
    /// (Rechteck/Kreis/Stern) — Freihand-Pfade (offene Linien) bekommen unabhängig davon `.straight`
    /// (siehe `CanvasStore.makePathObject`), da eine offene Linie ohnehin kein Füllgebiet hat.
    static func suggested(forShapeWidth width: Double, height: Double) -> StitchType {
        guard width > 0, height > 0 else { return .tatami }
        let shorterSide = min(width, height)
        let longerSide = max(width, height)
        guard shorterSide <= satinMaxShortSideMillimeters, shorterSide / longerSide <= satinAspectRatioThreshold else {
            return .tatami
        }
        return .satin
    }

    static let satinMaxShortSideMillimeters: Double = 15
    static let satinAspectRatioThreshold: Double = 0.3
}

enum UnderlayType: String, Codable, CaseIterable {
    case none
    case centerWalk
    case edgeWalk
    case zigzagNet

    /// Automatischer Unterlage-Vorschlag je Stichtyp (Issue #18), analog zu `StitchType.suggested`
    /// (Issue #11): reine Vorbelegung beim Erzeugen der Sticheinstellungen, im Objekt-Inspektor
    /// jederzeit manuell überschreibbar. Laufstich (offene Linie, kein Flächengebiet) bekommt keine
    /// Unterlage; Tatami-Füllung und Satin profitieren beide von einer Center-Walk-Unterlage.
    static func suggested(for stitchType: StitchType) -> UnderlayType {
        switch stitchType {
        case .straight: return .none
        case .tatami, .satin: return .centerWalk
        }
    }
}

@Model
final class StitchSettings {
    var stitchType: StitchType = StitchType.tatami
    var density: Double = 0.4 // mm Abstand zwischen Stichreihen
    var angleDegrees: Double = 0
    var underlayType: UnderlayType = UnderlayType.centerWalk

    var designObject: DesignObject?
    /// Issue #18: separate Rand-Sticheinstellungen — ein `StitchSettings`-Objekt gehört entweder
    /// über `designObject` (Füllung) oder über `borderOwner` (Rand) zu genau einem `DesignObject`,
    /// nie über beide gleichzeitig. Zwei getrennte Inverse-Relationships statt einer einzigen, da
    /// ein Objekt Füllung UND Rand unabhängig voneinander haben kann.
    var borderOwner: DesignObject?

    init(
        stitchType: StitchType = .tatami,
        density: Double = 0.4,
        angleDegrees: Double = 0,
        underlayType: UnderlayType = .centerWalk
    ) {
        self.stitchType = stitchType
        self.density = density
        self.angleDegrees = angleDegrees
        self.underlayType = underlayType
    }
}
