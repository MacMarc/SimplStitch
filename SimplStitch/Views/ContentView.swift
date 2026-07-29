//
//  ContentView.swift
//  SimplStitch
//
//  Created by Marc Brechbühl on 29.07.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    // Platzhalter-Canvasgrösse, bis Phase 8 ein echtes Projekt via DocumentGroup öffnet.
    @State private var canvasStore = CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180))
    @State private var isLayersPanelPresented = true
    @State private var isExportDialogPresented = false
    // Eigener Subprocess statt canvasStores internem — der ist private (siehe CanvasStore-Kommentar
    // zu "ein PythonBridge-Subprocess pro CanvasStore reicht"). Einmalig hier gehalten (nicht pro
    // Sheet-Präsentation neu erzeugt), sonst würde jedes Öffnen des Export-Dialogs einen weiteren,
    // nie beendeten Subprocess starten.
    @State private var exportService = FileExportService(bridge: PythonBridge())

    var body: some View {
        NavigationSplitView {
            List {
                Text("sidebar.noProjects")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                // Platzhalter-Werkzeugleiste, bis Phase 8 die echte Toolbar (Menü + Symbolleiste) bringt.
                Picker("canvas.toolPicker.label", selection: Binding(
                    get: { canvasStore.currentTool },
                    set: { canvasStore.selectTool($0) }
                )) {
                    ForEach(CanvasTool.allCases) { tool in
                        Text(tool.displayName).tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)

                if let selected = canvasStore.selectedObject {
                    StitchDevPanelView(object: selected, store: canvasStore)
                }

                CanvasView(store: canvasStore)
            }
            .toolbar {
                // Platzhalter-Toggle fürs Ebenen-Panel, bis Phase 8 die echte Toolbar bringt.
                ToolbarItem {
                    Button {
                        isLayersPanelPresented.toggle()
                    } label: {
                        Label("layers.panel.toggle", systemImage: "square.3.layers.3d")
                    }
                }
                // Platzhalter-Export-Button, bis Phase 8 die echte Menü-/Toolbar-Verdrahtung bringt.
                ToolbarItem {
                    Button {
                        isExportDialogPresented = true
                    } label: {
                        Label("export.toolbar.button", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .inspector(isPresented: $isLayersPanelPresented) {
                LayersPanelView(store: canvasStore)
                    .inspectorColumnWidth(min: 200, ideal: 240)
            }
            .sheet(isPresented: $isExportDialogPresented) {
                ExportDialogView(
                    objects: canvasStore.objects,
                    canvasSize: canvasStore.canvasSizeMillimeters,
                    exportService: exportService
                )
            }
        }
    }
}

#Preview {
    ContentView()
}
