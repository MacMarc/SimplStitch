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
//  zu scrollen. Danach zwei Bereiche wie in den macOS-Systemeinstellungen (`TabView` mit
//  `.sidebarAdaptable`, feste Fenstergrösse).
//
//  Issue #26 (Bug 3): `.tabViewStyle(.sidebarAdaptable)` sieht den echten Systemeinstellungen zwar
//  ähnlich, ist aber technisch eine einklappbare Sidebar mit Toggle-Button — echte
//  Systemeinstellungen haben eine feste, nicht einklappbare Sidebar. Ausserdem waren die
//  Garnlisten-/Stickrahmen-Panes reine `VStack`s ohne Top-Alignment, ihr Inhalt zentrierte sich
//  vertikal im Fenster statt oben zu beginnen. Fix: echte `NavigationSplitView` mit fest breiter
//  `List`-Sidebar (nicht ausblendbar) statt `TabView`, jede Detail-Pane explizit oben ausgerichtet.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case palettes
    case hoopSizes

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .general: return "settings.tab.general"
        case .palettes: return "settings.tab.palettes"
        case .hoopSizes: return "settings.tab.hoopSizes"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .palettes: return "swatchpalette"
        case .hoopSizes: return "square.dashed"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]
    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]
    @Query(sort: \CustomHoopSize.name) private var customHoopSizes: [CustomHoopSize]

    @State private var isImporterPresented = false
    @State private var importError: String?

    // Issue #22: Formular zum Anlegen eigener Stickrahmen-Grössen.
    @State private var newHoopName = ""
    @State private var newHoopWidth: Double = 100
    @State private var newHoopHeight: Double = 100

    private let paletteImporter: GPLPaletteImporting

    @State private var selectedSection: SettingsSection = .general

    private var unit: MeasurementUnit {
        settingsList.first?.preferredMeasurementUnit ?? .millimeters
    }

    init(paletteImporter: GPLPaletteImporting = GPLPaletteImporter()) {
        self.paletteImporter = paletteImporter
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.titleKey, systemImage: section.systemImage).tag(section)
            }
            // Feste Breite (min == ideal == max): die Sidebar lässt sich weder ziehen noch
            // einklappen — wie in den echten macOS-Systemeinstellungen (Issue #26, Bug 3a).
            .navigationSplitViewColumnWidth(DesignSystem.settingsSidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedSection {
                case .general:
                    if let settings = settingsList.first {
                        generalForm(settings)
                    }
                case .palettes:
                    palettesPane
                case .hoopSizes:
                    hoopSizesPane
                }
            }
            // Issue #26, Bug 3b: Inhalt beginnt jetzt oben statt sich bei kurzem Inhalt vertikal
            // im Fenster zu zentrieren.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 560, height: 420)
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

                // Issue #30: rein optische Verschiebung der Lineal-BESCHRIFTUNG — betrifft weder
                // die gespeicherten Objektkoordinaten noch Export/Stichgenerierung (siehe
                // CanvasView.rulerLabel-Offset-Kommentar).
                Toggle(
                    "settings.ruler.originXCentered",
                    isOn: Binding(
                        get: { settings.rulerOriginXCentered ?? false },
                        set: { settings.rulerOriginXCentered = $0 }
                    )
                )
                Toggle(
                    "settings.ruler.originYCentered",
                    isOn: Binding(
                        get: { settings.rulerOriginYCentered ?? false },
                        set: { settings.rulerOriginYCentered = $0 }
                    )
                )
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
        .inspectorForm()
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
                HStack {
                    Spacer()
                    Button("settings.palettes.enableAll") { setAllPalettes(enabled: true) }
                    Button("settings.palettes.disableAll") { setAllPalettes(enabled: false) }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

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

    /// Issue #29 (Punkt 4): Sammelaktion statt jede der potenziell 74 mitgelieferten
    /// Garnlisten einzeln umzuschalten. Zwei eindeutige Buttons statt eines Toggles, da ein
    /// einzelner Umschalt-Button bei gemischtem Aktivierungszustand mehrdeutig wäre.
    private func setAllPalettes(enabled: Bool) {
        for palette in palettes {
            palette.isEnabled = enabled
        }
    }

    /// Issue #22: eigene Stickrahmen-Grössen — appweit verwaltet (wie Garnlisten), im Projekt-
    /// Eigenschaften-Tab (`ProjectInspectorView`) neben den kuratierten Standardgrössen wählbar.
    @ViewBuilder
    private var hoopSizesPane: some View {
        VStack(spacing: 0) {
            if customHoopSizes.isEmpty {
                ContentUnavailableView(
                    "settings.hoopSizes.empty",
                    systemImage: "square.dashed",
                    description: Text("settings.hoopSizes.empty.description")
                )
            } else {
                List {
                    ForEach(customHoopSizes) { size in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(size.name)
                            Text("\(Int(size.widthMillimeters)) × \(Int(size.heightMillimeters)) mm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteHoopSizes)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("settings.hoopSizes.add")
                TextField("settings.hoopSizes.name", text: $newHoopName)
                HStack {
                    AxisField("W", binding: $newHoopWidth)
                    AxisField("H", binding: $newHoopHeight)
                    Text(unit.symbol).foregroundStyle(.secondary)
                    Spacer()
                    Button("settings.hoopSizes.addButton") { addHoopSize() }
                        .disabled(newHoopName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
        }
    }

    private func addHoopSize() {
        let trimmedName = newHoopName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let size = CustomHoopSize(
            name: trimmedName,
            widthMillimeters: unit.millimeters(from: newHoopWidth),
            heightMillimeters: unit.millimeters(from: newHoopHeight)
        )
        modelContext.insert(size)
        newHoopName = ""
        newHoopWidth = unit.value(fromMillimeters: 100)
        newHoopHeight = unit.value(fromMillimeters: 100)
    }

    private func deleteHoopSizes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(customHoopSizes[index])
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
        .modelContainer(for: [AppSettings.self, ThreadPalette.self, ThreadColor.self, CustomHoopSize.self], inMemory: true)
}
