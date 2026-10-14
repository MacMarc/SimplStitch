//
//  StitchProject.swift
//  SimplStitch
//
//  Wrapper für ein `.stitchdesign` Document Package. Die eigentliche
//  Quelle der Wahrheit für den Inhalt ist content.svg (Phase 4); `objects`
//  ist der in SwiftData gehaltene Arbeitsstand, aus dem SVG geschrieben
//  bzw. mit dem SVG befüllt wird.
//
//  fileBookmarkData statt einer reinen URL, weil ENABLE_USER_SELECTED_FILES
//  gesetzt ist (App Sandbox) — Security-Scoped-Bookmarks überleben Neustarts
//  zuverlässiger als gespeicherte Pfade.
//

import Foundation
import SwiftData

@Model
final class StitchProject {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var fileBookmarkData: Data?
    var lastKnownPath: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var lastOpenedAt: Date?
    var canvasWidthMillimeters: Double = 100
    var canvasHeightMillimeters: Double = 100

    /// Dateiname (nicht Pfad) des Hintergrundbilds unter assets/ im Document Package, falls gesetzt.
    var backgroundImageFileName: String?
    /// Issue #10: Deckkraft des Hintergrundbilds (0...1) — einstellbar, damit darüberliegende
    /// Objekte/Stiche beim Nachzeichnen lesbar bleiben.
    var backgroundImageOpacity: Double = 1.0
    /// Issue #10: Hintergrundbild ist eine eigene, ausblendbare "Ebene" (Nutzer-Feedback) — bleibt
    /// beim Ausblenden gesetzt (Bild + Deckkraft bleiben erhalten), wird nur nicht gezeichnet.
    var isBackgroundImageVisible: Bool = true

    /// Issue #20 (nach User-Feedback vereinfacht): EINE Standard-Garnliste pro Projekt statt einer
    /// kuratierten Farbliste — die alte "alle Farben aller aktiven Paletten einzeln auflisten"-UI
    /// verursachte mit ~20'000 Garnfarben (73 InkStitch-Paletten) massives Lag in der SwiftUI-Liste
    /// und gefiel dem Nutzer ohnehin nicht. `ThreadPalette.id`-Referenz, aufgelöst gegen die echten
    /// Paletten aus dem sharedModelContainer. Bewusst eine ID statt einer SwiftData-Relationship:
    /// StitchProject lebt ausserhalb des ModelContext (Quelle der Wahrheit ist content.svg, siehe
    /// Phase 8a), ThreadPalette dagegen im echten sharedModelContainer — beide Persistenz-Domänen
    /// lassen sich nicht über eine Relationship verbinden.
    var defaultThreadPaletteID: UUID?

    /// Issue #31: Hilfslinien des Projekts. Persistiert über `content.svg`
    /// (`<line data-ss-role="guide">`, siehe SVGDesignSerializer) wie der restliche Inhalt.
    /// StitchProject liegt in keinem SQLite-Store (nicht im Schema von SimplStitchApp), daher kein
    /// Migrationsrisiko durch das neue Feld — anders als bei AppSettings (`toolbarSize`-Präzedenzfall).
    ///
    /// Gespeichert als JSON-`Data` statt direkt als `[Guide]`: SwiftData stürzt bei einem
    /// Codable-Array-Attribut ab ("collection of codable but it failed to cast to a sequence"),
    /// sobald der gespeicherte Wert nil ist, z.B. beim Löschen/Cascade eines Projekts.
    private var guidesData: Data?

    var guides: [Guide] {
        get { guidesData.flatMap { try? JSONDecoder().decode([Guide].self, from: $0) } ?? [] }
        set { guidesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    @Relationship(deleteRule: .cascade, inverse: \DesignObject.project)
    var objects: [DesignObject] = []

    init(
        name: String,
        lastKnownPath: String,
        canvasWidthMillimeters: Double = 100,
        canvasHeightMillimeters: Double = 100
    ) {
        self.id = UUID()
        self.name = name
        self.lastKnownPath = lastKnownPath
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.canvasWidthMillimeters = canvasWidthMillimeters
        self.canvasHeightMillimeters = canvasHeightMillimeters
    }
}
