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
    var sharedModelContainer: ModelContainer = {
        // SwiftData Models werden in Phase 3 ergänzt (StitchProject, DesignObject, ThreadPalette, AppSettings …)
        let schema = Schema([])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
