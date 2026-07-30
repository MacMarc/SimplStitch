//
//  ContentView.swift
//  SimplStitch
//
//  Created by Marc Brechbühl on 29.07.2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var document: StitchDesignDocument
    // Issue #8: SwiftUI stellt für ReferenceFileDocument/DocumentGroup-Fenster einen pro Dokument
    // verdrahteten UndoManager bereit (Bearbeiten-Menü, ⌘Z/⌘⇧Z) — CanvasStore ist keine View und
    // hat daher keinen eigenen Environment-Zugriff, bekommt ihn also von hier durchgereicht.
    @Environment(\.undoManager) private var undoManager

    @State private var canvasStore: CanvasStore
    @State private var isInspectorPresented = true
    @State private var isExportDialogPresented = false
    @State private var isImportDialogPresented = false
    @State private var importErrorMessage: String?
    // Eigener Subprocess statt canvasStores internem — der ist private (siehe CanvasStore-Kommentar
    // zu "ein PythonBridge-Subprocess pro CanvasStore reicht"). Einmalig hier gehalten (nicht pro
    // Sheet-Präsentation neu erzeugt), sonst würde jedes Öffnen des Export-Dialogs einen weiteren,
    // nie beendeten Subprocess starten.
    @State private var exportService = FileExportService(bridge: PythonBridge())
    // Issue #7: eigener Subprocess wie exportService — Import und Export teilen sich bewusst
    // keinen Bridge-Prozess, derselbe Grund wie oben (Lebenszyklus/Fehlerisolation pro Feature).
    @State private var importService = FileImportService(bridge: PythonBridge())

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
            // Issue #7: Stickdatei-Import ans Menü (Ablage > Importieren…, SimplStitchCommands)
            // und an Drag&Drop direkt auf den Canvas angebunden — FileImportService selbst ist seit
            // Phase 7 fertig, es fehlte nur die UI-Anbindung.
            .fileImporter(
                isPresented: $isImportDialogPresented,
                allowedContentTypes: Self.embroideryContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importEmbroideryFile(at: url)
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                importEmbroideryFile(at: url)
                return true
            }
            .alert(
                "import.embroidery.error.title",
                isPresented: Binding(get: { importErrorMessage != nil }, set: { if !$0 { importErrorMessage = nil } })
            ) {
                Button("import.embroidery.error.dismiss") { importErrorMessage = nil }
            } message: {
                Text(importErrorMessage ?? "")
            }
            // Macht canvasStore/die Sheet-Bindings für die Menüleiste erreichbar (SimplStitchCommands,
            // Phase 8b) — .commands ist auf Scene-Ebene deklariert, hat also keinen direkten Zugriff
            // auf pro-Fenster-Zustand.
            .focusedSceneValue(\.canvasStore, canvasStore)
            .focusedSceneValue(\.isExportDialogPresented, $isExportDialogPresented)
            .focusedSceneValue(\.isImportDialogPresented, $isImportDialogPresented)
            .focusedSceneValue(\.isInspectorPresented, $isInspectorPresented)
            .onAppear { canvasStore.undoManager = undoManager }
        }
    }

    /// Kuratierte Auswahl der gängigsten der 46 von pyembroidery unterstützten Formate fürs
    /// `.fileImporter`-Panel (siehe FileImportService) — `.data` als Fallback, damit auch seltenere
    /// Formate ohne registrierten UTType wählbar bleiben, statt die Liste auf alle 46 aufzublähen.
    private static let embroideryContentTypes: [UTType] = {
        let extensions = ["vp3", "pes", "jef", "exp", "dst", "xxx", "hus", "jsf", "pcs", "csd", "u01", "10o", "vip", "sew"]
        return extensions.compactMap { UTType(filenameExtension: $0) } + [.data]
    }()

    private func importEmbroideryFile(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        Task {
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let pattern = try await importService.importEmbroideryFile(at: url)
                let newObjects = importService.designObjects(from: pattern)
                guard !newObjects.isEmpty else {
                    importErrorMessage = String(localized: "import.embroidery.empty")
                    return
                }
                canvasStore.importObjects(newObjects)
            } catch {
                importErrorMessage = error.localizedDescription
            }
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
