//
//  CanvasInspectorView.swift
//  SimplStitch
//
//  Phase 8d: kombiniert Ebenen-Panel (5e) und Objekt-Inspektor (8d) in einem
//  einzigen `.inspector`-Bereich — SwiftUI erlaubt nur einen Inspector pro
//  Fenster, ähnlich der Format/Arrange-Tabs in Pages/Keynote. Wechselt
//  automatisch zur "Eigenschaften"-Ansicht, sobald ein Objekt selektiert wird
//  (wie das Format-Inspector-Verhalten in Pages/Keynote) — Nutzer können
//  jederzeit manuell zurück zu "Ebenen" wechseln.
//
//  Issue #14: der Tab-Picker sass ursprünglich als normales Geschwister-Element
//  über dem aktiven Panel in einem VStack — bei langem Panel-Inhalt (viele
//  Garnfarben/Ebenen) hat NICHT das jeweilige List/Form intern gescrollt,
//  sondern die umgebende `.inspector()`-Spalte hat den GESAMTEN VStack
//  (Picker inklusive) als einen Block gescrollt, weil der VStack ohne
//  explizite Höhenvorgabe keine verlässliche Scroll-Grenze für sein Kind-List
//  darstellt. Fix: Picker+Divider hängen jetzt als `.safeAreaInset(edge: .top)`
//  am jeweiligen Panel — das Panel (List/Form) ist damit der alleinige Root-
//  Inhalt und bekommt die volle verfügbare Höhe (scrollt zuverlässig intern),
//  der Picker liegt strukturell ausserhalb der Scroll-Hierarchie und kann
//  dadurch gar nicht mehr mitscrollen.
//

import SwiftUI

private enum InspectorTab: String, CaseIterable, Identifiable {
    case layers
    case object
    case project

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .layers: return String(localized: "inspector.tab.layers")
        case .object: return String(localized: "inspector.tab.object")
        case .project: return String(localized: "inspector.tab.project")
        }
    }
}

struct CanvasInspectorView: View {
    let store: CanvasStore

    @State private var selectedTab: InspectorTab = .layers

    var body: some View {
        Group {
            switch selectedTab {
            case .layers:
                LayersPanelView(store: store)
            case .object:
                if let object = store.selectedObject {
                    ObjectInspectorView(object: object, store: store)
                        .id(object.id)
                } else if let groupID = store.selectedGroupID {
                    GroupInspectorView(groupID: groupID, memberCount: store.selectedObjects.count, store: store)
                } else if store.selectedObjectIDs.count > 1 {
                    // Issue #23: eine Mehrfachauswahl aus (noch) nicht gruppierten Objekten zeigte
                    // bisher denselben "Kein Objekt ausgewählt"-Leerzustand wie gar keine Selektion —
                    // dort fehlte die Möglichkeit zu gruppieren, obwohl "Gruppierung aufheben" für
                    // eine bestehende Gruppe längst im Inspector verfügbar ist (GroupInspectorView).
                    MultiSelectionInspectorView(memberCount: store.selectedObjectIDs.count, store: store)
                } else {
                    ContentUnavailableView(
                        "inspector.object.empty",
                        systemImage: "square.dashed.inset.filled",
                        description: Text("inspector.object.empty.description")
                    )
                }
            case .project:
                ProjectInspectorView(store: store)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                // Issue #20: Pulldown statt Segmented Control — "Ebenen"/"Objekt-Eigenschaften"/
                // "Projekt-Eigenschaften" sind als deutsche Komposita zu lang für drei Segmente in
                // der schmalen Inspector-Spalte (240–280pt). Ein Menü-Picker bleibt bei jeder
                // Fensterbreite lesbar.
                Picker("", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(8)

                Divider()
            }
            .background(.bar)
        }
        .onChange(of: store.selectedObjectIDs) { _, newValue in
            if !newValue.isEmpty {
                selectedTab = .object
            }
        }
    }
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return CanvasInspectorView(store: store)
}
