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
}

enum UnderlayType: String, Codable, CaseIterable {
    case none
    case centerWalk
    case edgeWalk
    case zigzagNet
}

@Model
final class StitchSettings {
    var stitchType: StitchType = StitchType.tatami
    var density: Double = 0.4 // mm Abstand zwischen Stichreihen
    var angleDegrees: Double = 0
    var underlayType: UnderlayType = UnderlayType.centerWalk

    var designObject: DesignObject?

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
