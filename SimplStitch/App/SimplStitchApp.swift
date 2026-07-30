//
//  SimplStitchApp.swift
//  SimplStitch
//
//  Created by Marc Brechbühl on 29.07.2026.
//

import SwiftUI
import SwiftData

@main
struct SimplStitchApp: App {
    // Nur noch projektübergreifende Modelle — StitchProject/DesignObject/StitchSettings leben
    // seit Phase 8a in einem eigenen, in-memory-only ModelContainer pro offenem Dokument
    // (StitchDesignDocument), da ihre echte Persistenz über content.svg läuft, nicht SwiftData.
    /// Bugfix (Crash beim Start): `ModelContainer(for:configurations:)` warf hier bisher direkt in
    /// einen `fatalError`, wenn SwiftDatas automatische Lightweight-Migration scheitert — reale
    /// Absturzursache, per macOS-Crashlog verifiziert (`EXC_BREAKPOINT` in `_assertionFailure`,
    /// ausgelöst durch dieses `fatalError`). Passiert typischerweise nach einem `@Model`-Schema-
    /// Wechsel (z.B. ein neues Feld), wenn der auf der Platte liegende Store aus einem älteren
    /// Build nicht automatisch migrierbar ist. Da dieser Store NUR appweite Preferences/Garnlisten
    /// hält — nicht die eigentlichen Projekte, die leben in content.svg (siehe StitchDesignDocument,
    /// Phase 8a) — ist ein Reset unkritisch: schlägt die Migration fehl, wird der inkompatible
    /// Store gelöscht und frisch angelegt, statt die ganze App unbenutzbar zu machen. Im schlimmsten
    /// Fall muss der Nutzer Garnlisten neu importieren/Einstellungen neu setzen, verliert aber keine
    /// Projektdaten.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ThreadColor.self,
            ThreadPalette.self,
            AppSettings.self,
            CustomHoopSize.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        func makeContainer() throws -> ModelContainer {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            // Issue #13: Standard-Garnlisten müssen vor der ersten View existieren (Objekt-
            // Inspektor greift sofort per @Query darauf zu) — eigener ModelContext statt
            // `container.mainContext`, das ist @MainActor-isoliert und hier noch nicht garantiert.
            BuiltInThreadPaletteBootstrapper().bootstrapIfNeeded(context: ModelContext(container))
            return container
        }

        if let container = try? makeContainer() {
            return container
        }

        let storeURL = modelConfiguration.url
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }

        do {
            return try makeContainer()
        } catch {
            fatalError("Could not create ModelContainer even after resetting the store: \(error)")
        }
    }()

    var body: some Scene {
        DocumentGroup(newDocument: { StitchDesignDocument() }) { configuration in
            ContentView(document: configuration.document)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            SimplStitchCommands()
        }

        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
    }
}
