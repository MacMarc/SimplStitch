//
//  CanvasView.swift
//  SimplStitch
//
//  Basis-Zeichenfläche: rendert die Stickfläche (weisses Rechteck in
//  Canvas-Grösse) mit einem 10mm-Raster zur Orientierung, Zoom per
//  Trackpad-Pinch, sowie die Formen aus CanvasStore.objects inkl.
//  Live-Vorschau während des Zeichnens (5b). Beim Auswahl-Werkzeug übernimmt
//  eine einzige Geste (`selectionGesture`) je nach Trefferpunkt Pan,
//  Verschieben eines Objekts oder Griff-Drag (Skalieren/Drehen/Runden, 5c) —
//  SwiftUI erlaubt nur eine statisch angehängte Geste pro View, daher die
//  Verzweigung zur Laufzeit anhand des Trefferpunkts beim Gestenstart.
//
//  Text (5d): Objekte vom Kind `.text` werden direkt als Glyphen gezeichnet
//  (rotiert wie alle anderen Objekte). Ein Doppelklick auf ein Text-Objekt mit
//  dem Auswahl-Werkzeug startet `CanvasStore.beginEditingText` — währenddessen
//  legt sich eine `TextField`-Overlay über die Box; sie verliert den Fokus
//  (und committet/verwirft damit) sobald der Nutzer wegklickt oder Return drückt.
//

import SwiftUI

struct CanvasView: View {
    let store: CanvasStore

    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveDragTranslation: CGSize = .zero
    @State private var selectionDrag = SelectionDragState()
    @FocusState private var isTextEditorFocused: Bool

    private var effectiveZoomScale: CGFloat {
        store.zoomScale * liveMagnification
    }

