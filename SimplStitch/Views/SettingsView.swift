//
//  SettingsView.swift
//  SimplStitch
//
//  Phase 8f: Einstellungen-Fenster (SwiftUI `Settings`-Scene, SimplStitchApp.swift),
//  gebunden an das seit Phase 3 existierende AppSettings-Modell. AppSettings ist ein
//  Singleton in der Praxis (genau eine Zeile) — `ensureSettingsExist()` legt sie beim
//  ersten Öffnen an, falls noch keine existiert.
//
//  Issue #21: ursprünglich ein einziges `Form` mit `.fixedSize(vertical: true)` — bei den
//  74 mitgelieferten Garnlisten (Issue #20) wuchs das Fenster über den Bildschirm hinaus statt
//  zu scrollen. Jetzt zwei Bereiche wie in den macOS-Systemeinstellungen (`TabView` mit
//  `.sidebarAdaptable`, feste Fenstergrösse): "Allgemein" (kurzes Form, passt immer) und
//  "Garnlisten" (eigenständige `List`, scrollt intern statt das Fenster zu strecken).
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
        TabView {
            Tab("settings.tab.general", systemImage: "gearshape") {
                if let settings = settingsList.first {
                    generalForm(settings)
                }
            }
            Tab("settings.tab.palettes", systemImage: "swatchpalette") {
                palettesPane
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(width: 520, height: 420)
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
    private func generalForm(_ settings: AppSettings) -> some View {
        Form {
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

            // Issue #25: Icon-/Textgrösse der Werkzeug-Toolbar war fest verdrahtet ("Tableiste zu
            // klein") — jetzt drei Stufen, angewendet in ContentView.iconButton.
            Section("settings.section.toolbar") {
                Picker(
                    "settings.toolbarSize",
                    selection: Binding(
                        get: { settings.toolbarSize },
                        set: { settings.toolbarSize = $0 }
                    )
                ) {
                    Text("settings.toolbarSize.small").tag(ToolbarSize.small)
                    Text("settings.toolbarSize.medium").tag(ToolbarSize.medium)
                    Text("settings.toolbarSize.large").tag(ToolbarSize.large)
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
        .formStyle(.grouped)
    }

    /// Issue #20: Garnlisten aktivieren/deaktivieren (deaktivierte Paletten werden im
    /// Projekt-Eigenschaften-Tab beim Hinzufügen neuer Garnfarben ausgeblendet) sowie
    /// Import/Löschen — appweite Palettenverwaltung gehört hierhin, nicht ins projektbezogene
    /// Inspector-Panel (ProjectInspectorView).
    /// Issue #21: eigene `List` statt `Form`-`Section` — scrollt bei vielen Paletten intern,
    /// statt das Fenster (das jetzt eine feste Grösse hat) zu sprengen.
    @ViewBuilder
    private var palettesPane: some View {
        VStack(spacing: 0) {
            if palettes.isEmpty {
                ContentUnavailableView(
                    "settings.section.palettes",
                    systemImage: "swatchpalette",
                    description: Text("settings.palettes.empty")
                )
            } else {
                List {
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
            }

            Divider()

            HStack {
                Spacer()
                Button {
                    isImporterPresented = true
                } label: {
                    Label("threads.import.button", systemImage: "square.and.arrow.down")
                }
                .padding(12)
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
