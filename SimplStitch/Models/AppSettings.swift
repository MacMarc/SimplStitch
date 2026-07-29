//
//  AppSettings.swift
//  SimplStitch
//
//  App-weite Preferences. "Zuletzt geöffnete Projekte" wird bewusst NICHT
//  hier gespeichert (keine Logic in Persistenz-Modellen) — das leitet ein
//  Store per @Query aus StitchProject.lastOpenedAt ab.
//

import Foundation
import SwiftData

enum MeasurementUnit: String, Codable, CaseIterable {
    case millimeters
    case inches
}

@Model
final class AppSettings {
    var preferredMeasurementUnit: MeasurementUnit = MeasurementUnit.millimeters
    var maxRecentProjects: Int = 10
    var defaultThreadPaletteID: UUID?

    init(
        preferredMeasurementUnit: MeasurementUnit = .millimeters,
        maxRecentProjects: Int = 10
    ) {
        self.preferredMeasurementUnit = preferredMeasurementUnit
        self.maxRecentProjects = maxRecentProjects
    }
}
