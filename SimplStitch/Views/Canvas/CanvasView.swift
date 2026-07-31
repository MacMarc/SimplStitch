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
//  Mehrfachauswahl & Gruppierung (Issue #16): Shift ist der Modifier, der die
//  sonst feste Klick-Drag-auf-leerer-Fläche-ist-immer-Pan-Konvention (5a/5c)
//  überlagert — Shift+Klick auf ein Objekt schaltet es (bzw. bei einem
//  Gruppenmitglied die ganze Gruppe) in der Selektion um, Shift+Drag über
//  leere Fläche zieht ein Gummiband auf. Ohne Shift bleibt alles wie zuvor.
//  Ist eine ganze Gruppe selektiert, zeigt CanvasView einen einzigen,
//  achsenparallelen Rahmen mit Griffen um `CanvasStore.selectedGroupBounds`
//  statt der Einzelobjekt-Griffe — CanvasStore transformiert dann alle
//  Mitglieder gemeinsam (PowerPoint/Illustrator-Verhalten).
//

import AppKit
import SwiftUI

struct CanvasView: View {
    let store: CanvasStore

    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveDragTranslation: CGSize = .zero
    @State private var selectionDrag = SelectionDragState()
    @FocusState private var isTextEditorFocused: Bool
    /// Issue #15/#26: `.onAppear` allein reicht nicht — bei einem frisch von `DocumentGroup`
    /// geöffneten Fenster durchläuft die `GeometryReader`-Grösse mehrere Zwischenwerte, bevor
    /// macOS das Fenster auf seine endgültige (jetzt grosszügige, siehe `.defaultSize` in
    /// SimplStitchApp) Grösse bringt. Ein einmaliges "beim ersten Nicht-Null-Wert einrasten"
    /// (die alte `hasPerformedInitialZoomToFit`-Logik) passte sich dadurch oft an eine noch
    /// transiente, zu kleine Zwischengrösse an und blieb dann für immer klein (Issue #26, Bug 4).
    /// Stattdessen: automatisch neu einpassen bei JEDER Grössenänderung, bis der Nutzer selbst
    /// pannt/zoomt/"Ganze Seite einpassen" wählt — danach hört das automatische Einpassen auf,
    /// um den Nutzer nicht zu überschreiben.
    @State private var hasUserAdjustedView = false

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
                    drawBackgroundImage(in: &context)
                    drawGrid(in: &context)
                    drawObjects(in: &context)
                    drawDraftPreview(in: &context)
                    drawStitchPreview(in: &context)
                    drawSelectionOutline(in: &context)
                    drawHandles(in: &context)
                    drawStitchPreviewError(in: &context)
                    drawMarqueeRect(in: &context)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                .gesture(store.currentTool == .select ? AnyGesture(selectionGesture) : AnyGesture(drawGesture))
                .gesture(magnificationGesture)
                .simultaneousGesture(doubleTapToEditGesture)
                // Issue #19: Escape beendet den Punkt-Editier-Modus (Opus-Konsultation).
                .onExitCommand { store.endPointEditing() }
                .onAppear {
                    autoFitIfNeeded(proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    autoFitIfNeeded(newSize)
                }
                .focusedSceneValue(\.zoomToFitAction) {
                    store.zoomToFit(viewportSize: proxy.size)
                    hasUserAdjustedView = true
                }

                if let editingObject = store.editingTextObject {
                    textEditorOverlay(for: editingObject)
                }
            }
        }
    }

    /// Issue #15/#26: automatisches Einpassen bei jeder Grössenänderung, solange der Nutzer noch
    /// nicht selbst eingegriffen hat — siehe Kommentar bei `hasUserAdjustedView`.
    private func autoFitIfNeeded(_ size: CGSize) {
        guard !hasUserAdjustedView, size.width > 0, size.height > 0 else { return }
        store.zoomToFit(viewportSize: size)
    }

    /// Doppelklick auf ein Text-Objekt mit dem Auswahl-Werkzeug startet die Inline-Bearbeitung.
    /// Issue #19: Doppelklick auf ein `.path`/`.line`-Objekt startet stattdessen den Punkt-Editier-
    /// Modus (Anker-/Kontrollpunkt-Griffe statt der üblichen Skalier-Griffe).
    private var doubleTapToEditGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard store.currentTool == .select else { return }
                let designPoint = store.designPoint(fromView: value.location)
                guard let hit = store.object(atDesignPoint: designPoint), !hit.isLocked else { return }
                if hit.kind == .text {
                    store.beginEditingText(hit.id)
                    isTextEditorFocused = true
                } else if hit.kind == .path || hit.kind == .line {
                    store.beginPointEditing(hit.id)
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
                hasUserAdjustedView = true
            }
    }

    /// Auswahl-Werkzeug: eine Geste für Pan (leerer Bereich), Verschieben (Objekt-/Gruppenkörper),
    /// Griff-Drag (Skalieren/Drehen/Runden, einzeln oder als Gruppe) und Gummiband-Auswahl
    /// (Shift+Drag über leere Fläche) — die Verzweigung passiert beim ersten `onChanged`-Aufruf
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
                    // Issue #30 (Punkt 4): ⇧ wird hier LIVE bei jedem Drag-Update abgefragt (nicht nur
                    // beim Gestenstart in `beginSelectionInteraction`) — dort entscheidet Shift bereits
                    // über Mehrfachauswahl/Gummiband, ein an einem Eck-Griff gestarteter Resize-Drag
                    // (ohne Shift beim Klicken, sonst hätte `beginSelectionInteraction` gar nicht in den
                    // Handle-Zweig verzweigt) kann aber währenddessen mit ⇧ die Proportionen sperren,
                    // exakt wie in Keynote/PowerPoint.
                    store.updateTransformDrag(
                        toDesignPoint: store.designPoint(fromView: value.location),
                        keepAspectRatio: NSEvent.modifierFlags.contains(.shift)
                    )
                case .marquee:
                    store.updateMarqueeSelection(toDesignPoint: store.designPoint(fromView: value.location))
                case .pan, .inert, .none:
                    break
                }
            }
            .onEnded { value in
                switch selectionDrag.mode {
                case .pan:
                    store.pan(by: value.translation)
                    hasUserAdjustedView = true
                case .moveObject, .handle:
                    store.endTransformDrag()
                case .marquee:
                    store.endMarqueeSelection()
                case .inert, .none:
                    break
                }
                selectionDrag.mode = .none
            }
    }

    /// Entscheidet anhand des Trefferpunkts (View-Koordinaten) beim Gestenstart, was die laufende
    /// Geste bewirken soll — inkl. der dafür nötigen Store-Seiteneffekte (Selektieren, Drag starten).
    /// Shift ist der Modifier für Mehrfachauswahl (Objekt-Toggle bzw. Gummiband, siehe Klassenkommentar).
    /// ⌥ (Option) auf einem Kanten-Griff des selektierten Einzelobjekts verzerrt statt zu skalieren
    /// (Issue #9) — nur für Einzelobjekte, nicht für eine selektierte Gruppe (siehe
    /// `CanvasStore.beginSkewDrag`-Kommentar).
    private func beginSelectionInteraction(atViewPoint viewPoint: CGPoint) -> SelectionDragState.Mode {
        if store.editingTextObject != nil {
            store.endEditingText()
        }
        let designPoint = store.designPoint(fromView: viewPoint)
        let shiftHeld = NSEvent.modifierFlags.contains(.shift)
        let optionHeld = NSEvent.modifierFlags.contains(.option)

        // Issue #19: im Punkt-Editier-Modus hat ein Treffer auf Anker/Kontrollpunkt Vorrang vor der
        // normalen Objekt-/Griff-Erkennung — ein Klick daneben beendet den Modus (fällt danach in
        // normales Auswahl-Verhalten durch, z.B. Verschieben des Objekts oder Pan auf leerer Fläche).
        if let pointEditingObject = store.pointEditingObject {
            if let component = store.pointEditHandle(atDesignPoint: designPoint, for: pointEditingObject) {
                store.beginPointEditDrag(object: pointEditingObject, component: component, atDesignPoint: designPoint)
                return .handle(component)
            }
            store.endPointEditing()
        }

        if !shiftHeld, let groupBounds = store.selectedGroupBounds,
           let handle = store.handle(atDesignPoint: designPoint, forGroupBounds: groupBounds) {
            store.beginGroupTransformDrag(handle: handle, atDesignPoint: designPoint)
            return .handle(handle)
        }

        if !shiftHeld, let selected = store.selectedObject, !selected.isLocked,
           let handle = store.handle(atDesignPoint: designPoint, for: selected) {
            if optionHeld, handle.isEdgeHandle {
                store.beginSkewDrag(object: selected, handle: handle, atDesignPoint: designPoint)
            } else {
                store.beginTransformDrag(object: selected, handle: handle, atDesignPoint: designPoint)
            }
            return .handle(handle)
        }

        if let hitObject = store.object(atDesignPoint: designPoint) {
            if shiftHeld {
                store.toggleSelection(of: hitObject.id)
                return .inert
            }
            if hitObject.isLocked {
                store.selectObject(hitObject.id)
                return .inert
            }
            store.beginTransformDrag(object: hitObject, handle: nil, atDesignPoint: designPoint)
            return .moveObject
        }

        if shiftHeld {
            store.beginMarqueeSelection(atDesignPoint: designPoint)
            return .marquee
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

    /// Issue #10: Hintergrundbild als eigene, ausblendbare "Ebene" unterhalb von Raster/Objekten —
    /// seitenverhältnis-erhaltend auf die Canvasgrösse eingepasst (zentriert, wie SVGs eigener
    /// `preserveAspectRatio`-Default `xMidYMid meet`, den unser eigener Renderer hier manuell
    /// nachbilden muss) statt verzerrend zu strecken, mit einstellbarer Deckkraft.
    private func drawBackgroundImage(in context: inout GraphicsContext) {
        guard store.isBackgroundImageVisible, let cgImage = store.backgroundCGImage else { return }
        let canvasRect = CGRect(
            x: effectivePanOffset.width,
            y: effectivePanOffset.height,
            width: store.canvasSizeMillimeters.width * effectiveZoomScale,
            height: store.canvasSizeMillimeters.height * effectiveZoomScale
        )
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = min(canvasRect.width / imageSize.width, canvasRect.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let destinationRect = CGRect(
            x: canvasRect.midX - fittedSize.width / 2,
            y: canvasRect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
        context.drawLayer { layerContext in
            layerContext.opacity = store.backgroundImageOpacity
            layerContext.draw(Image(decorative: cgImage, scale: 1), in: destinationRect)
        }
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
                // Issue #18: Füllung/Rand sind unabhängig voneinander — eine Form kann beides,
                // nur eins oder (mit hasFill=false, hasBorder=false) vorübergehend gar nichts haben.
                let path = object.designSpacePath().applying(object.visualTransform)
                if object.hasFill {
                    objectContext.fill(path, with: .color(color))
                }
                if object.hasBorder {
                    drawBorder(path, object: object, in: &objectContext)
                }
            case .path, .line:
                // Issue #30: `hasFill` wurde hier bislang komplett ignoriert — ein `.path`-Objekt mit
                // aktiver Füllung (z.B. jeder importierte SVG-Pfad, siehe SVGDesignSerializer) sah auf
                // dem Canvas dauerhaft ungefüllt aus, erkennbar nur an der Stichvorschau, und die zeigt
                // ausschliesslich das aktuell SELEKTIERTE Objekt (CanvasStore.refreshStitchPreview) —
                // ohne Klick liess sich "ist das gefüllt?" gar nicht sehen. Jetzt wie bei
                // rect/circle/star: `hasFill` zeichnet eine echte Flächenfüllung. `.line` hat per
                // Definition nie `hasFill = true` (siehe DesignObjectKind-Doku), daher hier unverändert.
                // Der bisherige 0.3mm-Strich in Füllfarbe bleibt NUR der Fallback, wenn weder Füllung
                // noch Rand aktiv sind — sonst wäre der Pfad komplett unsichtbar.
                let path = object.designSpacePath().applying(object.visualTransform)
                if object.hasFill {
                    objectContext.fill(path, with: .color(color))
                }
                if object.hasBorder {
                    drawBorder(path, object: object, in: &objectContext)
                } else if !object.hasFill {
                    objectContext.stroke(path, with: .color(color), lineWidth: 0.3)
                }
            case .text:
                drawText(object, color: color, in: context)
            }
        }
    }

    private func borderColor(for object: DesignObject) -> Color {
        Color(cgColor: CGColor.fromHex(object.borderColorHex ?? object.fillColorHex) ?? CGColor(gray: 0, alpha: 1))
    }

    /// Issue #30: Rand-Ausrichtung (`BorderAlignment`) — SwiftUI/CoreGraphics kennt keine native
    /// Inside/Outside-Stroke-Option, ein Strich liegt immer zentriert auf der Kontur. Statt einer
    /// echten Offset-Kurve (die es auf Swift-/CoreGraphics-Seite nicht gibt — die serverseitige
    /// Stichgenerierung in `bridge.py` nutzt dafür Shapely) zeichnet die Vorschau einen doppelt
    /// breiten zentrierten Strich und clippt ihn auf die Innen- bzw. Aussenhälfte des Original-
    /// Pfads — eine praktische Näherung, die bei den allermeisten Formen visuell nicht von einer
    /// echten Offset-Kurve zu unterscheiden ist (bewusste Vereinfachung, siehe Rand-Sektion im
    /// Objekt-Inspektor). `.outside` nutzt den Even-Odd-Trick (grosses Rechteck + Original-Pfad in
    /// einem gemeinsamen `Path`) statt echter Pfad-Subtraktion, die SwiftUI ebenfalls nicht bietet.
    private func drawBorder(_ path: Path, object: DesignObject, in context: inout GraphicsContext) {
        let strokeColor = borderColor(for: object)
        switch object.borderAlignment {
        case .centered:
            context.stroke(path, with: .color(strokeColor), lineWidth: object.borderWidthMillimeters)
        case .inside:
            var clippedContext = context
            clippedContext.clip(to: path)
            clippedContext.stroke(path, with: .color(strokeColor), lineWidth: object.borderWidthMillimeters * 2)
        case .outside:
            var clippedContext = context
            var outsideMask = Path()
            outsideMask.addRect(path.boundingRect.insetBy(dx: -object.borderWidthMillimeters, dy: -object.borderWidthMillimeters))
            outsideMask.addPath(path)
            clippedContext.clip(to: outsideMask, style: FillStyle(eoFill: true))
            clippedContext.stroke(path, with: .color(strokeColor), lineWidth: object.borderWidthMillimeters * 2)
        }
    }

    /// Text wird nicht als `Path` gerendert, sondern über `GraphicsContext.draw(Text:at:)` — die
    /// Rotation kommt daher zusätzlich in die Context-Transform statt in den Pfad (siehe
    /// DesignObjectPath.visualTransform für dieselbe Rotationskonvention als Pfad-Transform).
    private func drawText(_ object: DesignObject, color: Color, in context: GraphicsContext) {
        guard let string = object.text, !string.isEmpty, object.id != store.editingTextObject?.id else { return }
        var textContext = context
        textContext.transform = object.visualTransform.concatenating(designToViewTransform)
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
        case .path, .line:
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
        var outlineContext = context
        outlineContext.transform = designToViewTransform
        let style = StrokeStyle(lineWidth: 0.4, dash: [1.2, 0.8])

        if let groupBounds = store.selectedGroupBounds {
            // Gruppenrahmen (achsenparallel) plus dünne Konturen je Mitglied — wie in Illustrator/
            // PowerPoint, wo eine Gruppenselektion beides gleichzeitig zeigt.
            for member in store.selectedObjects where member.isVisible {
                let memberBounds = CGRect(x: member.positionX, y: member.positionY, width: member.width, height: member.height)
                let memberPath = Path(memberBounds).applying(member.visualTransform)
                outlineContext.stroke(memberPath, with: .color(.accentColor.opacity(0.5)), style: StrokeStyle(lineWidth: 0.25, dash: [0.8, 0.6]))
            }
            outlineContext.stroke(Path(groupBounds), with: .color(.accentColor), style: style)
            return
        }

        if store.selectedObjectIDs.count > 1 {
            // Mehrfachauswahl über Gruppengrenzen hinweg (kommt nur über die Panel-Mehrfachauswahl
            // vor) — Vereinfachung: nur Einzelkonturen, keine gemeinsamen Griffe (siehe CanvasStore).
            for object in store.selectedObjects where object.isVisible {
                let bounds = CGRect(x: object.positionX, y: object.positionY, width: object.width, height: object.height)
                let path = Path(bounds).applying(object.visualTransform)
                outlineContext.stroke(path, with: .color(.accentColor), style: style)
            }
            return
        }

        guard let selected = store.selectedObject, selected.isVisible else { return }
        let bounds = CGRect(x: selected.positionX, y: selected.positionY, width: selected.width, height: selected.height)
        let path = Path(bounds).applying(selected.visualTransform)
        outlineContext.stroke(path, with: .color(.accentColor), style: style)
    }

    /// Gummiband-Rechteck während einer Shift-Drag-Auswahl über leere Canvas-Fläche.
    private func drawMarqueeRect(in context: inout GraphicsContext) {
        guard let rect = store.marqueeRect else { return }
        var marqueeContext = context
        marqueeContext.transform = designToViewTransform
        let path = Path(rect)
        marqueeContext.fill(path, with: .color(.accentColor.opacity(0.12)))
        marqueeContext.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 0.4, dash: [1.2, 0.8]))
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
        let markerSize: CGFloat = 7

        // Issue #19: im Punkt-Editier-Modus ERSETZEN Anker-/Kontrollpunkt-Griffe die üblichen
        // Skalier-/Rotations-Griffe komplett, statt zusätzlich dazu gezeichnet zu werden.
        if let pointEditingObject = store.pointEditingObject, pointEditingObject.isVisible {
            drawPointEditHandles(for: pointEditingObject, markerSize: markerSize, in: &context)
            return
        }

        if let groupBounds = store.selectedGroupBounds {
            drawHandleSet(store.groupHandlePositions(for: groupBounds), markerSize: markerSize, color: .accentColor, in: &context)
            return
        }

        guard let selected = store.selectedObject, selected.isVisible else { return }
        let color: Color = selected.isLocked ? .secondary : .accentColor
        drawHandleSet(store.handlePositions(for: selected), markerSize: markerSize, color: color, in: &context)
    }

    private func drawHandleSet(_ positions: [CanvasHandleKind: CGPoint], markerSize: CGFloat, color: Color, in context: inout GraphicsContext) {
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

    /// Issue #19: Quadrat-Griff pro Anker (alle Anker, jederzeit anklickbar) + runde Kontrollpunkt-
    /// Griffe mit Verbindungslinie zum Anker — aber nur für `activePointEditAnchorIndex`, sonst wären
    /// bei einem Pfad mit vielen Ankern alle Kontrollpunkte gleichzeitig sichtbar (unübersichtlich).
    private func drawPointEditHandles(for object: DesignObject, markerSize: CGFloat, in context: inout GraphicsContext) {
        let positions = store.pointEditAnchorPositions(for: object)

        if let activeIndex = store.activePointEditAnchorIndex, let anchorPoint = positions[.anchor(activeIndex)] {
            let anchorViewPoint = store.viewPoint(fromDesign: anchorPoint)
            for kind in [CanvasHandleKind.controlIn(activeIndex), .controlOut(activeIndex)] {
                guard let controlPoint = positions[kind] else { continue }
                var linePath = Path()
                linePath.move(to: anchorViewPoint)
                linePath.addLine(to: store.viewPoint(fromDesign: controlPoint))
                context.stroke(linePath, with: .color(Color.orange.opacity(0.6)), lineWidth: 1)
            }
        }

        for (kind, designPoint) in positions {
            let viewPoint = store.viewPoint(fromDesign: designPoint)
            switch kind {
            case .anchor:
                drawSquareHandle(at: viewPoint, size: markerSize, color: .accentColor, in: &context)
            case .controlIn, .controlOut:
                drawCircleHandle(at: viewPoint, size: markerSize - 1, color: .orange, in: &context)
            case .segmentMidpoint:
                // Issue #19 (Linie-Biegepunkte): ursprünglich bewusst kleiner/blasser als die
                // Anker-Quadrate gehalten, damit auf einen Blick klar ist, dass dies eine Biege-
                // statt eine Endpunkt-Geste ist — laut Nutzer-Feedback (Issue #29, Punkt 8) dadurch
                // aber kaum erkennbar/treffbar. Jetzt sogar etwas GRÖSSER als die Anker-Quadrate und
                // voll deckend (Orange statt Accent-Farbe reicht als Unterscheidung zum Anker).
                drawCircleHandle(at: viewPoint, size: markerSize + 1, color: .orange, in: &context)
            default:
                break
            }
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
        /// Gummiband-Auswahl (Shift+Drag über leere Fläche, siehe CanvasView-Klassenkommentar).
        case marquee
        /// Getroffen, aber ohne Wirkung (z.B. gesperrtes Objekt oder Shift-Klick-Toggle) —
        /// verhindert versehentliches Pannen.
        case inert
    }

    var mode: Mode = .none
}

#Preview {
    CanvasView(store: CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180)))
}
