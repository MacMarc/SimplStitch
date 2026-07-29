//
//  SettingsView.swift
//  SimplStitch
//
//  Phase 8f: Einstellungen-Fenster (SwiftUI `Settings`-Scene, SimplStitchApp.swift),
//  gebunden an das seit Phase 3 existierende AppSettings-Modell. AppSettings ist ein
//  Singleton in der Praxis (genau eine Zeile) — `ensureSettingsExist()` legt sie beim
//  ersten Öffnen an, falls noch keine existiert.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]

    var body: some View {
        Form {
            if let settings = settingsList.first {
                settingsForm(settings)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: ensureSettingsExist)
    }

    @ViewBuilder
    private func settingsForm(_ settings: AppSettings) -> some View {
        Section("settings.section.units") {
            Picker(
                "settings.measurementUnit",
                selection: Binding(
                    get: { settings.preferredMeasurementUnit },
                    set: { settings.preferredMeasurementUnit = $0 }
                )
            ) {
                Text("settings.unit.millimeters").tag(MeasurementUnit.millimeters)
                Text("settings.unit.inches").tag(MeasurementUnit.inches)
            }
        }

        Section("settings.section.projects") {
            Stepper(
                value: Binding(
                    get: { settings.maxRecentProjects },
                    set: { settings.maxRecentProjects = $0 }
                ),
                in: 1...50
            ) {
                HStack {
                    Text("settings.maxRecentProjects")
                    Spacer()
                    Text(settings.maxRecentProjects, format: .number)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("settings.section.threads") {
            Picker(
                "settings.defaultPalette",
                selection: Binding(
                    get: { settings.defaultThreadPaletteID },
                    set: { settings.defaultThreadPaletteID = $0 }
                )
            ) {
                Text("settings.defaultPalette.none").tag(UUID?.none)
                ForEach(palettes) { palette in
                    Text(palette.name).tag(Optional(palette.id))
                }
            }
        }
    }

    private func ensureSettingsExist() {
        guard settingsList.isEmpty else { return }
        modelContext.insert(AppSettings())
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [AppSettings.self, ThreadPalette.self, ThreadColor.self], inMemory: true)
}
