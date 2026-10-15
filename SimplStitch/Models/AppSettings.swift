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

    /// Issue #30 (Lineal): Nullpunkt der Lineal-BESCHRIFTUNG auf die Canvas-Mitte statt die obere
    /// linke Ecke — rein optisch (die tatsächlichen `positionX`/`positionY`-Koordinaten der Objekte,
    /// Export/Stichgenerierung bleiben unverändert auf der Ecke). Bewusst `Optional` statt `= false`
    /// — derselbe Bugfix-Präzedenzfall wie bei `toolbarSize` oben (SIGABRT bei einem bestehenden
    /// AppSettings-Datensatz mit NULL-Spalte für ein nachträglich hinzugefügtes, nicht-optionales
    /// Feld). Alle Lesestellen nutzen `?? false`.
    var rulerOriginXCentered: Bool?
    var rulerOriginYCentered: Bool?

    /// Apple Intelligence beim Bild-Nachzeichnen mitentscheiden lassen. Optional aus demselben
    /// Grund wie `toolbarSize` (bestehende Zeilen haben NULL); `nil` heisst "an" — wirkt ohnehin
    /// nur, wenn Apple Intelligence auf dem Mac verfügbar ist (`AppleIntelligenceStatus`).
    var usesAppleIntelligence: Bool?

    /// Einmalig gesetzt, sobald die Grundfarben als Standard-Garnliste vorbelegt wurden — danach
    /// darf der Nutzer auch bewusst "Keine" wählen, ohne dass der nächste Start das überschreibt.
    var didSeedDefaultThreadPalette: Bool?

    init(
        preferredMeasurementUnit: MeasurementUnit = .millimeters,
        maxRecentProjects: Int = 10,
        toolbarSize: ToolbarSize = .medium,
        rulerOriginXCentered: Bool = false,
        rulerOriginYCentered: Bool = false
    ) {
        self.preferredMeasurementUnit = preferredMeasurementUnit
        self.maxRecentProjects = maxRecentProjects
        self.toolbarSize = toolbarSize
        self.rulerOriginXCentered = rulerOriginXCentered
        self.rulerOriginYCentered = rulerOriginYCentered
    }
}

// Issue #32 (Finding 8): die `?? default`-Fallbacks für die optionalen bzw. evtl. noch fehlenden
// Felder lagen bisher an sechs Stellen in vier Views dupliziert. Hier zentral, damit eine künftige
// Default-/Migrationsänderung nur noch eine Stelle betrifft.
extension AppSettings {
    var isRulerOriginXCentered: Bool {
        get { rulerOriginXCentered ?? false }
        set { rulerOriginXCentered = newValue }
    }

    var isRulerOriginYCentered: Bool {
        get { rulerOriginYCentered ?? false }
        set { rulerOriginYCentered = newValue }
    }

    var isAppleIntelligenceEnabled: Bool {
        get { usesAppleIntelligence ?? true }
        set { usesAppleIntelligence = newValue }
    }
}

/// Lesezugriff auf die (einzige, Issue #23) AppSettings-Zeile aus einem `@Query`-Ergebnis — mit
/// denselben Defaults, falls Previews/Tests noch keine Zeile haben.
extension Collection where Element == AppSettings {
    var measurementUnit: MeasurementUnit {
        first?.preferredMeasurementUnit ?? .millimeters
    }

    var isRulerOriginXCentered: Bool {
        first?.isRulerOriginXCentered ?? false
    }

    var isRulerOriginYCentered: Bool {
        first?.isRulerOriginYCentered ?? false
    }

    var isAppleIntelligenceEnabled: Bool {
        first?.isAppleIntelligenceEnabled ?? true
    }
}
