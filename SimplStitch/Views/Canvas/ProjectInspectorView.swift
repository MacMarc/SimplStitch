//
//  ProjectInspectorView.swift
//  SimplStitch
//
//  Issue #20 (nach User-Feedback vereinfacht): dritter Inspector-Tab "Projekt-Eigenschaften" —
//  ein einzelner Pulldown "Standard Garnliste", der nur Palettennamen zeigt (nicht deren Farben).
//  Die erste Fassung listete alle Farben aller aktiven Garnlisten einzeln auf (~20'000 Zeilen bei
//  den mitgelieferten InkStitch-Paletten) — spürbares Lag und vom Nutzer explizit nicht gewünscht.
//  Die Farben der hier gewählten Palette sind dann im Objekt-Inspektor (Füllung/Rand) mit Namen
//  auswählbar, siehe `CanvasStore.defaultThreadPaletteID` und `ObjectInspectorView`.
//
//  Garnlisten selbst importieren/löschen/(de)aktivieren passiert in SettingsView (Issue #20) —
//  appweite Verwaltung, kein Projekt-Zustand.
//
//  Issue #24 (Überarbeitung nach Live-Test):
//  - Unschöner Zeilenumbruch behoben: der Picker hatte zusätzlich zum Sektionstitel ein fast
//    identisches Zeilen-Label ("Standard Garnliste" neben "Standard-Garnliste" als Sektionstitel),
//    das bei langen Palettennamen (z.B. "InkStitch Robison-Anton Polyester") in der schmalen
//    Inspector-Spalte umbrach. Das redundante Zeilen-Label ist jetzt weg (`labelsHidden()`), der
//    Picker bekommt die volle Zeilenbreite für den Wertetext.
//  - Projektname jetzt editierbar (`StitchProject.name` existierte im Modell, war aber nirgends
//    in der UI erreichbar — der Fenstertitel kommt stattdessen vom Dateinamen, das bleibt so;
//    dies ist ein separater interner Anzeigename).
//  - Sektionsüberschriften vergrössert (`.headline`), analog zu ObjectInspectorView.
//
//  Issue #22: neue Sektion "Stickrahmen" — Canvas-Grösse per Pulldown auf eine gängige
//  Stickrahmen-Standardgrösse (`HoopSize.builtIn`) oder eine eigene, in den Einstellungen
//  angelegte Grösse (`CustomHoopSize`) setzen, plus manuelle W/H-Felder für beliebige Werte
//  (mm/Zoll-bewusst wie ObjectInspectorView, `AppSettings.preferredMeasurementUnit`).
//

import SwiftUI
import SwiftData

struct ProjectInspectorView: View {
    let store: CanvasStore

    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]
    @Query(sort: \CustomHoopSize.name) private var customHoopSizes: [CustomHoopSize]
    @Query private var appSettingsList: [AppSettings]

    private var enabledPalettes: [ThreadPalette] {
        palettes.filter(\.isEnabled)
    }

    private var unit: MeasurementUnit {
        appSettingsList.first?.preferredMeasurementUnit ?? .millimeters
    }

    private var nameBinding: Binding<String> {
        Binding(get: { store.projectName }, set: { store.projectName = $0 })
    }

    private var allHoopSizes: [HoopSize] {
        HoopSize.builtIn + customHoopSizes.map(\.asHoopSize)
    }

    /// Ordnet die aktuelle Canvas-Grösse einer bekannten Voreinstellung zu (exakter mm-Vergleich)
    /// — passt keine, zeigt der Picker "Benutzerdefiniert" (die manuellen W/H-Felder darunter
    /// erlauben ja jeden beliebigen Wert, nicht nur die kuratierte Liste).
    private var matchingHoopSize: HoopSize? {
        allHoopSizes.first {
            $0.widthMillimeters == store.canvasSizeMillimeters.width && $0.heightMillimeters == store.canvasSizeMillimeters.height
        }
    }

    private func canvasWidthBinding() -> Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: store.canvasSizeMillimeters.width) },
            set: { store.canvasSizeMillimeters.width = max(unit.millimeters(from: $0), 1) }
        )
    }

    private func canvasHeightBinding() -> Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: store.canvasSizeMillimeters.height) },
            set: { store.canvasSizeMillimeters.height = max(unit.millimeters(from: $0), 1) }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("project.name.label", text: nameBinding)
            } header: {
                Text("project.name.section").font(.headline)
            }

            Section {
                Picker(
                    "",
                    selection: Binding(
                        get: { matchingHoopSize },
                        set: { newValue in
                            guard let newValue else { return }
                            store.canvasSizeMillimeters = CGSize(width: newValue.widthMillimeters, height: newValue.heightMillimeters)
                        }
                    )
                ) {
                    Text("project.hoopSize.custom").tag(HoopSize?.none)
                    Section("project.hoopSize.builtIn") {
                        ForEach(HoopSize.builtIn) { size in
                            Text(size.name).tag(Optional(size))
                        }
                    }
                    if !customHoopSizes.isEmpty {
                        Section("project.hoopSize.custom.section") {
                            ForEach(customHoopSizes) { size in
                                Text(size.name).tag(Optional(size.asHoopSize))
                            }
                        }
                    }
                }
                .labelsHidden()

                LabeledContent {
                    HStack {
                        axisField("inspector.object.size.width", binding: canvasWidthBinding())
                        axisField("inspector.object.size.height", binding: canvasHeightBinding())
                    }
                } label: {
                    Text("project.hoopSize.manual") + Text(" (\(unit.symbol))")
                }
            } header: {
                Text("project.hoopSize.section").font(.headline)
            }

            Section {
                Picker(
                    "",
                    selection: Binding(
                        get: { store.defaultThreadPaletteID },
                        set: { store.defaultThreadPaletteID = $0 }
                    )
                ) {
                    Text("project.defaultPalette.none").tag(UUID?.none)
                    ForEach(enabledPalettes) { palette in
                        Text(palette.name).tag(Optional(palette.id))
                    }
                }
                .labelsHidden()
            } header: {
                Text("project.defaultPalette.section").font(.headline)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("project.threads.panel.title"))
    }

    private func axisField(_ labelKey: LocalizedStringKey, binding: Binding<Double>) -> some View {
        HStack(spacing: 3) {
            Text(labelKey).font(.caption2).foregroundStyle(.secondary)
            TextField("", value: binding, format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .frame(width: 50)
        }
    }
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return ProjectInspectorView(store: store)
        .modelContainer(for: [ThreadPalette.self, ThreadColor.self, CustomHoopSize.self, AppSettings.self], inMemory: true)
}
