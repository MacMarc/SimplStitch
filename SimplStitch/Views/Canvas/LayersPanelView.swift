//
//  LayersPanelView.swift
//  SimplStitch
//
//  Ebenen-Panel (5e): listet CanvasStore.objects in Z-Order (oberstes Objekt
//  zuerst, wie in Illustrator/Affinity üblich), erlaubt Umsortieren per Drag
//  (`List.onMove`, macOS sortiert Listen ohne separaten Edit-Modus per Drag),
//  Sichtbarkeit/Sperre pro Objekt sowie Selektion — synchron mit der Canvas-
//  Selektion (`CanvasStore.selectedObjectIDs`). Die vier Z-Order-Buttons unten
//  spiegeln CanvasStore.ZOrderMove und sind bei Gruppen-/Mehrfachauswahl
//  deaktiviert (siehe Klassenkommentar CanvasStore.selectedObjectID).
//
//  Gruppierung (Issue #16): Objekte mit gleicher `groupID` sind im Ebenen-
//  Panel unter einer klappbaren Gruppen-Zeile verschachtelt statt als flache
//  Liste — Gruppenmitglieder liegen dank `CanvasStore.groupSelectedObjects()`
//  immer als zusammenhängender Block in `objectsFrontToBack`, das erlaubt eine
//  einfache lineare Gruppierung beim Aufbau der Zeilen (`buildRows`). Die
//  native `List(selection: Set<UUID>)`-Mehrfachauswahl (Cmd/Shift-Klick) tagged
//  Gruppen-Zeilen mit der `groupID` selbst — die Übersetzung zu/von den
//  tatsächlichen Mitglieds-IDs (CanvasStore.selectedObjectIDs) passiert in
//  `selectionBinding`.
//
//  Eingebunden in ContentView über `.inspector(isPresented:)`.
//
//  Sichtbarkeits-/Sperr-Icons on demand (Nutzer-Feedback, Opus-Konsultation): die beiden
//  Icon-Buttons pro Zeile waren bisher permanent sichtbar, auch im (häufigsten) Normalzustand
//  sichtbar+entsperrt — das erzeugte bei vielen Ebenen unnötige visuelle Unruhe. Jetzt blendet
//  `LayerRow` die Buttons nur ein, wenn die Zeile gehovert oder selektiert ist ("wir brauchen sie
//  gerade") — EIN Nicht-Standard-Zustand (ausgeblendet/gesperrt) bleibt davon unabhängig immer als
//  stiller Indikator sichtbar, damit man beim Scannen der Liste nicht verliert, welche Ebenen
//  betroffen sind. Reserviert per `.opacity`/fester Breite weiterhin den Platz (kein Reflow/Jitter
//  des Namens, VoiceOver/Tastaturnutzer erreichen die Buttons weiterhin über Selektion).
//

import SwiftUI

struct LayersPanelView: View {
    let store: CanvasStore

    @State private var collapsedGroups: Set<UUID> = []

    private enum Row: Identifiable {
        case object(DesignObject)
        case group(id: UUID, members: [DesignObject])

        var id: UUID {
            switch self {
            case .object(let object): return object.id
            case .group(let id, _): return id
            }
        }
    }

    private var rows: [Row] {
        var result: [Row] = []
        var index = 0
        let ordered = store.objectsFrontToBack
        while index < ordered.count {
            let object = ordered[index]
            if let groupID = object.groupID {
                var members: [DesignObject] = []
                while index < ordered.count, ordered[index].groupID == groupID {
                    members.append(ordered[index])
                    index += 1
                }
                result.append(.group(id: groupID, members: members))
            } else {
                result.append(.object(object))
                index += 1
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.objects.isEmpty {
                ContentUnavailableView(
                    "layers.panel.empty",
                    systemImage: "square.3.layers.3d",
                    description: Text("layers.panel.empty.description")
                )
            } else {
                List(selection: selectionBinding) {
                    ForEach(rows) { row in
                        switch row {
                        case .object(let object):
                            LayerRow(
                                object: object,
                                store: store,
                                isSelected: store.selectedObjectIDs.contains(object.id)
                            )
                            .tag(object.id)
                        case .group(let groupID, let members):
                            DisclosureGroup(isExpanded: expandedBinding(for: groupID)) {
                                ForEach(members, id: \.id) { member in
                                    LayerRow(
                                        object: member,
                                        store: store,
                                        isSelected: store.selectedObjectIDs.contains(member.id)
                                    )
                                    .tag(member.id)
                                    .padding(.leading, 16)
                                }
                            } label: {
                                GroupRow(groupID: groupID, memberCount: members.count, store: store)
                            }
                            .tag(groupID)
                        }
                    }
                    .onMove { offsets, destination in
                        reorderRows(from: offsets, to: destination)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            zOrderControls
        }
        .navigationTitle(Text("layers.panel.title"))
    }

    private func expandedBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    collapsedGroups.remove(groupID)
                } else {
                    collapsedGroups.insert(groupID)
                }
            }
        )
    }

