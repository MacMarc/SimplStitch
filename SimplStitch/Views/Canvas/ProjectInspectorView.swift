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

import SwiftUI
import SwiftData

struct ProjectInspectorView: View {
    let store: CanvasStore

    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]

    private var enabledPalettes: [ThreadPalette] {
        palettes.filter(\.isEnabled)
    }

    private var nameBinding: Binding<String> {
        Binding(get: { store.projectName }, set: { store.projectName = $0 })
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
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return ProjectInspectorView(store: store)
        .modelContainer(for: [ThreadPalette.self, ThreadColor.self], inMemory: true)
}
