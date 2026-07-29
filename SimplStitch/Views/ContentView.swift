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
    @State private var isInspectorPresented = true
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
            CanvasView(store: canvasStore)
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
                        isInspectorPresented.toggle()
                    } label: {
                        Label("inspector.toggle", systemImage: "sidebar.trailing")
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
            .inspector(isPresented: $isInspectorPresented) {
                CanvasInspectorView(store: canvasStore)
                    .inspectorColumnWidth(min: 240, ideal: 280)
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
            .focusedSceneValue(\.isInspectorPresented, $isInspectorPresented)
        }
    }

    /// Apple-Mail-Stil (Issue #5): runder Icon-Kreis, gefüllt bei aktivem Werkzeug, kleinerer
    /// Text darunter statt Icon+Text nebeneinander in einer `.bordered`/`.borderedProminent`-Kapsel.
    /// `.plain`-ButtonStyle, da der Kreis-Hintergrund selbst die Aktiv-Kapsel übernimmt — eine
    /// zusätzliche Button-Kapsel würde den Kreis in ein Rechteck einfassen.
    ///
    /// Zwei Bugfixes nach User-Feedback auf der ersten Fassung:
    /// - `.contentShape(Rectangle())` auf dem gesamten Label: ohne das reagiert ein `.plain`-Button
    ///   mit nicht-opakem Inhalt (der Kreis-Hintergrund ist bei inaktivem Werkzeug `Color.clear`)
    ///   nur auf Klicks innerhalb der tatsächlich gezeichneten Pixel (SF-Symbol-Glyph, Text) — der
    ///   Leerraum dazwischen war klickunempfindlich, das Icon liess sich zwar treffen, der Text
    ///   darunter kaum. Der explizite Rechteck-Content-Shape macht das gesamte Label-Frame klickbar.
    /// - Kreis von 28pt auf 22pt verkleinert, Innenabstand reduziert: die vorherige Gesamthöhe
    ///   (Icon-Frame + Text) überschritt die von der Toolbar bereitgestellte Höhe, der obere Rand
    ///   des Kreises wurde dadurch sichtbar abgeschnitten ("Kreis schaut oben raus").
    @ViewBuilder
    private func toolButton(for tool: CanvasTool) -> some View {
        let isActive = canvasStore.currentTool == tool

        Button {
            canvasStore.selectTool(tool)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: tool.systemImageName)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
                    .background {
                        Circle().fill(isActive ? Color.accentColor : Color.clear)
                    }
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                Text(tool.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(width: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tool.displayName))
    }
}

#Preview {
    ContentView(document: StitchDesignDocument())
}