    /// Übersetzt zwischen den Zeilen-Tags der Liste (Objekt-IDs für Einzelzeilen, Gruppen-IDs für
    /// Gruppenzeilen) und `CanvasStore.selectedObjectIDs` (immer konkrete Mitglieds-IDs).
    private var selectionBinding: Binding<Set<UUID>> {
        Binding(
            get: {
                var tags: Set<UUID> = []
                for row in rows {
                    switch row {
                    case .object(let object):
                        if store.selectedObjectIDs.contains(object.id) { tags.insert(object.id) }
                    case .group(let groupID, let members):
                        if members.allSatisfy({ store.selectedObjectIDs.contains($0.id) }) {
                            tags.insert(groupID)
                        }
                    }
                }
                return tags
            },
            set: { newTags in
                var ids: Set<UUID> = []
                for row in rows {
                    switch row {
                    case .object(let object):
                        if newTags.contains(object.id) { ids.insert(object.id) }
                    case .group(let groupID, let members):
                        if newTags.contains(groupID) { ids.formUnion(members.map(\.id)) }
                    }
                }
                store.replaceSelection(ids)
            }
        )
    }

    /// Jede Row (Einzelobjekt oder Gruppen-Block) entspricht einem zusammenhängenden Abschnitt in
    /// `store.objectsFrontToBack` — eine Gruppen-Zeile wird beim Drag also als Ganzes verschoben.
    private func reorderRows(from offsets: IndexSet, to destination: Int) {
        var reordered = rows
        reordered.move(fromOffsets: offsets, toOffset: destination)
        let newFrontToBack = reordered.flatMap { row -> [DesignObject] in
            switch row {
            case .object(let object): return [object]
            case .group(_, let members): return members
            }
        }
        store.applyFrontToBackOrder(newFrontToBack)
    }

    private var zOrderControls: some View {
        HStack(spacing: 12) {
            zOrderButton(.toBack, systemImage: "square.3.layers.3d.bottom.filled", labelKey: "layers.moveToBack")
            zOrderButton(.backward, systemImage: "chevron.down", labelKey: "layers.moveBackward")
            zOrderButton(.forward, systemImage: "chevron.up", labelKey: "layers.moveForward")
            zOrderButton(.toFront, systemImage: "square.3.layers.3d.top.filled", labelKey: "layers.moveToFront")
            Spacer()
        }
        .padding(8)
    }

    private func zOrderButton(_ move: CanvasStore.ZOrderMove, systemImage: String, labelKey: LocalizedStringKey) -> some View {
        Button {
            guard let id = store.selectedObjectID else { return }
            store.moveObject(id, move)
        } label: {
            Label(labelKey, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .help(labelKey)
        .disabled(store.selectedObjectID == nil)
    }
}

private struct LayerRow: View {
    let object: DesignObject
    let store: CanvasStore
    let isSelected: Bool

    @State private var isHovered = false

    /// Zeile "in Benutzung" — Hover ODER Selektion. Selektion ist bewusst mit eingeschlossen,
    /// nicht nur Hover: sonst kämen Tastatur-/VoiceOver-Nutzer (die nie hovern) nie an die Buttons,
    /// und ein gerade angeklicktes Objekt soll seine Bedienelemente behalten, während man
    /// entscheidet, ob man es sperrt/ausblendet.
    private var revealsControls: Bool { isHovered || isSelected }

    var body: some View {
        HStack(spacing: 8) {
            iconButton(
                systemName: object.isVisible ? "eye" : "eye.slash",
                isNonDefault: !object.isVisible,
                helpKey: object.isVisible ? "layers.hide" : "layers.show"
            ) {
                store.toggleVisibility(of: object.id)
            }

            Text(object.name)
                .foregroundStyle(object.isVisible ? Color.primary : Color.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            iconButton(
                systemName: object.isLocked ? "lock.fill" : "lock.open",
                isNonDefault: object.isLocked,
                helpKey: object.isLocked ? "layers.unlock" : "layers.lock"
            ) {
                store.toggleLock(of: object.id)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: revealsControls)
    }

    /// Standardzustand (sichtbar+entsperrt) bleibt unsichtbar, bis die Zeile gebraucht wird
    /// (Hover/Selektion) — ein Nicht-Standard-Zustand (ausgeblendet/gesperrt) bleibt dagegen immer
    /// als stiller Indikator sichtbar, unabhängig von Hover/Selektion, damit man beim Scannen der
    /// Liste nicht verliert, welche Ebenen betroffen sind. `.opacity` statt bedingtem Einfügen hält
    /// die Zeilenbreite stabil (kein Reflow des Namens) und den Button weiterhin für VoiceOver
    /// erreichbar.
    @ViewBuilder
    private func iconButton(
        systemName: String,
        isNonDefault: Bool,
        helpKey: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        let shouldShow = revealsControls || isNonDefault
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(isNonDefault ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .help(helpKey)
        .frame(width: 20)
        .opacity(shouldShow ? 1 : 0)
        .allowsHitTesting(shouldShow)
    }
}

/// Label einer Gruppen-Zeile im Ebenen-Panel — zeigt Mitgliederanzahl und bietet "Gruppierung
/// aufheben" per Kontextmenü an, unabhängig davon, ob die Gruppe gerade selektiert ist.
private struct GroupRow: View {
    let groupID: UUID
    let memberCount: Int
    let store: CanvasStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(Color.secondary)
            Text(String(format: String(localized: "layers.group.label"), memberCount))
                .lineLimit(1)
            Spacer()
        }
        .contextMenu {
            Button("layers.group.ungroup") {
                store.ungroup(groupID: groupID)
            }
        }
    }
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return LayersPanelView(store: store)
}
