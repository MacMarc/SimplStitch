//
//  ContentView.swift
//  SimplStitch
//
//  Created by Marc Brechbühl on 29.07.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject var document: StitchDesignDocument

    @State private var canvasStore: CanvasStore
    @State private var isLayersPanelPresented = true
    @State private var isExportDialogPresented = false
    // Eigener Subprocess statt canvasStores internem — der ist private (siehe CanvasStore-Kommentar
    // zu "ein PythonBridge-Subprocess pro CanvasStore reicht"). Einmalig hier gehalten (nicht pro
    // Sheet-Präsentation neu erzeugt), sonst würde jedes Öffnen des Export-Dialogs einen weiteren,
    // nie beendeten Subprocess starten.
    @State private var exportService = FileExportService(bridge: PythonBridge())

    init(document: StitchDesignDocument) {
        self.document = document
        self._canvasStore = State(initialValue: CanvasStore(project: document.project))
    }

    var body: some View {
        NavigationSplitView {
            List {
                Text("sidebar.noProjects")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(spacing: 0) {
                if let selected = canvasStore.selectedObject {
                    StitchDevPanelView(object: selected, store: canvasStore)
                }

                CanvasView(store: canvasStore)
            }
            .toolbar {
                // Werkzeugauswahl (8c) — dieselben 6 CanvasTool-Fälle wie das Werkzeug-Menü (8b),
                // Icon+Text erzwungen (.labelStyle(.titleAndIcon)) statt der macOS-Standardregel zu
                // folgen, die eine Toolbar-Label meist auf reines Icon reduziert — CLAUDE.md verlangt
                // hier explizit "Icon + Text-Label (kein Icon-Raten)".
                ToolbarItemGroup(placement: .principal) {
                    ForEach(CanvasTool.allCases) { tool in
                        toolButton(for: tool)
                    }
                }

                ToolbarItem {
                    Button {
                        isLayersPanelPresented.toggle()
                    } label: {
                        Label("layers.panel.toggle", systemImage: "square.3.layers.3d")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem {
                    Button {
                        isExportDialogPresented = true
                    } label: {
                        Label("export.toolbar.button", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
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
            // Macht canvasStore/die Sheet-Bindings für die Menüleiste erreichbar (SimplStitchCommands,
            // Phase 8b) — .commands ist auf Scene-Ebene deklariert, hat also keinen direkten Zugriff
            // auf pro-Fenster-Zustand.
            .focusedSceneValue(\.canvasStore, canvasStore)
            .focusedSceneValue(\.isExportDialogPresented, $isExportDialogPresented)
            .focusedSceneValue(\.isLayersPanelPresented, $isLayersPanelPresented)
        }
    }

    /// `.borderedProminent` nur für das aktive Werkzeug — als `if`/`else` statt eines Ternarys
    /// zwischen zwei ButtonStyle-Typen, da `.borderedProminent`/`.bordered` unterschiedliche
    /// konkrete Typen sind und sich nicht direkt in einem Ausdruck vereinen lassen.
    @ViewBuilder
    private func toolButton(for tool: CanvasTool) -> some View {
        let button = Button {
            canvasStore.selectTool(tool)
        } label: {
            Label(tool.displayName, systemImage: tool.systemImageName)
                .labelStyle(.titleAndIcon)
        }

        if canvasStore.currentTool == tool {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

#Preview {
    ContentView(document: StitchDesignDocument())
}
