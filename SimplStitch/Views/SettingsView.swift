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
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]

    @State private var isImporterPresented = false
    @State private var importError: String?

    private let paletteImporter: GPLPaletteImporting

    init(paletteImporter: GPLPaletteImporting = GPLPaletteImporter()) {
        self.paletteImporter = paletteImporter
    }

    var body: some View {
        Form {
            if let settings = settingsList.first {
                settingsForm(settings)
            }
            paletteManagementSection()
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: ensureSettingsExist)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "gpl") ?? .plainText]
        ) { result in
            handleImportResult(result)
        }
        .alert(
            "threads.import.error.title",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("threads.import.error.dismiss") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
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

    /// Issue #20: Garnlisten aktivieren/deaktivieren (deaktivierte Paletten werden im
    /// Projekt-Eigenschaften-Tab beim Hinzufügen neuer Garnfarben ausgeblendet) sowie
    /// Import/Löschen — appweite Palettenverwaltung gehört hierhin, nicht ins projektbezogene
    /// Inspector-Panel (ProjectInspectorView).
    @ViewBuilder
    private func paletteManagementSection() -> some View {
        Section("settings.section.palettes") {
            if palettes.isEmpty {
                Text("settings.palettes.empty")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(palettes) { palette in
                    Toggle(
                        palette.name,
                        isOn: Binding(
                            get: { palette.isEnabled },
                            set: { palette.isEnabled = $0 }
                        )
                    )
                }
                .onDelete(perform: deletePalettes)
            }

            Button {
                isImporterPresented = true
            } label: {
                Label("threads.import.button", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func deletePalettes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(palettes[index])
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let palette = try paletteImporter.importPalette(at: url)
            modelContext.insert(palette)
        } catch {
            importError = error.localizedDescription
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
