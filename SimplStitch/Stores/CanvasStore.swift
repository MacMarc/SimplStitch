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
//  `objects` lebt vorerst nur im Store (kein ModelContext-Insert) — bis
//  Phase 8 echte Projekte via DocumentGroup öffnet, gibt es noch kein reales
//  StitchProject zum Anhängen; die Synchronisation mit SwiftData übernimmt
//  dann ein ProjectStore.
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
    var canvasSizeMillimeters: CGSize

    private let stitchGenerationService: StitchGenerationServicing

    init(
        canvasSizeMillimeters: CGSize,
        zoomScale: CGFloat = 1,
        panOffset: CGSize = .zero,
        stitchGenerationService: StitchGenerationServicing = StitchGenerationService(bridge: PythonBridge())
    ) {
        self.canvasSizeMillimeters = canvasSizeMillimeters
        self.zoomScale = min(max(zoomScale, Self.minZoomScale), Self.maxZoomScale)
        self.panOffset = panOffset
        self.stitchGenerationService = stitchGenerationService
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
    private(set) var objects: [DesignObject] = []
    private(set) var isDrafting = false
    private(set) var draftShapeRect: CGRect?
    private(set) var draftPathPoints: [CGPoint] = []

    private var draftStartPoint: CGPoint?

    func selectTool(_ tool: CanvasTool) {
        currentTool = tool
        if tool != .select {
            selectedObjectID = nil
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
            objects.append(newObject)
        }
        currentTool = .select
        selectedObjectID = newObject?.id
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
        return object
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

    // MARK: Selektion & Handles (5c)

    private(set) var selectedObjectID: UUID?

    var selectedObject: DesignObject? {
        guard let id = selectedObjectID else { return nil }
        return objects.first { $0.id == id }
    }

    func selectObject(_ id: UUID?) {
        selectedObjectID = id
        refreshStitchPreview()
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
    }

    private var activeObjectID: UUID?
    private var activeHandle: CanvasHandleKind?
    private var transformDragStartPoint: CGPoint?
    private var transformDragSnapshot: TransformSnapshot?

    /// Startet das Verschieben (handle == nil) oder einen Griff-Drag am gegebenen Punkt (Design-Koordinaten).
    /// Selektiert das Objekt gleich mit. Gesperrte Objekte (`isLocked`) lassen sich selektieren, aber nicht verändern.
    func beginTransformDrag(object: DesignObject, handle: CanvasHandleKind?, atDesignPoint point: CGPoint) {
        selectedObjectID = object.id
        guard !object.isLocked else { return }
        activeObjectID = object.id
        activeHandle = handle
        transformDragStartPoint = point
        transformDragSnapshot = TransformSnapshot(
            positionX: object.positionX,
            positionY: object.positionY,
            width: object.width,
            height: object.height,
            rotationDegrees: object.rotationDegrees,
            cornerRadius: object.cornerRadius
        )
    }

    func updateTransformDrag(toDesignPoint point: CGPoint) {
        guard let objectID = activeObjectID,
              let object = objects.first(where: { $0.id == objectID }),
              let start = transformDragStartPoint,
              let snapshot = transformDragSnapshot else { return }

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
    }

    func endTransformDrag() {
        activeObjectID = nil
        activeHandle = nil
        transformDragStartPoint = nil
        transformDragSnapshot = nil
        refreshStitchPreview()
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
        selectedObjectID = id
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
            if selectedObjectID == id {
                selectedObjectID = nil
            }
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
