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

                CanvasView(store: canvasStore)
            }
        }
    }
}

#Preview {
    ContentView()
}
