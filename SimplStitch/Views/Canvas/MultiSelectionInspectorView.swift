//
//  MultiSelectionInspectorView.swift
//  SimplStitch
//
//  Issue #23: "Eigenschaften"-Tab-Inhalt, wenn mehrere (noch nicht gruppierte) Objekte selektiert
//  sind — vorher zeigte das den "Kein Objekt ausgewählt"-Leerzustand, obwohl `CanvasStore.
//  groupSelectedObjects()` längst existiert (Toolbar-Menü ⌘G) und `GroupInspectorView` das
//  Gegenstück "Gruppierung aufheben" für eine bestehende Gruppe schon anbietet. Symmetrisch dazu.
//

import SwiftUI

struct MultiSelectionInspectorView: View {
    let memberCount: Int
    let store: CanvasStore

    var body: some View {
        Form {
            Section {
                LabeledContent("inspector.group.memberCount", value: String(memberCount))
                Button("menu.object.group") {
                    store.groupSelectedObjects()
                }
            } header: {
                Text("inspector.multiSelection.section").font(.headline)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return MultiSelectionInspectorView(memberCount: 2, store: store)
}
