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
    // Issue #25: Icon-/Textgrösse der Werkzeug-Toolbar ist jetzt in den Einstellungen wählbar
    // (AppSettings.toolbarSize) statt eines einzigen fest verdrahteten Werts.
    @Query private var appSettingsList: [AppSettings]

    private var toolbarSize: ToolbarSize {
        appSettingsList.first?.toolbarSize ?? .medium
    }

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
                // Issue #25: Exportieren zieht als letztes Element in dieselbe Icon-Gruppe ein
                // (vorher ein separater, anders gestylter Toolbar-Button neben Inspektor).
                ToolbarItemGroup(placement: .principal) {
                    ForEach(CanvasTool.allCases) { tool in
                        toolButton(for: tool)
                    }
                    iconButton(systemImage: "square.and.arrow.up", label: String(localized: "export.toolbar.button")) {
                        isExportDialogPresented = true
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

    /// Apple-Mail-Stil (Issue #5): Icon mit kleinerem Text darunter statt Icon+Text nebeneinander
    /// in einer `.bordered`/`.borderedProminent`-Kapsel.
    @ViewBuilder
    private func toolButton(for tool: CanvasTool) -> some View {
        iconButton(systemImage: tool.systemImageName, label: tool.displayName, isActive: canvasStore.currentTool == tool) {
            canvasStore.selectTool(tool)
        }
    }

    /// Gemeinsamer Baustein für alle Icon+Text-Toolbar-Buttons (Werkzeuge + Exportieren, Issue #25).
    ///
    /// Grösse kommt aus `AppSettings.toolbarSize` statt fester Werte (Issue #25: "Tableiste zu
    /// klein", jetzt in den Einstellungen anpassbar).
    ///
    /// Auswahl-Optik (Issue #25, Nachbesserung): ein solider blauer Kreis nur hinter dem Icon
    /// wurde als "optisch nicht schön" empfunden. Jetzt eine sanft eingefärbte, abgerundete
    /// Fläche hinter Icon UND Text zusammen (`Color.accentColor.opacity(0.15)`, wie macOS'
    /// eigene dezente Selektions-Hervorhebungen z.B. in Listen/Segmented Controls) statt einer
    /// harten Vollfarbe — Icon/Text färben sich zusätzlich in der Akzentfarbe statt weiss auf blau.
    ///
    /// `.contentShape(Rectangle())` auf dem gesamten Label: ohne das reagiert ein `.plain`-Button
    /// mit nicht-opakem Inhalt (der Hintergrund ist im inaktiven Zustand `Color.clear`) nur auf
    /// Klicks innerhalb der tatsächlich gezeichneten Pixel (SF-Symbol-Glyph, Text) — der Leerraum
    /// dazwischen war klickunempfindlich.
    @ViewBuilder
    private func iconButton(systemImage: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        let size = toolbarSize
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: size.symbolFontSize, weight: .medium))
                    .frame(width: size.iconDiameter, height: size.iconDiameter)
                    .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                Text(label)
                    .font(.system(size: size.textFontSize))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .frame(width: size.buttonWidth)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

#Preview {
    ContentView(document: StitchDesignDocument())
}
