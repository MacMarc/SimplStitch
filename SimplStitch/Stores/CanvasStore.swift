//
//  CanvasStore.swift
//  SimplStitch
//
//  Zeichenfläche: Zoom/Pan-Zustand und die Umrechnung zwischen Design-
//  Koordinaten (Millimeter, Ursprung oben-links — wie content.svg, Phase 4)
//  und View-Koordinaten (Punkte). Ausserdem Werkzeugauswahl und das Erzeugen
//  neuer Formen per Klick-Drag (5b) sowie Selektion, Verschieben und
//  PowerPoint-artige Handles zum Skalieren/Drehen/Eckenrunden (5c). Text-Objekte
//  entstehen über dasselbe Klick-Drag-Verfahren (Rechteck-Ziel-Box, bei blossem
//  Klick eine Default-Grösse) und wechseln danach direkt in den Bearbeitungsmodus
//  (5d) — CanvasView zeigt dafür eine TextField-Overlay über der Box.
//
//  `objects`/`canvasSizeMillimeters` sind computed properties über ein
//  `StitchProject` (Phase 8a) — kein eigenes Array mehr. Da `project` ein
//  SwiftData-`@Model` ist, dessen Properties selbst Teil des Observation-
//  Tracking sind, bemerken SwiftUI-Views das trotz des Zwischenschritts über
//  den computed getter (Observation trackt zur Laufzeit den tatsächlichen
//  Zugriffspfad, nicht nur direkt als `@Observable` markierte Properties).
//
//  Scope-Hinweis (5c): Verzerren (Skew) hat trotz vorhandener
//  skewXDegrees/skewYDegrees-Felder im Modell noch keinen interaktiven Griff
//  — Rendering wendet Skew ebenfalls noch nicht an. Folgt als eigener Schritt,
//  sobald das Interaktionsmodell dafür (z.B. Modifier-Taste auf einem
//  Skalier-Griff) entschieden ist.
//
//  Live-Stichvorschau (6e): `stitchPreview` hält die zuletzt generierten Stiche
//  für das selektierte Objekt, `refreshStitchPreview()` stösst eine debouncte,
//  abbrechbare Neugenerierung über StitchGenerationService an. Ruft die
//  echte Python-Bridge auf — ein neuer PythonBridge-Subprocess pro CanvasStore
//  ist für den aktuellen Scope (eine Zeichenfläche gleichzeitig) ausreichend.
//

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class CanvasStore {
    static let minZoomScale: CGFloat = 0.1
    static let maxZoomScale: CGFloat = 8

    private(set) var zoomScale: CGFloat
    private(set) var panOffset: CGSize

    var canvasSizeMillimeters: CGSize {
        get { CGSize(width: project.canvasWidthMillimeters, height: project.canvasHeightMillimeters) }
        set {
            project.canvasWidthMillimeters = newValue.width
            project.canvasHeightMillimeters = newValue.height
        }
    }

    private let project: StitchProject
    private let stitchGenerationService: StitchGenerationServicing

    init(
        project: StitchProject,
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        stitchGenerationService: StitchGenerationServicing = StitchGenerationService(bridge: PythonBridge())
    ) {
        self.project = project
        self.zoomScale = min(max(zoomScale, Self.minZoomScale), Self.maxZoomScale)
        self.panOffset = panOffset
        self.stitchGenerationService = stitchGenerationService
    }

    /// Komfort-Initializer für Tests/Previews ohne eigenes `StitchProject` — erzeugt intern ein
    /// unbenanntes Projekt mit der gewünschten Zeichenflächengrösse. Produktivcode (`ContentView`)
    /// nutzt `init(project:...)` mit dem echten, aus dem Dokument geladenen `StitchProject`.
    convenience init(
        canvasSizeMillimeters: CGSize,
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        stitchGenerationService: StitchGenerationServicing = StitchGenerationService(bridge: PythonBridge())
    ) {
        let project = StitchProject(
            name: "",
            lastKnownPath: "",
            canvasWidthMillimeters: canvasSizeMillimeters.width,
            canvasHeightMillimeters: canvasSizeMillimeters.height
        )
        self.init(project: project, zoomScale: zoomScale, panOffset: panOffset, stitchGenerationService: stitchGenerationService)
    }

    func setZoomScale(_ newValue: CGFloat) {
        zoomScale = min(max(newValue, Self.minZoomScale), Self.maxZoomScale)
    }

    func zoom(by factor: CGFloat) {
        setZoomScale(zoomScale * factor)
    }

    func pan(by delta: CGSize) {
        panOffset.width += delta.width
        panOffset.height += delta.height
    }

    func resetView() {
        zoomScale = 1
        panOffset = .zero
    }

    /// Skaliert und zentriert die Zeichenfläche so, dass sie vollständig im Viewport sichtbar ist.
    func zoomToFit(viewportSize: CGSize, margin: CGFloat = 24) {
        guard canvasSizeMillimeters.width > 0, canvasSizeMillimeters.height > 0,
              viewportSize.width > margin * 2, viewportSize.height > margin * 2 else {
            resetView()
            return
        }
        let availableWidth = viewportSize.width - margin * 2
        let availableHeight = viewportSize.height - margin * 2
        let scale = min(availableWidth / canvasSizeMillimeters.width, availableHeight / canvasSizeMillimeters.height)
        setZoomScale(scale)

        let scaledCanvasSize = CGSize(
            width: canvasSizeMillimeters.width * zoomScale,
            height: canvasSizeMillimeters.height * zoomScale
        )
        panOffset = CGSize(
            width: (viewportSize.width - scaledCanvasSize.width) / 2,
            height: (viewportSize.height - scaledCanvasSize.height) / 2
        )
    }

    // MARK: Koordinatensystem

    func viewPoint(fromDesign designPoint: CGPoint) -> CGPoint {
        CGPoint(x: designPoint.x * zoomScale + panOffset.width, y: designPoint.y * zoomScale + panOffset.height)
    }

    func designPoint(fromView viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: (viewPoint.x - panOffset.width) / zoomScale, y: (viewPoint.y - panOffset.height) / zoomScale)
    }

    /// Rechteck der Zeichenfläche in View-Koordinaten (für Hintergrund-/Rahmenzeichnung).
    var canvasRectInView: CGRect {
        CGRect(
            origin: viewPoint(fromDesign: .zero),
            size: CGSize(width: canvasSizeMillimeters.width * zoomScale, height: canvasSizeMillimeters.height * zoomScale)
        )
    }

    // MARK: Formen (5b)

    static let minimumShapeSize: Double = 1

    private(set) var currentTool: CanvasTool = .select

    private(set) var objects: [DesignObject] {
        get { project.objects }
        set { project.objects = newValue }
    }

    private(set) var isDrafting = false
    private(set) var draftShapeRect: CGRect?
    private(set) var draftPathPoints: [CGPoint] = []

    private var draftStartPoint: CGPoint?

    func selectTool(_ tool: CanvasTool) {
        currentTool = tool
        if tool != .select {
            selectedObjectIDs = []
        }
    }

    /// Startet das Zeichnen einer neuen Form am gegebenen Punkt (Design-Koordinaten). Keine Wirkung beim Auswahl-Werkzeug.
    func beginDraft(atDesignPoint point: CGPoint) {
        guard currentTool != .select else { return }
        isDrafting = true
        draftStartPoint = point
        switch currentTool {
        case .rectangle, .circle, .star, .text:
            draftShapeRect = CGRect(origin: point, size: .zero)
        case .path:
            draftPathPoints = [point]
        case .select:
            break
        }
    }

    /// Aktualisiert die Form während des Ziehens (Design-Koordinaten).
    func updateDraft(toDesignPoint point: CGPoint) {
        guard isDrafting, let start = draftStartPoint else { return }
        switch currentTool {
        case .rectangle, .circle, .star, .text:
            draftShapeRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
        case .path:
            draftPathPoints.append(point)
        case .select:
            break
        }
    }

    /// Schliesst das Zeichnen ab: erzeugt bei ausreichender Grösse ein neues DesignObject,
    /// verwirft den Entwurf und wechselt zurück zum Auswahl-Werkzeug.
    @discardableResult
    func commitDraft() -> DesignObject? {
        defer {
            isDrafting = false
            draftStartPoint = nil
            draftShapeRect = nil
            draftPathPoints = []
        }
        guard isDrafting else { return nil }

        let newObject: DesignObject?
        switch currentTool {
        case .select:
            newObject = nil
        case .rectangle:
            newObject = makeShapeObject(kind: .rectangle)
        case .circle:
            newObject = makeShapeObject(kind: .circle)
        case .star:
            newObject = makeShapeObject(kind: .star)
        case .path:
            newObject = makePathObject()
        case .text:
            newObject = makeTextObject()
        }

        if let newObject {
            newObject.project = project
            objects.append(newObject)
        }
        currentTool = .select
        selectedObjectIDs = newObject.map { [$0.id] } ?? []
        if newObject?.kind == .text {
            editingTextObjectID = newObject?.id
        }
        refreshStitchPreview()
        return newObject
    }

    private func makeShapeObject(kind: DesignObjectKind) -> DesignObject? {
        guard let rect = draftShapeRect,
              rect.width >= Self.minimumShapeSize, rect.height >= Self.minimumShapeSize else {
            return nil
        }
        let object = DesignObject(
            name: nextDefaultName(for: currentTool),
            kind: kind,
            positionX: rect.minX,
            positionY: rect.minY,
            width: rect.width,
            height: rect.height
        )
        object.zIndex = objects.count
        if kind == .star {
            object.starPointCount = 5
        }
        // Issue #11: Stichtyp wird anhand der Geometrie vorgeschlagen (schmal+länglich -> Satin,
        // sonst Tatami-Füllung), statt immer fest Tatami zu setzen — im Inspector überschreibbar.
        assignDefaultStitchSettings(to: object, stitchType: StitchType.suggested(forShapeWidth: rect.width, height: rect.height))
        return object
    }

    /// Formen ohne Sticheinstellungen wurden bislang beim Export stillschweigend übersprungen
    /// (`FileExportService.stitchableObjects` filtert auf `stitchSettings != nil`) — ohne einen
    /// Besuch im Objekt-Inspektor blieb eine frisch gezeichnete Form dauerhaft unstickbar. Neue
    /// Objekte bekommen daher sofort sinnvolle Default-Einstellungen (überschreibbar im Inspector).
    private func assignDefaultStitchSettings(to object: DesignObject, stitchType: StitchType) {
        let settings = StitchSettings(stitchType: stitchType)
        settings.designObject = object
        object.stitchSettings = settings
    }

    private func makePathObject() -> DesignObject? {
        guard draftPathPoints.count >= 2 else { return nil }
        let xValues = draftPathPoints.map(\.x)
        let yValues = draftPathPoints.map(\.y)
        let minX = xValues.min() ?? 0
        let minY = yValues.min() ?? 0
        let maxX = xValues.max() ?? 0
        let maxY = yValues.max() ?? 0

        let object = DesignObject(
            name: nextDefaultName(for: .path),
            kind: .path,
            positionX: minX,
            positionY: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        object.zIndex = objects.count
        object.pathData = Self.pathData(from: draftPathPoints)
        assignDefaultStitchSettings(to: object, stitchType: .straight)
        return object
    }

    /// Grösse einer neuen Textbox bei einem blossen Klick (kein/kaum Drag) — Ziehen mit dem Text-Werkzeug
    /// legt stattdessen die Box wie bei den Formwerkzeugen fest.
    static let defaultTextBoxSize = CGSize(width: 40, height: 12)
    static let defaultTextFontSize: Double = 8

    private func makeTextObject() -> DesignObject? {
        guard let start = draftStartPoint else { return nil }
        let rect: CGRect
        if let draft = draftShapeRect, draft.width >= Self.minimumShapeSize, draft.height >= Self.minimumShapeSize {
            rect = draft
        } else {
            rect = CGRect(origin: start, size: Self.defaultTextBoxSize)
        }
        let object = DesignObject(
            name: nextDefaultName(for: .text),
            kind: .text,
            positionX: rect.minX,
            positionY: rect.minY,
            width: rect.width,
            height: rect.height
        )
        object.zIndex = objects.count
        object.text = ""
        object.fontSize = Self.defaultTextFontSize
        return object
    }

    private func nextDefaultName(for tool: CanvasTool) -> String {
        let count = objects.filter { $0.kind == tool.shapeKind }.count + 1
        return "\(tool.displayName) \(count)"
    }

    /// Baut einen einfachen "M x,y L x,y …"-Pfadstring (SVG-Syntax) aus den Freihand-Punkten.
    private static func pathData(from points: [CGPoint]) -> String {
        guard let first = points.first else { return "" }
        var d = "M\(fmt(first.x)),\(fmt(first.y))"
        for point in points.dropFirst() {
            d += " L\(fmt(point.x)),\(fmt(point.y))"
        }
        return d
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    // MARK: Selektion & Handles (5c, Mehrfachauswahl & Gruppierung: Issue #16)

    /// Alle aktuell selektierten Objekte — Quelle der Wahrheit für die Selektion. Mehrfachauswahl
    /// entsteht per Shift-Klick/Gummiband-Auswahl auf dem Canvas oder Cmd/Shift-Klick im Ebenen-
    /// Panel (natives `List(selection:)`-Verhalten). Klick auf ein Gruppenmitglied selektiert immer
    /// die ganze Gruppe (siehe `toggleSelection`/`beginTransformDrag`) — die Selektion besteht daher
    /// stets aus vollständigen Gruppen und/oder einzelnen ungruppierten Objekten, nie einem Teil einer Gruppe.
    private(set) var selectedObjectIDs: Set<UUID> = []

    var selectedObjects: [DesignObject] {
        objects.filter { selectedObjectIDs.contains($0.id) }
    }

    /// Nicht-nil nur bei einer Einzelauswahl (ein ungruppiertes Objekt) — von Objekt-Inspektor,
    /// Sticheinstellungen, Z-Order-Buttons etc. genutzt, die pro Definition nur für genau ein
    /// Objekt sinnvoll sind. Bei Gruppen-/Mehrfachauswahl bewusst nil (siehe `selectedGroupID`
    /// für den Gruppen-Fall).
    var selectedObject: DesignObject? {
        guard selectedObjectIDs.count == 1, let id = selectedObjectIDs.first else { return nil }
        return objects.first { $0.id == id }
    }

    var selectedObjectID: UUID? { selectedObject?.id }

    /// Nicht-nil nur, wenn die aktuelle Selektion exakt aus allen Mitgliedern EINER Gruppe besteht
    /// (nicht bei Einzelselektion eines Mitglieds oder einer Mehrfachauswahl über Gruppengrenzen
    /// hinweg — beides kommt über die Panel-Mehrfachauswahl theoretisch vor, zeigt dann aber
    /// bewusst weder Gruppen- noch Einzelobjekt-Handles).
    var selectedGroupID: UUID? {
        let selected = selectedObjects
        guard selected.count > 1 else { return nil }
        let groupIDs = Set(selected.compactMap(\.groupID))
        guard groupIDs.count == 1, let groupID = groupIDs.first else { return nil }
        guard objects.filter({ $0.groupID == groupID }).count == selected.count else { return nil }
        return groupID
    }

    /// Achsenparalleler Rahmen um alle Mitglieder der aktuell selektierten Gruppe, inkl. deren
    /// individueller Rotation (umschliesst die gedrehten Eckpunkte jedes Mitglieds) — wie der
    /// Gruppenrahmen in PowerPoint/Illustrator, der selbst nicht mitrotiert, auch wenn einzelne
    /// Mitglieder gedreht sind.
    var selectedGroupBounds: CGRect? {
        guard let groupID = selectedGroupID else { return nil }
        return Self.groupBounds(of: objects.filter { $0.groupID == groupID })
    }

    static func groupBounds(of members: [DesignObject]) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for member in members {
            for corner in rotatedCorners(of: member) {
                minX = min(minX, corner.x)
                minY = min(minY, corner.y)
                maxX = max(maxX, corner.x)
                maxY = max(maxY, corner.y)
            }
        }
        guard minX.isFinite else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func rotatedCorners(of object: DesignObject) -> [CGPoint] {
        let objectCenter = center(of: object)
        let halfW = object.width / 2
        let halfH = object.height / 2
        let localCorners = [
            CGPoint(x: -halfW, y: -halfH), CGPoint(x: halfW, y: -halfH),
            CGPoint(x: halfW, y: halfH), CGPoint(x: -halfW, y: halfH),
        ]
        return localCorners.map { local in
            let rotated = rotatedVector(local, byDegrees: object.rotationDegrees)
            return CGPoint(x: objectCenter.x + rotated.x, y: objectCenter.y + rotated.y)
        }
    }

    func selectObject(_ id: UUID?) {
        selectedObjectIDs = id.map { [$0] } ?? []
        refreshStitchPreview()
    }

    /// Ersetzt die Selektion vollständig — genutzt vom Ebenen-Panel, das über `List(selection:)`
    /// eine eigene (Cmd/Shift-Klick-fähige) Mehrfachauswahl mitbringt und deren Row-Tags
    /// (Objekt-IDs bzw. Gruppen-IDs) selbst in konkrete Mitglieds-IDs übersetzt.
    func replaceSelection(_ ids: Set<UUID>) {
        selectedObjectIDs = ids
        refreshStitchPreview()
    }

    /// Shift-Klick auf dem Canvas: schaltet ein Objekt (bzw. bei einem Gruppenmitglied die ganze
    /// Gruppe) in der Selektion um, statt sie zu ersetzen.
    func toggleSelection(of id: UUID) {
        guard let object = objects.first(where: { $0.id == id }) else { return }
        let idsToToggle: Set<UUID>
        if let groupID = object.groupID {
            idsToToggle = Set(objects.filter { $0.groupID == groupID }.map(\.id))
        } else {
            idsToToggle = [id]
        }
        if idsToToggle.isSubset(of: selectedObjectIDs) {
            selectedObjectIDs.subtract(idsToToggle)
        } else {
            selectedObjectIDs.formUnion(idsToToggle)
        }
        refreshStitchPreview()
    }

    // MARK: Gummiband-Auswahl (Marquee)

    /// Rechteck der laufenden Gummiband-Auswahl in Design-Koordinaten, während eines Shift-Drags
    /// über leere Canvas-Fläche — nil ausserhalb einer solchen Geste.
    private(set) var marqueeRect: CGRect?
    private var marqueeStartPoint: CGPoint?

    func beginMarqueeSelection(atDesignPoint point: CGPoint) {
        marqueeStartPoint = point
        marqueeRect = CGRect(origin: point, size: .zero)
    }

    func updateMarqueeSelection(toDesignPoint point: CGPoint) {
        guard let start = marqueeStartPoint else { return }
        marqueeRect = CGRect(
            x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(point.x - start.x), height: abs(point.y - start.y)
        )
    }

    /// Fügt alle Objekte, deren (unrotierte) Bounding-Box das Gummiband-Rechteck schneidet, zur
    /// Selektion hinzu — bei Treffern auf ein Gruppenmitglied wird die ganze Gruppe ergänzt.
    /// Vereinfachung: unrotierte Bounding-Box, wie beim übrigen Hit-Testing (5c) — reicht für die
    /// Grobauswahl per Gummiband.
    func endMarqueeSelection() {
        defer { marqueeRect = nil; marqueeStartPoint = nil }
        guard let rect = marqueeRect else { return }
        var idsToAdd: Set<UUID> = []
        for object in objects where object.isVisible {
            let bounds = CGRect(x: object.positionX, y: object.positionY, width: object.width, height: object.height)
            guard bounds.intersects(rect) else { continue }
            if let groupID = object.groupID {
                idsToAdd.formUnion(objects.filter { $0.groupID == groupID }.map(\.id))
            } else {
                idsToAdd.insert(object.id)
            }
        }
        selectedObjectIDs.formUnion(idsToAdd)
        refreshStitchPreview()
    }

    // MARK: Gruppierung

    /// Fasst die aktuell selektierten Objekte (mind. 2) zu einer neuen Gruppe zusammen. Objekte,
    /// die bereits einer anderen Gruppe angehören, werden daraus gelöst — verschachtelte Gruppen
    /// sind bewusst nicht unterstützt (siehe `DesignObject.groupID`-Kommentar). Die zIndex-Werte
    /// der Mitglieder werden zusammenhängend gemacht, damit die Gruppe im Ebenen-Panel als ein
    /// Block dargestellt werden kann (siehe `LayersPanelView`).
    func groupSelectedObjects() {
        let members = selectedObjects
        guard members.count > 1 else { return }
        let groupID = UUID()
        for member in members {
            member.groupID = groupID
        }
        makeContiguous(members)
    }

    /// Löst die Gruppierung der aktuell selektierten Objekte auf (Selektion bleibt erhalten).
    func ungroupSelectedObjects() {
        for object in selectedObjects {
            object.groupID = nil
        }
    }

    /// Löst eine bestimmte Gruppe auf, unabhängig von der aktuellen Selektion — genutzt vom
    /// Ebenen-Panel für die "Gruppierung aufheben"-Aktion auf einer (evtl. nicht selektierten) Gruppenzeile.
    func ungroup(groupID: UUID) {
        for object in objects where object.groupID == groupID {
            object.groupID = nil
        }
    }

    /// Ordnet die zIndex-Werte so um, dass `members` als zusammenhängender Block an der vordersten
    /// aktuellen Position der Gruppe liegen (relative Reihenfolge der Mitglieder untereinander bleibt erhalten).
    private func makeContiguous(_ members: [DesignObject]) {
        let memberIDs = Set(members.map(\.id))
        var ordered = objectsFrontToBack
        let memberFrontToBack = ordered.filter { memberIDs.contains($0.id) }
        let insertIndex = ordered.firstIndex { memberIDs.contains($0.id) } ?? 0
        ordered.removeAll { memberIDs.contains($0.id) }
        ordered.insert(contentsOf: memberFrontToBack, at: min(insertIndex, ordered.count))
        reassignZIndices(frontToBack: ordered)
    }

    /// Übernimmt eine vollständige, neu geordnete vorne-nach-hinten-Liste (z.B. nach Drag im
    /// Ebenen-Panel, wo eine Gruppen-Zeile als zusammenhängender Block bewegt wird) und vergibt
    /// die zIndex-Werte neu.
    func applyFrontToBackOrder(_ ordered: [DesignObject]) {
        reassignZIndices(frontToBack: ordered)
    }

    /// Oberstes sichtbares Objekt unter dem gegebenen Punkt (Design-Koordinaten), oder nil.
    func object(atDesignPoint point: CGPoint) -> DesignObject? {
        for object in objectsFrontToBack where object.isVisible {
            let local = Self.localDesignPoint(point, in: object)
            if Self.objectContains(object, localPoint: local) {
                return object
            }
        }
        return nil
    }

    private static func objectContains(_ object: DesignObject, localPoint point: CGPoint) -> Bool {
        switch object.kind {
        case .rectangle, .circle, .star:
            return object.designSpacePath().contains(point)
        case .path, .text:
            // Vereinfachung: Freihand-Pfade (Strich statt Fläche) und Text (Glyphen statt exaktem
            // Pfad) werden per Bounding-Box getroffen — reicht fürs Selektieren.
            let bounds = CGRect(x: object.positionX, y: object.positionY, width: object.width, height: object.height)
            return bounds.insetBy(dx: -1, dy: -1).contains(point)
        }
    }

    /// Positionen aller Griffe eines Objekts in Design-Koordinaten, bereits um `rotationDegrees` gedreht
    /// (folgen also der sichtbaren Ausrichtung, wie bei PowerPoint-Handles).
    func handlePositions(for object: DesignObject) -> [CanvasHandleKind: CGPoint] {
        let halfW = object.width / 2
        let halfH = object.height / 2
        let center = Self.center(of: object)

        var localPoints: [CanvasHandleKind: CGPoint] = [:]
        for kind in CanvasHandleKind.resizeCases {
            guard let sign = kind.resizeSign else { continue }
            localPoints[kind] = CGPoint(x: sign.x * halfW, y: sign.y * halfH)
        }
        localPoints[.rotate] = CGPoint(x: 0, y: -halfH - Self.rotationHandleOffset)
        if object.kind == .rectangle {
            let maxRadius = min(object.width, object.height) / 2
            let radius = min(max(object.cornerRadius, 0), maxRadius)
            localPoints[.cornerRadius] = CGPoint(x: -halfW + radius, y: -halfH)
        }

        var result: [CanvasHandleKind: CGPoint] = [:]
        for (kind, local) in localPoints {
            let rotated = Self.rotatedVector(local, byDegrees: object.rotationDegrees)
            result[kind] = CGPoint(x: center.x + rotated.x, y: center.y + rotated.y)
        }
        return result
    }

    /// Griff unter dem gegebenen Punkt (Design-Koordinaten), innerhalb einer festen Bildschirm-Toleranz
    /// (umgerechnet in Design-Einheiten über den aktuellen Zoom, damit die Trefferfläche bei jedem Zoom gleich gross wirkt).
    func handle(atDesignPoint point: CGPoint, for object: DesignObject) -> CanvasHandleKind? {
        let tolerance = Self.handleHitRadiusPoints / zoomScale
        for (kind, handlePoint) in handlePositions(for: object) {
            let dx = point.x - handlePoint.x
            let dy = point.y - handlePoint.y
            if (dx * dx + dy * dy).squareRoot() <= tolerance {
                return kind
            }
        }
        return nil
    }

    static let rotationHandleOffset: Double = 8
    static let handleHitRadiusPoints: CGFloat = 7

    private struct TransformSnapshot {
        var positionX: Double
        var positionY: Double
        var width: Double
        var height: Double
        var rotationDegrees: Double
        var cornerRadius: Double

        init(object: DesignObject) {
            positionX = object.positionX
            positionY = object.positionY
            width = object.width
            height = object.height
            rotationDegrees = object.rotationDegrees
            cornerRadius = object.cornerRadius
        }
    }

    /// Snapshot für eine Gruppen-Transformation: der achsenparallele Gruppenrahmen zu Beginn des
    /// Drags (Pivot für Skalieren/Drehen) plus je ein `TransformSnapshot` pro Mitglied.
    private struct GroupTransformSnapshot {
        var bounds: CGRect
        var memberSnapshots: [UUID: TransformSnapshot]
    }

    private enum ActiveTransform {
        case single(objectID: UUID, snapshot: TransformSnapshot)
        case skew(objectID: UUID, snapshot: TransformSnapshot)
        case group(GroupTransformSnapshot)
    }

    private var activeTransform: ActiveTransform?
    private var activeHandle: CanvasHandleKind?
    private var transformDragStartPoint: CGPoint?

    /// Startet das Verschieben (handle == nil) oder einen Griff-Drag am gegebenen Punkt (Design-
    /// Koordinaten). Gehört das Objekt zu einer Gruppe, wird die ganze Gruppe selektiert und als
    /// Einheit transformiert (PowerPoint/Illustrator-Verhalten) — sonst nur das einzelne Objekt.
    /// Gesperrte Objekte (`isLocked`) lassen sich selektieren, aber nicht verändern; bei einer
    /// Gruppe blockiert bereits ein einziges gesperrtes Mitglied die gesamte Gruppen-Transformation.
    func beginTransformDrag(object: DesignObject, handle: CanvasHandleKind?, atDesignPoint point: CGPoint) {
        if let groupID = object.groupID {
            selectedObjectIDs = Set(objects.filter { $0.groupID == groupID }.map(\.id))
            beginGroupTransformDrag(handle: handle, atDesignPoint: point)
            return
        }
        selectedObjectIDs = [object.id]
        guard !object.isLocked else { return }
        activeHandle = handle
        transformDragStartPoint = point
        activeTransform = .single(objectID: object.id, snapshot: TransformSnapshot(object: object))
    }

    /// Startet einen Verzerren-Drag (Issue #9) — ⌥+Drag auf einem Kanten-Griff (nicht Ecke) verzerrt
    /// statt zu skalieren (siehe `CanvasHandleKind.isEdgeHandle`). Bewusst nur für Einzelobjekte:
    /// eine Gruppe als Ganzes zu verzerren wäre ein deutlich grösserer geometrischer Schritt (siehe
    /// dieselbe Vereinfachung bei `applyGroupResize`) und ist nicht Teil dieses Schritts.
    func beginSkewDrag(object: DesignObject, handle: CanvasHandleKind, atDesignPoint point: CGPoint) {
        selectedObjectIDs = [object.id]
        guard handle.isEdgeHandle, !object.isLocked else { return }
        activeHandle = handle
        transformDragStartPoint = point
        activeTransform = .skew(objectID: object.id, snapshot: TransformSnapshot(object: object))
    }

    /// Startet einen Griff-Drag auf dem Gruppenrahmen der aktuell selektierten Gruppe
    /// (`selectedGroupBounds`) — `handle == nil` bedeutet Verschieben der ganzen Gruppe.
    func beginGroupTransformDrag(handle: CanvasHandleKind?, atDesignPoint point: CGPoint) {
        let members = selectedObjects
        guard !members.isEmpty, !members.contains(where: \.isLocked) else { return }
        activeHandle = handle
        transformDragStartPoint = point
        let snapshots = Dictionary(uniqueKeysWithValues: members.map { ($0.id, TransformSnapshot(object: $0)) })
        activeTransform = .group(GroupTransformSnapshot(bounds: Self.groupBounds(of: members), memberSnapshots: snapshots))
    }

    func updateTransformDrag(toDesignPoint point: CGPoint) {
        guard let start = transformDragStartPoint, let transform = activeTransform else { return }

        switch transform {
        case .single(let objectID, let snapshot):
            guard let object = objects.first(where: { $0.id == objectID }) else { return }
            guard let handle = activeHandle else {
                object.positionX = snapshot.positionX + (point.x - start.x)
                object.positionY = snapshot.positionY + (point.y - start.y)
                return
            }
            switch handle {
            case .rotate:
                applyRotation(to: object, snapshot: snapshot, dragPoint: point)
            case .cornerRadius:
                applyCornerRadius(to: object, snapshot: snapshot, dragPoint: point)
            default:
                applyResize(to: object, handle: handle, snapshot: snapshot, dragPoint: point)
            }
        case .skew(let objectID, let snapshot):
            guard let object = objects.first(where: { $0.id == objectID }), let handle = activeHandle else { return }
            applySkew(to: object, handle: handle, snapshot: snapshot, dragPoint: point)
        case .group(let snapshot):
            guard let handle = activeHandle else {
                applyGroupMove(snapshot: snapshot, start: start, dragPoint: point)
                return
            }
            switch handle {
            case .rotate:
                applyGroupRotation(snapshot: snapshot, dragPoint: point)
            case .cornerRadius:
                break // Gruppen haben keinen Eckenradius-Griff.
            default:
                applyGroupResize(handle: handle, snapshot: snapshot, dragPoint: point)
            }
        }
    }

    func endTransformDrag() {
        activeTransform = nil
        activeHandle = nil
        transformDragStartPoint = nil
        refreshStitchPreview()
    }

    private func applyGroupMove(snapshot: GroupTransformSnapshot, start: CGPoint, dragPoint: CGPoint) {
        let dx = dragPoint.x - start.x
        let dy = dragPoint.y - start.y
        for (id, memberSnapshot) in snapshot.memberSnapshots {
            guard let member = objects.first(where: { $0.id == id }) else { continue }
            member.positionX = memberSnapshot.positionX + dx
            member.positionY = memberSnapshot.positionY + dy
        }
    }

    /// Skaliert jedes Mitglied relativ zum fixen Anker-Eck-/Kantenpunkt des Gruppenrahmens.
    /// Vereinfachung: skaliert Position-Offset und Grösse jedes Mitglieds unabhängig von dessen
    /// eigener Rotation (kein Scher-/Verzerrungs-Anteil für bereits gedrehte Mitglieder, das würde
    /// echte Skew-Unterstützung brauchen — siehe Issue #9). Reicht für den überwiegenden Fall
    /// unrotierter oder gleichmässig skalierter Gruppenmitglieder.
    private func applyGroupResize(handle: CanvasHandleKind, snapshot: GroupTransformSnapshot, dragPoint: CGPoint) {
        guard let sign = handle.resizeSign else { return }
        let bounds = snapshot.bounds
        let halfW = bounds.width / 2
        let halfH = bounds.height / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        var scaleX = 1.0
        if sign.x != 0, halfW > 0 {
            let anchorX = -sign.x * halfW
            let newWidth = max(Self.minimumShapeSize, abs((dragPoint.x - center.x) - anchorX))
            scaleX = newWidth / bounds.width
        }
        var scaleY = 1.0
        if sign.y != 0, halfH > 0 {
            let anchorY = -sign.y * halfH
            let newHeight = max(Self.minimumShapeSize, abs((dragPoint.y - center.y) - anchorY))
            scaleY = newHeight / bounds.height
        }

        let anchorPoint = CGPoint(x: center.x - sign.x * halfW, y: center.y - sign.y * halfH)

        for (id, memberSnapshot) in snapshot.memberSnapshots {
            guard let member = objects.first(where: { $0.id == id }) else { continue }
            let oldCenter = CGPoint(x: memberSnapshot.positionX + memberSnapshot.width / 2, y: memberSnapshot.positionY + memberSnapshot.height / 2)
            let newCenter = CGPoint(
                x: anchorPoint.x + (oldCenter.x - anchorPoint.x) * scaleX,
                y: anchorPoint.y + (oldCenter.y - anchorPoint.y) * scaleY
            )
            let newWidth = max(Self.minimumShapeSize, memberSnapshot.width * scaleX)
            let newHeight = max(Self.minimumShapeSize, memberSnapshot.height * scaleY)
            member.width = newWidth
            member.height = newHeight
            member.positionX = newCenter.x - newWidth / 2
            member.positionY = newCenter.y - newHeight / 2
        }
    }

    /// Dreht die ganze Gruppe als starren Körper um den Mittelpunkt des Gruppenrahmens: jedes
    /// Mitglied bekommt denselben Rotations-Delta addiert UND wandert auf seiner Kreisbahn um das
    /// Gruppenzentrum mit — exakt (kein Vereinfachungs-Kompromiss wie beim Skalieren), da reine
    /// Rotation keine Scherung erzeugt.
    private func applyGroupRotation(snapshot: GroupTransformSnapshot, dragPoint: CGPoint) {
        let center = CGPoint(x: snapshot.bounds.midX, y: snapshot.bounds.midY)
        let vector = CGPoint(x: dragPoint.x - center.x, y: dragPoint.y - center.y)
        guard vector.x != 0 || vector.y != 0 else { return }
        let angleDegrees = atan2(vector.y, vector.x) * 180 / .pi
        // Der Gruppen-Rotationsgriff steht immer am oberen Rand des (achsenparallelen)
        // Gruppenrahmens, also bei Winkel -90° — derselbe Baseline-Trick wie bei einem Einzelobjekt.
        let delta = angleDegrees + 90

        for (id, memberSnapshot) in snapshot.memberSnapshots {
            guard let member = objects.first(where: { $0.id == id }) else { continue }
            let oldCenter = CGPoint(x: memberSnapshot.positionX + memberSnapshot.width / 2, y: memberSnapshot.positionY + memberSnapshot.height / 2)
            let rotated = Self.rotatedVector(CGPoint(x: oldCenter.x - center.x, y: oldCenter.y - center.y), byDegrees: delta)
            let newCenter = CGPoint(x: center.x + rotated.x, y: center.y + rotated.y)
            member.positionX = newCenter.x - memberSnapshot.width / 2
            member.positionY = newCenter.y - memberSnapshot.height / 2
            member.rotationDegrees = memberSnapshot.rotationDegrees + delta
        }
    }

    /// Positionen der acht Skalier-Griffe + Rotations-Griff für einen achsenparallelen Gruppenrahmen
    /// (kein Eckenradius-Griff, kein Rotations-Offset durch Mitglieder — der Rahmen selbst rotiert nie).
    func groupHandlePositions(for bounds: CGRect) -> [CanvasHandleKind: CGPoint] {
        let halfW = bounds.width / 2
        let halfH = bounds.height / 2
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var result: [CanvasHandleKind: CGPoint] = [:]
        for kind in CanvasHandleKind.resizeCases {
            guard let sign = kind.resizeSign else { continue }
            result[kind] = CGPoint(x: center.x + sign.x * halfW, y: center.y + sign.y * halfH)
        }
        result[.rotate] = CGPoint(x: center.x, y: bounds.minY - Self.rotationHandleOffset)
        return result
    }

    func handle(atDesignPoint point: CGPoint, forGroupBounds bounds: CGRect) -> CanvasHandleKind? {
        let tolerance = Self.handleHitRadiusPoints / zoomScale
        for (kind, handlePoint) in groupHandlePositions(for: bounds) {
            let dx = point.x - handlePoint.x
            let dy = point.y - handlePoint.y
            if (dx * dx + dy * dy).squareRoot() <= tolerance {
                return kind
            }
        }
        return nil
    }

    private func applyResize(to object: DesignObject, handle: CanvasHandleKind, snapshot: TransformSnapshot, dragPoint: CGPoint) {
        guard let sign = handle.resizeSign else { return }
        let oldCenter = CGPoint(x: snapshot.positionX + snapshot.width / 2, y: snapshot.positionY + snapshot.height / 2)
        let dragLocal = Self.localDesignVector(dragPoint, center: oldCenter, rotationDegrees: snapshot.rotationDegrees)

        var newWidth = snapshot.width
        var centerOffsetX: Double = 0
        if sign.x != 0 {
            let anchorX = -sign.x * snapshot.width / 2
            newWidth = max(Self.minimumShapeSize, abs(dragLocal.x - anchorX))
            centerOffsetX = anchorX + (sign.x * newWidth) / 2
        }

        var newHeight = snapshot.height
        var centerOffsetY: Double = 0
        if sign.y != 0 {
            let anchorY = -sign.y * snapshot.height / 2
            newHeight = max(Self.minimumShapeSize, abs(dragLocal.y - anchorY))
            centerOffsetY = anchorY + (sign.y * newHeight) / 2
        }

        let rotatedOffset = Self.rotatedVector(CGPoint(x: centerOffsetX, y: centerOffsetY), byDegrees: snapshot.rotationDegrees)
        let newCenter = CGPoint(x: oldCenter.x + rotatedOffset.x, y: oldCenter.y + rotatedOffset.y)

        object.width = newWidth
        object.height = newHeight
        object.positionX = newCenter.x - newWidth / 2
        object.positionY = newCenter.y - newHeight / 2
    }

    private func applyRotation(to object: DesignObject, snapshot: TransformSnapshot, dragPoint: CGPoint) {
        let center = CGPoint(x: snapshot.positionX + snapshot.width / 2, y: snapshot.positionY + snapshot.height / 2)
        let vector = CGPoint(x: dragPoint.x - center.x, y: dragPoint.y - center.y)
        guard vector.x != 0 || vector.y != 0 else { return }
        let angleDegrees = atan2(vector.y, vector.x) * 180 / .pi
        // Der Rotations-Griff steht bei rotationDegrees == 0 lokal bei (0, -halfHeight), also Winkel -90°.
        object.rotationDegrees = angleDegrees + 90
    }

    private func applyCornerRadius(to object: DesignObject, snapshot: TransformSnapshot, dragPoint: CGPoint) {
        let center = CGPoint(x: snapshot.positionX + snapshot.width / 2, y: snapshot.positionY + snapshot.height / 2)
        let local = Self.localDesignVector(dragPoint, center: center, rotationDegrees: snapshot.rotationDegrees)
        let maxRadius = min(snapshot.width, snapshot.height) / 2
        let radius = local.x + snapshot.width / 2
        object.cornerRadius = min(max(radius, 0), maxRadius)
    }

    static let maxSkewDegrees: Double = 75

    /// Verzerren (Issue #9): die Verschiebung des gegriffenen Kanten-Griffs relativ zur Objektmitte
    /// (im unrotierten lokalen Raum, `snapshot.rotationDegrees` bereits herausgerechnet) wird über
    /// `atan2` in einen Scherwinkel umgerechnet — Bezugsgrösse ist die halbe Breite/Höhe, damit der
    /// Winkel unabhängig von der Objektgrösse vergleichbar bleibt. `handle.resizeSign` bestimmt das
    /// Vorzeichen: ein Griff auf der "negativen" Seite (top: y=-halfH, left: x=-halfW) braucht den
    /// negierten Versatz, damit der Griff dem Mauszeiger tatsächlich folgt — das Vorzeichen muss
    /// exakt zur Scher-Matrix in `DesignObjectPath.visualTransform` passen (x' = x + y·tanX für
    /// top/bottom, y' = y + x·tanY für left/right).
    ///
    /// Vereinfachung: nutzt wie `applyResize`/`applyRotation` weiterhin nur `rotationDegrees` für
    /// die lokale Rückrechnung — ein bereits verzerrtes Objekt (`skewXDegrees`/`skewYDegrees` != 0)
    /// nachträglich per Ecken-/Rotations-Griff zu skalieren/drehen bleibt dadurch eine Annäherung
    /// (dieselbe Art Vereinfachung wie bei `applyGroupResize`), die eigentliche Verzerren-Geste
    /// selbst ist davon nicht betroffen (sie setzt `skewXDegrees`/`skewYDegrees` direkt neu).
    private func applySkew(to object: DesignObject, handle: CanvasHandleKind, snapshot: TransformSnapshot, dragPoint: CGPoint) {
        guard let sign = handle.resizeSign else { return }
        let center = CGPoint(x: snapshot.positionX + snapshot.width / 2, y: snapshot.positionY + snapshot.height / 2)
        let local = Self.localDesignVector(dragPoint, center: center, rotationDegrees: snapshot.rotationDegrees)

        switch handle {
        case .top, .bottom:
            guard snapshot.height > 0 else { return }
            let angle = atan2(local.x * sign.y, snapshot.height / 2) * 180 / .pi
            object.skewXDegrees = Self.clampSkew(angle)
        case .left, .right:
            guard snapshot.width > 0 else { return }
            let angle = atan2(local.y * sign.x, snapshot.width / 2) * 180 / .pi
            object.skewYDegrees = Self.clampSkew(angle)
        default:
            break
        }
    }

    private static func clampSkew(_ degrees: Double) -> Double {
        min(max(degrees, -maxSkewDegrees), maxSkewDegrees)
    }

    private static func center(of object: DesignObject) -> CGPoint {
        CGPoint(x: object.positionX + object.width / 2, y: object.positionY + object.height / 2)
    }

    /// Dreht einen Vektor (relativ zum Ursprung) um `degrees`. Positive Werte drehen entsprechend
    /// `CGAffineTransform(rotationAngle:)` — beide Stellen nutzen dieselbe Konvention (siehe DesignObjectPath.rotationTransform).
    private static func rotatedVector(_ vector: CGPoint, byDegrees degrees: Double) -> CGPoint {
        guard degrees != 0 else { return vector }
        let radians = degrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        return CGPoint(x: vector.x * cosA - vector.y * sinA, y: vector.x * sinA + vector.y * cosA)
    }

    /// `point` relativ zu `center`, zurückgedreht in den unrotierten lokalen Raum (Vektor, nicht absolut).
    private static func localDesignVector(_ point: CGPoint, center: CGPoint, rotationDegrees: Double) -> CGPoint {
        let vector = CGPoint(x: point.x - center.x, y: point.y - center.y)
        return rotatedVector(vector, byDegrees: -rotationDegrees)
    }

    /// `point` zurückgedreht in den unrotierten lokalen Raum des Objekts — absolut, im selben Koordinatenraum
    /// wie `designSpacePath()`/`positionX`/`positionY` (nicht relativ zur Mitte).
    private static func localDesignPoint(_ point: CGPoint, in object: DesignObject) -> CGPoint {
        let objectCenter = center(of: object)
        let vector = localDesignVector(point, center: objectCenter, rotationDegrees: object.rotationDegrees)
        return CGPoint(x: objectCenter.x + vector.x, y: objectCenter.y + vector.y)
    }

    // MARK: Text-Bearbeitung (5d)

    private(set) var editingTextObjectID: UUID?

    var editingTextObject: DesignObject? {
        guard let id = editingTextObjectID else { return nil }
        return objects.first { $0.id == id }
    }

    /// Startet die Inline-Bearbeitung eines Text-Objekts (z.B. per Doppelklick, siehe CanvasView).
    func beginEditingText(_ id: UUID) {
        guard let object = objects.first(where: { $0.id == id }), object.kind == .text, !object.isLocked else { return }
        selectedObjectIDs = [id]
        editingTextObjectID = id
    }

    /// Beendet die Bearbeitung. Ein Text-Objekt, das dabei leer geblieben ist (z.B. Box gezogen und
    /// nichts eingetippt), wird verworfen statt als leeres Objekt liegen zu bleiben.
    func endEditingText() {
        guard let id = editingTextObjectID else { return }
        editingTextObjectID = nil
        guard let object = objects.first(where: { $0.id == id }) else { return }
        if (object.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            objects.removeAll { $0.id == id }
            selectedObjectIDs.remove(id)
        }
    }

    // MARK: Ebenen & Z-Order (5e)

    /// Objekte in Ebenen-Reihenfolge, oberstes (vorderstes) zuerst — wie in einem Ebenen-Panel üblich.
    /// Höherer `zIndex` liegt weiter vorne.
    var objectsFrontToBack: [DesignObject] {
        objects.sorted { $0.zIndex > $1.zIndex }
    }

    enum ZOrderMove {
        case toFront, forward, backward, toBack
    }

    /// Verschiebt ein Objekt in der Ebenen-Reihenfolge und ordnet danach alle `zIndex`-Werte lückenlos
    /// von hinten (0) nach vorne neu. Funktioniert auch für gesperrte Objekte — `isLocked` verhindert
    /// nur Verschieben/Skalieren/Drehen auf dem Canvas, nicht das Umsortieren der Ebenen.
    func moveObject(_ id: UUID, _ move: ZOrderMove) {
        var ordered = objectsFrontToBack
        guard let currentIndex = ordered.firstIndex(where: { $0.id == id }) else { return }
        let object = ordered.remove(at: currentIndex)

        let newIndex: Int
        switch move {
        case .toFront: newIndex = 0
        case .forward: newIndex = max(0, currentIndex - 1)
        case .backward: newIndex = min(ordered.count, currentIndex + 1)
        case .toBack: newIndex = ordered.count
        }
        ordered.insert(object, at: newIndex)
        reassignZIndices(frontToBack: ordered)
    }

    /// Für Drag-Umsortierung im Ebenen-Panel (`List.onMove`) — Offsets/Zielindex beziehen sich auf
    /// dieselbe vorne-nach-hinten-Reihenfolge wie `objectsFrontToBack`.
    func reorderObjects(fromFrontToBackOffsets offsets: IndexSet, toFrontToBackOffset destination: Int) {
        var ordered = objectsFrontToBack
        ordered.move(fromOffsets: offsets, toOffset: destination)
        reassignZIndices(frontToBack: ordered)
    }

    private func reassignZIndices(frontToBack ordered: [DesignObject]) {
        let count = ordered.count
        for (index, object) in ordered.enumerated() {
            object.zIndex = count - 1 - index
        }
    }

    func toggleVisibility(of id: UUID) {
        objects.first { $0.id == id }?.isVisible.toggle()
    }

    func toggleLock(of id: UUID) {
        objects.first { $0.id == id }?.isLocked.toggle()
    }

    /// Entfernt ein Objekt endgültig vom Canvas (Phase 8b, "Objekt löschen"-Menü/Toolbar-Aktion —
    /// bislang gab es dafür noch keine Store-API). Bereinigt Selektion/Bearbeitungszustand, falls
    /// sie sich auf das gelöschte Objekt bezogen. Gesperrte Objekte lassen sich bewusst löschen
    /// (Sperre verhindert nur Verschieben/Skalieren/Drehen, siehe 5c/5e-Konvention).
    func deleteObject(_ id: UUID) {
        objects.removeAll { $0.id == id }
        if selectedObjectIDs.remove(id) != nil {
            stitchPreview = nil
            stitchPreviewError = nil
        }
        if editingTextObjectID == id {
            editingTextObjectID = nil
        }
        if isPartOfActiveTransform(id) {
            activeTransform = nil
            activeHandle = nil
            transformDragStartPoint = nil
        }
    }

    private func isPartOfActiveTransform(_ id: UUID) -> Bool {
        switch activeTransform {
        case .single(let objectID, _): return objectID == id
        case .skew(let objectID, _): return objectID == id
        case .group(let snapshot): return snapshot.memberSnapshots[id] != nil
        case nil: return false
        }
    }

    /// Löscht alle aktuell selektierten Objekte — Komfort-Methode für Menü/Toolbar/Tastenkürzel,
    /// die keine expliziten IDs kennen (anders als das Ebenen-Panel, das pro Zeile eine ID hat).
    func deleteSelectedObject() {
        for id in selectedObjectIDs {
            deleteObject(id)
        }
    }

    // MARK: Garnfarben-Zuweisung (8e)

    /// Weist einem Objekt eine Garnfarbe zu (Drag aus dem Garnlisten-Panel, siehe CanvasView-
    /// Drop-Handler). Erzeugt bewusst ein neues, unabhängiges `ThreadColor` statt eine Relationship
    /// zur Palette durchzureichen — der Drag-Vorgang transportiert nur Werte (`DraggedThreadColor`),
    /// keine SwiftData-Objektreferenz über einen fremden ModelContext hinweg. `fillColorHex` wird
    /// synchron gehalten, da das Canvas-Rendering weiterhin darüber läuft, nicht über `threadColor`.
    func assignColor(name: String, red: Int, green: Int, blue: Int, catalogNumber: String?, to id: UUID) {
        guard let object = objects.first(where: { $0.id == id }) else { return }
        object.threadColor = ThreadColor(name: name, red: red, green: green, blue: blue, catalogNumber: catalogNumber)
        object.fillColorHex = String(format: "#%02X%02X%02X", red, green, blue)
        refreshStitchPreview()
    }

    // MARK: Live-Stichvorschau (6e)

    static let stitchPreviewDebounce: Duration = .milliseconds(250)

    private(set) var stitchPreview: [StitchPoint]?
    /// Menschenlesbare Fehlermeldung der letzten fehlgeschlagenen Stichgenerierung (z.B. Satin
    /// auf einer für Satin ungeeigneten Geometrie, siehe 6f) — nil solange keine vorliegt.
    private(set) var stitchPreviewError: String?

    private var stitchPreviewTask: Task<Void, Never>?

    /// Stösst eine debouncte, abbrechbare Neugenerierung der Stichvorschau für das aktuell
    /// selektierte Objekt an. Aufgerufen bei Selektionswechsel, nach Transform-Drags (Geometrie
    /// geändert) und von aussen nach Sticheinstellungs-Änderungen (siehe ContentView-Dev-Panel,
    /// solange es noch keinen echten Settings-Inspector gibt, Phase 8).
    func refreshStitchPreview() {
        stitchPreviewTask?.cancel()

        guard let object = selectedObject, object.stitchSettings != nil else {
            stitchPreviewTask = nil
            stitchPreview = nil
            stitchPreviewError = nil
            return
        }

        let objectID = object.id
        let canvasSize = canvasSizeMillimeters
        stitchPreviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.stitchPreviewDebounce)
            guard let self, !Task.isCancelled, self.selectedObjectID == objectID else { return }

            do {
                let stitches = try await self.stitchGenerationService.generateStitches(for: object, canvasSize: canvasSize)
                guard !Task.isCancelled, self.selectedObjectID == objectID else { return }
                self.stitchPreview = stitches
                self.stitchPreviewError = nil
            } catch {
                guard !Task.isCancelled, self.selectedObjectID == objectID else { return }
                self.stitchPreview = nil
                self.stitchPreviewError = error.localizedDescription
            }
        }
    }
}
