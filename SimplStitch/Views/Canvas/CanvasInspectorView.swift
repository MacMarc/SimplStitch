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

import SwiftUI

private enum InspectorTab: String, CaseIterable, Identifiable {
    case layers
    case object
    case threads

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .layers: return String(localized: "inspector.tab.layers")
        case .object: return String(localized: "inspector.tab.object")
        case .threads: return String(localized: "inspector.tab.threads")
        }
    }
}

struct CanvasInspectorView: View {
    let store: CanvasStore

    @State private var selectedTab: InspectorTab = .layers

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            switch selectedTab {
            case .layers:
                LayersPanelView(store: store)
            case .object:
                if let object = store.selectedObject {
                    ObjectInspectorView(object: object, store: store)
                } else if let groupID = store.selectedGroupID {
                    GroupInspectorView(groupID: groupID, memberCount: store.selectedObjects.count, store: store)
                } else {
                    ContentUnavailableView(
                        "inspector.object.empty",
                        systemImage: "square.dashed.inset.filled",
                        description: Text("inspector.object.empty.description")
                    )
                }
            case .threads:
                ThreadPalettesPanelView()
            }
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
