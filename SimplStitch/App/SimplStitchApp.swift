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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ThreadColor.self,
            ThreadPalette.self,
            AppSettings.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            // Issue #13: Standard-Garnlisten müssen vor der ersten View existieren (Objekt-
            // Inspektor greift sofort per @Query darauf zu) — eigener ModelContext statt
            // `container.mainContext`, das ist @MainActor-isoliert und hier noch nicht garantiert.
            BuiltInThreadPaletteBootstrapper().bootstrapIfNeeded(context: ModelContext(container))
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