    private var effectivePanOffset: CGSize {
        CGSize(
            width: store.panOffset.width + liveDragTranslation.width,
            height: store.panOffset.height + liveDragTranslation.height
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawCanvasBackground(in: &context)
                    drawGrid(in: &context)
                    drawObjects(in: &context)
                    drawDraftPreview(in: &context)
                    drawStitchPreview(in: &context)
                    drawSelectionOutline(in: &context)
                    drawHandles(in: &context)
                    drawStitchPreviewError(in: &context)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .gesture(store.currentTool == .select ? AnyGesture(selectionGesture) : AnyGesture(drawGesture))
                .gesture(magnificationGesture)
                .simultaneousGesture(doubleTapToEditGesture)
                .onAppear {
                    store.zoomToFit(viewportSize: proxy.size)
                }
                .focusedSceneValue(\.zoomToFitAction) {
                    store.zoomToFit(viewportSize: proxy.size)
                }

                if let editingObject = store.editingTextObject {
                    textEditorOverlay(for: editingObject)
                }
            }
        }
    }

    /// Doppelklick auf ein Text-Objekt mit dem Auswahl-Werkzeug startet die Inline-Bearbeitung.
    private var doubleTapToEditGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard store.currentTool == .select else { return }
                let designPoint = store.designPoint(fromView: value.location)
                if let hit = store.object(atDesignPoint: designPoint), hit.kind == .text, !hit.isLocked {
                    store.beginEditingText(hit.id)
                    isTextEditorFocused = true
                }
            }
    }

    /// TextField über der Box des gerade bearbeiteten Text-Objekts (View-Koordinaten, unrotiert —
    /// Bearbeitung eines gedrehten Textfelds ist eine bewusste Vereinfachung, siehe 5d-Scope-Hinweis).
    private func textEditorOverlay(for object: DesignObject) -> some View {
        let topLeft = store.viewPoint(fromDesign: CGPoint(x: object.positionX, y: object.positionY))
        let size = CGSize(width: object.width * effectiveZoomScale, height: object.height * effectiveZoomScale)

        return TextField("", text: textBinding(for: object), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.custom(object.fontName ?? "Helvetica", size: (object.fontSize ?? CanvasStore.defaultTextFontSize) * effectiveZoomScale))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .padding(2)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
            .position(x: topLeft.x + size.width / 2, y: topLeft.y + size.height / 2)
            .focused($isTextEditorFocused)
            .onAppear { isTextEditorFocused = true }
            .onSubmit { store.endEditingText() }
            .onChange(of: isTextEditorFocused) { _, isFocused in
                if !isFocused {
                    store.endEditingText()
                }
            }
    }

    private func textBinding(for object: DesignObject) -> Binding<String> {
        Binding(get: { object.text ?? "" }, set: { object.text = $0 })
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($liveMagnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                store.zoom(by: value)
            }
    }

    /// Auswahl-Werkzeug: eine Geste für Pan (leerer Bereich), Verschieben (Objektkörper) und
    /// Griff-Drag (Skalieren/Drehen/Runden) — die Verzweigung passiert beim ersten `onChanged`-Aufruf
    /// über `beginSelectionInteraction`, das Ergebnis steckt bis `onEnded` in `selectionDrag`.
    private var selectionGesture: some Gesture<DragGesture.Value> {
        DragGesture(minimumDistance: 0)
            .updating($liveDragTranslation) { value, state, _ in
                if case .pan = selectionDrag.mode {
                    state = value.translation
                }
            }
            .onChanged { value in
                if case .none = selectionDrag.mode {
                    selectionDrag.mode = beginSelectionInteraction(atViewPoint: value.startLocation)
                }
                switch selectionDrag.mode {
                case .moveObject, .handle:
                    store.updateTransformDrag(toDesignPoint: store.designPoint(fromView: value.location))
                case .pan, .inert, .none:
                    break
                }
            }
            .onEnded { value in
                switch selectionDrag.mode {
                case .pan:
                    store.pan(by: value.translation)
                case .moveObject, .handle:
                    store.endTransformDrag()
                case .inert, .none:
                    break
                }
                selectionDrag.mode = .none
            }
    }

    /// Entscheidet anhand des Trefferpunkts (View-Koordinaten) beim Gestenstart, was die laufende
    /// Geste bewirken soll — inkl. der dafür nötigen Store-Seiteneffekte (Selektieren, Drag starten).
    private func beginSelectionInteraction(atViewPoint viewPoint: CGPoint) -> SelectionDragState.Mode {
        if store.editingTextObject != nil {
            store.endEditingText()
        }
        let designPoint = store.designPoint(fromView: viewPoint)

        if let selected = store.selectedObject, !selected.isLocked,
           let handle = store.handle(atDesignPoint: designPoint, for: selected) {
            store.beginTransformDrag(object: selected, handle: handle, atDesignPoint: designPoint)
            return .handle(handle)
        }

        if let hitObject = store.object(atDesignPoint: designPoint) {
            if hitObject.isLocked {
                store.selectObject(hitObject.id)
                return .inert
            }
            store.beginTransformDrag(object: hitObject, handle: nil, atDesignPoint: designPoint)
            return .moveObject
        }

        store.selectObject(nil)
        return .pan
    }

    /// Klick-Drag mit einem Formwerkzeug erzeugt statt Pan ein neues DesignObject (siehe CanvasStore.commitDraft).
    private var drawGesture: some Gesture<DragGesture.Value> {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !store.isDrafting {
                    store.beginDraft(atDesignPoint: store.designPoint(fromView: value.startLocation))
                }
                store.updateDraft(toDesignPoint: store.designPoint(fromView: value.location))
            }
            .onEnded { _ in
                store.commitDraft()
            }
    }

    /// Design- → View-Transformation für das direkte Rendern von Objekt-Pfaden (siehe DesignObjectPath).
    private var designToViewTransform: CGAffineTransform {
        CGAffineTransform(scaleX: effectiveZoomScale, y: effectiveZoomScale)
            .concatenating(CGAffineTransform(translationX: effectivePanOffset.width, y: effectivePanOffset.height))
    }

    private func drawCanvasBackground(in context: inout GraphicsContext) {
        let rect = CGRect(
            x: effectivePanOffset.width,
            y: effectivePanOffset.height,
            width: store.canvasSizeMillimeters.width * effectiveZoomScale,
            height: store.canvasSizeMillimeters.height * effectiveZoomScale
        )
        context.fill(Path(rect), with: .color(.white))
        context.stroke(Path(rect), with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)
    }

    private func drawGrid(in context: inout GraphicsContext) {
        let spacingMillimeters: Double = 10
        let scale = effectiveZoomScale
        let origin = CGPoint(x: effectivePanOffset.width, y: effectivePanOffset.height)
        let canvasSize = store.canvasSizeMillimeters

        var gridPath = Path()

        var x: Double = 0
        while x <= canvasSize.width {
            let viewX = origin.x + x * scale
            gridPath.move(to: CGPoint(x: viewX, y: origin.y))
            gridPath.addLine(to: CGPoint(x: viewX, y: origin.y + canvasSize.height * scale))
            x += spacingMillimeters
        }

        var y: Double = 0
        while y <= canvasSize.height {
            let viewY = origin.y + y * scale
            gridPath.move(to: CGPoint(x: origin.x, y: viewY))
            gridPath.addLine(to: CGPoint(x: origin.x + canvasSize.width * scale, y: viewY))
            y += spacingMillimeters
        }

        context.stroke(gridPath, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
    }

    private func drawObjects(in context: inout GraphicsContext) {
        var objectContext = context
        objectContext.transform = designToViewTransform

        for object in store.objects.sorted(by: { $0.zIndex < $1.zIndex }) where object.isVisible {
            let color = Color(cgColor: CGColor.fromHex(object.fillColorHex) ?? CGColor(gray: 0, alpha: 1))
            switch object.kind {
            case .rectangle, .circle, .star:
                let path = object.designSpacePath().applying(object.rotationTransform)
                objectContext.fill(path, with: .color(color))
            case .path:
                let path = object.designSpacePath().applying(object.rotationTransform)
                objectContext.stroke(path, with: .color(color), lineWidth: 0.3)
            case .text:
                drawText(object, color: color, in: context)
            }
        }
    }

    /// Text wird nicht als `Path` gerendert, sondern über `GraphicsContext.draw(Text:at:)` — die
    /// Rotation kommt daher zusätzlich in die Context-Transform statt in den Pfad (siehe
    /// DesignObjectPath.rotationTransform für dieselbe Rotationskonvention als Pfad-Transform).
    private func drawText(_ object: DesignObject, color: Color, in context: GraphicsContext) {
        guard let string = object.text, !string.isEmpty, object.id != store.editingTextObject?.id else { return }
        var textContext = context
        textContext.transform = object.rotationTransform.concatenating(designToViewTransform)
        let fontSize = object.fontSize ?? CanvasStore.defaultTextFontSize
        let font = Font.custom(object.fontName ?? "Helvetica", size: fontSize)
        let text = Text(string).font(font).foregroundColor(color)
        textContext.draw(text, at: CGPoint(x: object.positionX, y: object.positionY), anchor: .topLeading)
    }

    private func drawDraftPreview(in context: inout GraphicsContext) {
        guard store.isDrafting else { return }
        var previewContext = context
        previewContext.transform = designToViewTransform
        let style = StrokeStyle(lineWidth: 0.4, dash: [1.5, 1])

        let path: Path
        switch store.currentTool {
        case .rectangle, .text:
            guard let rect = store.draftShapeRect else { return }
            path = Path(rect)
        case .circle:
            guard let rect = store.draftShapeRect else { return }
            path = Path(ellipseIn: rect)
        case .star:
            guard let rect = store.draftShapeRect else { return }
            path = DesignObject.starPath(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height, pointCount: 5)
        case .path:
            path = polyline(through: store.draftPathPoints)
        case .select:
            return
        }
        previewContext.stroke(path, with: .color(.accentColor), style: style)
    }

    /// Zeichnet die zuletzt generierte Stichvorschau (6e) für das selektierte Objekt als dünne
    /// Polylinien — Segmente, die mit einem echten Stich enden, durchgezogen, alles andere
    /// (JUMP/TRIM/STOP/COLOR_CHANGE, also Bewegung ohne Faden) gestrichelt. `store.stitchPreview`
    /// ist nur gesetzt, solange sie zum aktuell selektierten Objekt gehört (siehe
    /// CanvasStore.refreshStitchPreview), daher keine zusätzliche ID-Prüfung hier nötig.
    private func drawStitchPreview(in context: inout GraphicsContext) {
        guard let stitches = store.stitchPreview, stitches.count > 1 else { return }
        var previewContext = context
        previewContext.transform = designToViewTransform

        var stitchPath = Path()
        var movementPath = Path()
        var previous = CGPoint(x: stitches[0].x, y: stitches[0].y)

        for stitch in stitches.dropFirst() {
            let point = CGPoint(x: stitch.x, y: stitch.y)
            var segment = Path()
            segment.move(to: previous)
            segment.addLine(to: point)
            if stitch.command == .stitch {
                stitchPath.addPath(segment)
            } else {
                movementPath.addPath(segment)
            }
            previous = point
        }

        previewContext.stroke(stitchPath, with: .color(.black.opacity(0.7)), lineWidth: 0.12)
        previewContext.stroke(movementPath, with: .color(.gray.opacity(0.6)), style: StrokeStyle(lineWidth: 0.1, dash: [0.6, 0.4]))
    }

    private func polyline(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    // MARK: Selektion & Handles (5c)

    private func drawSelectionOutline(in context: inout GraphicsContext) {
        guard let selected = store.selectedObject, selected.isVisible else { return }
        var outlineContext = context
        outlineContext.transform = designToViewTransform
        let bounds = CGRect(x: selected.positionX, y: selected.positionY, width: selected.width, height: selected.height)
        let path = Path(bounds).applying(selected.rotationTransform)
        outlineContext.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 0.4, dash: [1.2, 0.8]))
    }

    /// Zeigt einen Fehler der letzten Stichgenerierung (6f) als kleine Inline-Meldung nahe der
    /// Selektion an, statt lautlos nichts zu zeichnen (siehe CanvasStore.refreshStitchPreview).
    /// Betrifft z.B. ungültige/entartete Geometrie, die InkStitch ablehnt — Satin ist dabei
    /// KEIN Garant für einen Fehler: laut 6a-Test lieferte SatinColumn auf einem einfachen
    /// Rechteck ohne Fehler 508 Stiche (InkStitch interpretiert den geschlossenen Pfad
    /// offenbar als zwei Schienen), echte Fehler treten eher bei entarteten/zu kleinen Pfaden
    /// auf. In View-Koordinaten (nicht design-transformiert), damit die Schrift bei jedem Zoom
    /// lesbar bleibt.
    private func drawStitchPreviewError(in context: inout GraphicsContext) {
        guard let message = store.stitchPreviewError,
              let selected = store.selectedObject, selected.isVisible else { return }

        let topLeft = store.viewPoint(fromDesign: CGPoint(x: selected.positionX, y: selected.positionY))
        let text = Text(message)
            .font(.caption)
            .foregroundColor(.white)
        let resolved = context.resolve(text)
        let padding: CGFloat = 4
        let textSize = resolved.measure(in: CGSize(width: 260, height: CGFloat.infinity))
        let origin = CGPoint(x: topLeft.x, y: topLeft.y - textSize.height - padding * 2 - 4)
        let backgroundRect = CGRect(origin: origin, size: CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2))

        context.fill(Path(roundedRect: backgroundRect, cornerRadius: 4), with: .color(.red.opacity(0.85)))
        context.draw(resolved, at: CGPoint(x: backgroundRect.minX + padding, y: backgroundRect.minY + padding), anchor: .topLeading)
    }

    private func drawHandles(in context: inout GraphicsContext) {
        guard let selected = store.selectedObject, selected.isVisible else { return }
        let positions = store.handlePositions(for: selected)
        let markerSize: CGFloat = 7
        let color: Color = selected.isLocked ? .secondary : .accentColor

        if let top = positions[.top], let rotate = positions[.rotate] {
            var linePath = Path()
            linePath.move(to: store.viewPoint(fromDesign: top))
            linePath.addLine(to: store.viewPoint(fromDesign: rotate))
            context.stroke(linePath, with: .color(color.opacity(0.6)), lineWidth: 1)
        }

        for kind in CanvasHandleKind.resizeCases {
            guard let designPoint = positions[kind] else { continue }
            drawSquareHandle(at: store.viewPoint(fromDesign: designPoint), size: markerSize, color: color, in: &context)
        }
        if let rotate = positions[.rotate] {
            drawCircleHandle(at: store.viewPoint(fromDesign: rotate), size: markerSize, color: color, in: &context)
        }
        if let cornerRadius = positions[.cornerRadius] {
            drawCircleHandle(at: store.viewPoint(fromDesign: cornerRadius), size: markerSize - 2, color: .orange, in: &context)
        }
    }

    private func drawSquareHandle(at point: CGPoint, size: CGFloat, color: Color, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        let path = Path(rect)
        context.fill(path, with: .color(.white))
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }

    private func drawCircleHandle(at point: CGPoint, size: CGFloat, color: Color, in context: inout GraphicsContext) {
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(.white))
        context.stroke(path, with: .color(color), lineWidth: 1.2)
    }
}

/// Laufender Interaktions-Modus der 5c-Auswahlgeste — als Referenztyp in `@State` gehalten,
/// da SwiftUI-Gesture-Closures ihn über mehrere `onChanged`-Aufrufe hinweg synchron lesen/schreiben müssen.
@Observable
final class SelectionDragState {
    enum Mode {
        case none
        case pan
        case moveObject
        case handle(CanvasHandleKind)
        /// Getroffen, aber ohne Wirkung (z.B. gesperrtes Objekt) — verhindert versehentliches Pannen.
        case inert
    }

    var mode: Mode = .none
}

#Preview {
    CanvasView(store: CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180)))
}
