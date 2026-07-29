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

import SwiftUI
import SwiftData

struct ProjectInspectorView: View {
    let store: CanvasStore

    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]

    private var enabledPalettes: [ThreadPalette] {
        palettes.filter(\.isEnabled)
    }

    var body: some View {
        Form {
            Section("project.defaultPalette.section") {
                Picker(
                    "project.defaultPalette.label",
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
