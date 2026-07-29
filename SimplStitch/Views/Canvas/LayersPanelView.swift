//
//  LayersPanelView.swift
//  SimplStitch
//
//  Ebenen-Panel (5e): listet CanvasStore.objects in Z-Order (oberstes Objekt
//  zuerst, wie in Illustrator/Affinity üblich), erlaubt Umsortieren per Drag
//  (`List.onMove`, macOS sortiert Listen ohne separaten Edit-Modus per Drag),
//  Sichtbarkeit/Sperre pro Objekt sowie Selektion — synchron mit der Canvas-
//  Selektion (`CanvasStore.selectedObjectID`). Die vier Z-Order-Buttons unten
//  spiegeln CanvasStore.ZOrderMove.
//
//  Eingebunden in ContentView über `.inspector(isPresented:)`.
//

import SwiftUI

struct LayersPanelView: View {
    let store: CanvasStore

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
                    ForEach(store.objectsFrontToBack, id: \.id) { object in
                        LayerRow(object: object, store: store)
                            .tag(object.id)
                    }
                    .onMove { offsets, destination in
                        store.reorderObjects(fromFrontToBackOffsets: offsets, toFrontToBackOffset: destination)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            zOrderControls
        }
        .navigationTitle(Text("layers.panel.title"))
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(get: { store.selectedObjectID }, set: { store.selectObject($0) })
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

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.toggleVisibility(of: object.id)
            } label: {
                Image(systemName: object.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(object.isVisible ? Color.primary : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(object.isVisible ? "layers.hide" : "layers.show")

            Text(object.name)
                .foregroundStyle(object.isVisible ? Color.primary : Color.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                store.toggleLock(of: object.id)
            } label: {
                Image(systemName: object.isLocked ? "lock.fill" : "lock.open")
            }
            .buttonStyle(.plain)
            .help(object.isLocked ? "layers.unlock" : "layers.lock")
        }
    }
}

#Preview {
    let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    return LayersPanelView(store: store)
}
