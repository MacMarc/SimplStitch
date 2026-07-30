//
//  GroupInspectorView.swift
//  SimplStitch
//
//  "Eigenschaften"-Tab-Inhalt, wenn eine ganze Gruppe selektiert ist (Issue
//  #16) — `ObjectInspectorView` zeigt pro-Objekt-Felder (Position/Grösse/
//  Sticheinstellungen etc.), die für eine Mehrfachauswahl nicht sinnvoll
//  ausfüllbar sind. Bewusst minimal: nur Mitgliederanzahl + Gruppierung
//  aufheben. Transformieren der Gruppe passiert weiterhin direkt über die
//  Handles auf dem Canvas (CanvasStore.beginGroupTransformDrag).
//

import SwiftUI

struct GroupInspectorView: View {
    let groupID: UUID
    let memberCount: Int
    let store: CanvasStore

    var body: some View {
        Form {
            Section {
                LabeledContent("inspector.group.memberCount", value: String(memberCount))
                Button("inspector.group.ungroup") {
                    store.ungroup(groupID: groupID)
                }
            } header: {
                SectionHeader("inspector.group.section")
            }
        }
        .inspectorForm()
    }
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return GroupInspectorView(groupID: UUID(), memberCount: 3, store: store)
}
