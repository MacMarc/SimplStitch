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

    /// Issue #23: Objekt-/Rand-Masse im Inspector waren bisher hart auf "(mm)" verdrahtet, obwohl
    /// diese Einstellung längst existierte. Interne Speicherung bleibt überall Millimeter (Canvas,
    /// SVG, Stichgenerierung) — nur Anzeige/Eingabe im Inspector rechnet um.
    var symbol: String {
        switch self {
        case .millimeters: return "mm"
        case .inches: return "in"
        }
    }

    func value(fromMillimeters millimeters: Double) -> Double {
        switch self {
        case .millimeters: return millimeters
        case .inches: return millimeters / 25.4
        }
    }

    func millimeters(from value: Double) -> Double {
        switch self {
        case .millimeters: return value
        case .inches: return value * 25.4
        }
    }
}

/// Issue #25: die Werkzeug-Toolbar war "zu klein" — Icon/Text-Grösse jetzt in den Einstellungen
/// wählbar statt eines einzigen festen Werts. Feste Werte je Stufe statt eines Multiplikators,
/// damit jede Stufe für sich austariert werden kann (z.B. Textgrösse nicht linear mit dem Icon).
enum ToolbarSize: String, Codable, CaseIterable {
    case small
    case medium
    case large

    var iconDiameter: Double {
        switch self {
        case .small: return 22
        case .medium: return 28
        case .large: return 34
        }
    }

    var symbolFontSize: Double {
        switch self {
        case .small: return 13
        case .medium: return 15
        case .large: return 18
        }
    }

    var textFontSize: Double {
        switch self {
        case .small: return 9
        case .medium: return 10.5
        case .large: return 12
        }
    }

    var buttonWidth: Double {
        switch self {
        case .small: return 50
        case .medium: return 58
        case .large: return 66
        }
    }
}

@Model
final class AppSettings {
    var preferredMeasurementUnit: MeasurementUnit = MeasurementUnit.millimeters
    var maxRecentProjects: Int = 10
    var defaultThreadPaletteID: UUID?
    /// Bugfix (Absturz "Neues Dokument", SIGABRT): bewusst `Optional` statt `= .medium`.
    /// Ein bereits vorhandener `AppSettings`-Datensatz aus der Zeit VOR diesem Feld hat in der
    /// SQLite-Spalte `NULL` stehen (per Crashlog verifiziert: `swift_dynamicCastFailure` im von
    /// `@Model` generierten Getter, ausgelöst beim ersten Lesezugriff aus `ContentView.toolbarSize`)
    /// — ein NICHT-optionales `@Model`-Feld mit Default-Wert schützt nur vor einem fehlenden
    /// Insert-Argument, nicht vor einer bereits bestehenden `NULL`-Spalte aus einem älteren Build.
    /// `Optional` lässt SwiftData `nil` zurückgeben statt zu crashen; alle Call-Sites lesen ohnehin
    /// schon über `?? .medium` (ContentView/SettingsView).
    var toolbarSize: ToolbarSize?

    init(
        preferredMeasurementUnit: MeasurementUnit = .millimeters,
        maxRecentProjects: Int = 10,
        toolbarSize: ToolbarSize = .medium
    ) {
        self.preferredMeasurementUnit = preferredMeasurementUnit
        self.maxRecentProjects = maxRecentProjects
        self.toolbarSize = toolbarSize
    }
}
