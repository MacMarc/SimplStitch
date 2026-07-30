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
    // Issue #29 (Punkt 7): liest die appweite Standard-Garnliste (AppSettings.defaultThreadPaletteID,
    // Einstellungen > Allgemein) für das einmalige Seeding neuer Dokumente in onAppear.
    @Query private var appSettingsList: [AppSettings]

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
        // Issue #26 (Opus-Konsultation, Nachbesserung 2): die linke Seitenleiste war seit Phase 8a
        // reine, nie verdrahtete Platzhalter-UI (zeigte immer nur "Noch keine Projekte", ohne
        // @Query/Auswahl/Funktion) — kein Produkt-Requirement dafür in CLAUDE.md auffindbar. Die
        // App ist über `DocumentGroup` ohnehin dokumentbasiert (jedes Projekt = eigenes Fenster,
        // "Zuletzt geöffnet" kommt nativ vom Ablage-Menü) — ein zweiter Navigator hier hätte nur
        // den Canvas beengt, ohne echten Nutzen. Entfernt: `CanvasView` ist jetzt direkt der
        // Wurzel-Inhalt des Fensters statt einer `NavigationSplitView`-Detail-Spalte.
        CanvasView(store: canvasStore)
            .toolbar {
                // Issue #26 (Opus-Konsultation, Nachbesserung 2): sieben einzelne, handgebaute
                // Icon+Beschriftungs-Buttons (vorherige Fassung) wirkten als lose Ansammlung statt
                // "aus einem Guss", da `.buttonStyle(.plain)` explizit jede native Toolbar-Chrome
                // (Hover/Pressed/Fokus/Inaktiv-Dimmen) abbestellt. Ein einziger nativer segmentierter
                // `Picker` ist dagegen EIN zusammenhängendes Element mit nativer Auswahl-Optik —
                // löst "nicht aus einem Guss" strukturell, nicht nur kosmetisch. Bewusste,
                // besprochene Abweichung von der sonst geltenden CLAUDE.md-Regel "Icon + Text-Label
                // (kein Icon-Raten)": Beschriftung nur noch als Mouseover-Tooltip (`.help`), nicht
                // mehr permanent sichtbarer Text — siehe CLAUDE.md-Eintrag zu Issue #26,
                // Nachbesserung 2 für die Begründung/Nutzerentscheidung.
                ToolbarItem(placement: .principal) {
                    Picker(
                        "canvas.tool.picker",
                        selection: Binding(
                            get: { canvasStore.currentTool },
                            set: { canvasStore.selectTool($0) }
                        )
                    ) {
                        ForEach(CanvasTool.allCases) { tool in
                            Image(systemName: tool.systemImageName)
                                .help(Text(tool.displayName))
                                .tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.large)
                }

                // Exportieren/Inspektor sind Aktionen bzw. ein View-Toggle, keine Werkzeug-Modi —
                // bewusst NICHT im selben Segmented-Control, sondern als eigenständige, schlichte
                // Icon-Buttons am Rand (führende Werkzeug-Auswahl / abschliessende Aktionen ist das
                // übliche Muster nativer Dokument-Toolbars, z.B. Vorschau/Notizen).
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isExportDialogPresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help(Text("export.toolbar.button"))
                    .accessibilityLabel(Text("export.toolbar.button"))
                }

                ToolbarItem {
                    Button {
                        isInspectorPresented.toggle()
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(Text("inspector.toggle"))
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
            // Issue #10: Hintergrundbild wählen — eigenes `.fileImporter`-Sheet (Bild- statt
            // Stickdatei-Typen), Bytes gehen direkt an `StitchDesignDocument.setBackgroundImage`,
            // das sie bis zum nächsten Speichern hält (siehe dortiger Kommentar).
            .fileImporter(
                isPresented: Binding(
                    get: { canvasStore.isBackgroundImagePickerPresented },
                    set: { canvasStore.isBackgroundImagePickerPresented = $0 }
                ),
                allowedContentTypes: [.png, .jpeg, .heic, .image],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importBackgroundImage(at: url)
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                }
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
            .onAppear {
                canvasStore.undoManager = undoManager
                // Issue #29 (Punkt 7): Standard-Garnliste aus den Einstellungen als Startwert nur für
                // wirklich neue Dokumente übernehmen — geöffnete Projekte bringen ihren Wert (auch
                // "keiner gewählt") bereits aus content.svg mit und sollen ihn behalten. Die
                // Projekt-Einstellung selbst überschreibt diesen Startwert danach wie gehabt.
                if document.isNewDocument {
                    canvasStore.defaultThreadPaletteID = appSettingsList.first?.defaultThreadPaletteID
                }
                // Issue #10: Bild-Bytes leben im Dokument (nicht in StitchProject/SwiftData, siehe
                // dortiger Kommentar) — CanvasStore braucht sie trotzdem fürs Zeichnen.
                canvasStore.backgroundImageData = document.backgroundImageData
            }
            .onChange(of: document.backgroundImageData) { _, newValue in
                canvasStore.backgroundImageData = newValue
            }
            .onChange(of: canvasStore.backgroundImageRemovalRequested) { _, requested in
                guard requested else { return }
                document.removeBackgroundImage()
                canvasStore.backgroundImageRemovalRequested = false
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

    /// Issue #10: liest die gewählte Bilddatei und reicht sie an `StitchDesignDocument` weiter —
    /// synchron wie `importSVGFile`, keine Bridge/kein Subprocess nötig, nur Foundation-I/O.
    private func importBackgroundImage(at url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            document.setBackgroundImage(fileName: url.lastPathComponent, data: data)
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

}

#Preview {
    ContentView(document: StitchDesignDocument())
}
