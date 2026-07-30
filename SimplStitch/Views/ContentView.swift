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
                //
                // Issue #26 (Bug 1): der "Apple-Mail-Stil" (Issue #5) war insgesamt höher als die
                // System-Titlebar/Toolbar und lief in den Fensterinhalt über. Die erste
                // Nachbesserung ersetzte das fälschlich durch native `Label`+`.buttonStyle`-Buttons
                // (Icon+Text NEBENEINANDER) — der Nutzer wollte aber ausdrücklich Text UNTER dem
                // Icon, wie in Mail/Notizen. Fix: `ToolbarIconLabel` (DesignSystem.swift) liefert
                // genau dieses Layout, aber mit fest bemessenen, bewusst kleinen Massen, die sicher
                // innerhalb der Toolbar-Höhe bleiben, statt der vormals konfigurierbaren (bis 34pt
                // Icon) `AppSettings.toolbarSize`-Werte, die die eigentliche Überlauf-Ursache waren.
                ToolbarItemGroup(placement: .principal) {
                    ForEach(CanvasTool.allCases) { tool in
                        toolButton(for: tool)
                    }
                }

                // Exportieren ist eine Aktion, kein Werkzeug-Modus — gehört nicht in dieselbe
                // Gruppe wie die Werkzeugauswahl (Issue #26). Gleiches Icon-über-Text-Layout wie
                // die Werkzeuge, für ein einheitliches Erscheinungsbild der gesamten Toolbar.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isExportDialogPresented = true
                    } label: {
                        ToolbarIconLabel(systemImage: "square.and.arrow.up", title: String(localized: "export.toolbar.button"))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("export.toolbar.button"))
                }

                ToolbarItem {
                    Button {
                        isInspectorPresented.toggle()
                    } label: {
                        ToolbarIconLabel(systemImage: "sidebar.trailing", title: String(localized: "inspector.toggle"), isActive: isInspectorPresented)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("inspector.toggle"))
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
                        importFile(at: url)
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                importFile(at: url)
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
    /// `.svg` zusätzlich für den generischen SVG-Import (Issue #6, `SVGDesignSerializer`).
    private static let embroideryContentTypes: [UTType] = {
        let extensions = ["vp3", "pes", "jef", "exp", "dst", "xxx", "hus", "jsf", "pcs", "csd", "u01", "10o", "vip", "sew"]
        return extensions.compactMap { UTType(filenameExtension: $0) } + [.data, .svg]
    }()

    /// Dispatcht anhand der Dateiendung: `.svg` läuft über `SVGDesignSerializer` (rein Swift, kein
    /// Python-Subprocess — Issue #6), alles andere über die bestehende `FileImportService`-Bridge
    /// (Issue #7). Beide Wege (Menü/Drag&Drop) rufen dieselbe Methode auf.
    private func importFile(at url: URL) {
        if url.pathExtension.lowercased() == "svg" {
            importSVGFile(at: url)
        } else {
            importEmbroideryFile(at: url)
        }
    }

    /// Issue #6: eigenständiger SVG-Import (kein pyembroidery/InkStitch-Umweg) — beliebige
    /// Illustrator/Inkscape-Dateien, nicht nur unser eigenes `content.svg`-Schema. Synchron, da
    /// `SVGDesignSerializer.decode` reines `XMLParser`-Parsing ist, kein Subprocess-Aufruf.
    private func importSVGFile(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let svgString = try String(contentsOf: url, encoding: .utf8)
            let decoded = try SVGDesignSerializer().decode(svg: svgString)
            guard !decoded.objects.isEmpty else {
                importErrorMessage = String(localized: "import.svg.empty")
                return
            }
            canvasStore.importObjects(decoded.objects)
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }

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

    /// Werkzeugauswahl-Button — Icon über Text (`ToolbarIconLabel`, siehe DesignSystem.swift),
    /// exakt wie vom Nutzer gewünscht (Mail/Notizen-Stil), aber mit fest bemessenen, absichtlich
    /// kleinen Massen statt der vormals konfigurierbaren `AppSettings.toolbarSize`-Werte, die zum
    /// Überlauf über die Titlebar geführt hatten (Issue #26, Bug 1).
    private func toolButton(for tool: CanvasTool) -> some View {
        Button {
            canvasStore.selectTool(tool)
        } label: {
            ToolbarIconLabel(systemImage: tool.systemImageName, title: tool.displayName, isActive: canvasStore.currentTool == tool)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tool.displayName))
    }
}

#Preview {
    ContentView(document: StitchDesignDocument())
}
