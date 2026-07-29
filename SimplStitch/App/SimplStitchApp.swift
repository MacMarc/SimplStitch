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
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
    }
}
