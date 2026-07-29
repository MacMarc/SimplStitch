//
//  CanvasStoreTests.swift
//  SimplStitchTests
//
//  Phase-5a-Checkpoint: Koordinatensystem, Zoom/Pan-Zustand.
//

import Testing
import SwiftUI
@testable import SimplStitch

@MainActor
struct CanvasStoreTests {

    @Test func initialStateIsUnzoomedAndUnpanned() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 150))
        #expect(store.zoomScale == 1)
        #expect(store.panOffset == .zero)
    }

    @Test func zoomIsClampedToBounds() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.setZoomScale(100)
        #expect(store.zoomScale == CanvasStore.maxZoomScale)
        store.setZoomScale(0.001)
        #expect(store.zoomScale == CanvasStore.minZoomScale)
    }

    @Test func zoomByMultipliesCurrentScale() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.zoom(by: 2)
        #expect(store.zoomScale == 2)
        store.zoom(by: 0.5)
        #expect(abs(store.zoomScale - 1) < 0.0001)
    }

    @Test func panAccumulatesOffset() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.pan(by: CGSize(width: 10, height: -5))
        store.pan(by: CGSize(width: 5, height: 5))
        #expect(store.panOffset == CGSize(width: 15, height: 0))
    }

    @Test func designAndViewPointConversionsRoundtrip() {
        let store = CanvasStore(
            canvasSizeMillimeters: CGSize(width: 100, height: 100),
            zoomScale: 2,
            panOffset: CGSize(width: 20, height: 30)
        )
        let designPoint = CGPoint(x: 40, y: 25)
        let viewPoint = store.viewPoint(fromDesign: designPoint)
        #expect(viewPoint == CGPoint(x: 40 * 2 + 20, y: 25 * 2 + 30))

        let backToDesign = store.designPoint(fromView: viewPoint)
        #expect(abs(backToDesign.x - designPoint.x) < 0.0001)
        #expect(abs(backToDesign.y - designPoint.y) < 0.0001)
    }

    @Test func zoomToFitScalesAndCentersCanvas() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 50))
        store.zoomToFit(viewportSize: CGSize(width: 500, height: 500), margin: 0)

        // Breiter Canvas (100x50) in quadratischem Viewport (500x500) -> Breite limitiert die Skalierung.
        #expect(abs(store.zoomScale - 5) < 0.0001)
        let scaledHeight = 50 * store.zoomScale
        #expect(abs(store.panOffset.height - (500 - scaledHeight) / 2) < 0.0001)
        #expect(abs(store.panOffset.width - 0) < 0.0001)
    }

    @Test func resetViewRestoresDefaults() {
        let store = CanvasStore(
            canvasSizeMillimeters: CGSize(width: 100, height: 100),
            zoomScale: 3,
            panOffset: CGSize(width: 10, height: 10)
        )
        store.resetView()
        #expect(store.zoomScale == 1)
        #expect(store.panOffset == .zero)
    }

    // MARK: Formen (5b)

    @Test func draggingRectangleToolCreatesRectangleObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: CGPoint(x: 10, y: 20))
        store.updateDraft(toDesignPoint: CGPoint(x: 40, y: 50))
        let created = store.commitDraft()

        #expect(created?.kind == .rectangle)
        #expect(created?.positionX == 10)
        #expect(created?.positionY == 20)
        #expect(created?.width == 30)
        #expect(created?.height == 30)
        #expect(store.objects.count == 1)
        #expect(created?.stitchSettings?.stitchType == .tatami)
    }

    @Test func draggingInAnyDirectionNormalizesToPositiveRect() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.circle)
        store.beginDraft(atDesignPoint: CGPoint(x: 40, y: 50))
        store.updateDraft(toDesignPoint: CGPoint(x: 10, y: 20))
        let created = store.commitDraft()

        #expect(created?.kind == .circle)
        #expect(created?.positionX == 10)
        #expect(created?.positionY == 20)
        #expect(created?.width == 30)
        #expect(created?.height == 30)
    }

    @Test func draggingStarToolSetsDefaultPointCount() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.star)
        store.beginDraft(atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateDraft(toDesignPoint: CGPoint(x: 20, y: 20))
        let created = store.commitDraft()

        #expect(created?.kind == .star)
        #expect(created?.starPointCount == 5)
        #expect(created?.stitchSettings?.stitchType == .tatami)
    }

    /// Issue #11: schmale/längliche Rechtecke bekommen automatisch Satin statt Tatami vorgeschlagen
    /// (siehe StitchSettingsTests für die reine Heuristik) — hier die tatsächliche Verdrahtung in
    /// CanvasStore.makeShapeObject.
    @Test func draggingNarrowElongatedRectangleSuggestsSatin() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateDraft(toDesignPoint: CGPoint(x: 30, y: 3))
        let created = store.commitDraft()

        #expect(created?.stitchSettings?.stitchType == .satin)
    }

    @Test func draggingBelowMinimumSizeCreatesNoObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: CGPoint(x: 10, y: 10))
        store.updateDraft(toDesignPoint: CGPoint(x: 10.2, y: 10.2))
        let created = store.commitDraft()

        #expect(created == nil)
        #expect(store.objects.isEmpty)
    }

    @Test func freehandPathAccumulatesPointsIntoPathData() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.path)
        store.beginDraft(atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateDraft(toDesignPoint: CGPoint(x: 10, y: 0))
        store.updateDraft(toDesignPoint: CGPoint(x: 10, y: 10))
        let created = store.commitDraft()

        #expect(created?.kind == .path)
        #expect(created?.positionX == 0)
        #expect(created?.positionY == 0)
        #expect(created?.width == 10)
        #expect(created?.height == 10)
        #expect(created?.pathData == "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000")
        #expect(created?.stitchSettings?.stitchType == .straight)
    }

    @Test func singleClickWithPathToolCreatesNoObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.path)
        store.beginDraft(atDesignPoint: CGPoint(x: 5, y: 5))
        let created = store.commitDraft()

        #expect(created == nil)
        #expect(store.objects.isEmpty)
    }

    @Test func committingDraftResetsToolToSelect() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: .zero)
        store.updateDraft(toDesignPoint: CGPoint(x: 20, y: 20))
        store.commitDraft()

        #expect(store.currentTool == .select)
        #expect(store.isDrafting == false)
    }

    @Test func defaultObjectNamesIncrementPerKind() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: .zero)
        store.updateDraft(toDesignPoint: CGPoint(x: 20, y: 20))
        store.commitDraft()

        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: .zero)
        store.updateDraft(toDesignPoint: CGPoint(x: 20, y: 20))
        let second = store.commitDraft()

        #expect(second?.name == "\(CanvasTool.rectangle.displayName) 2")
    }

    @Test func selectToolDoesNotStartDrafting() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.beginDraft(atDesignPoint: CGPoint(x: 5, y: 5))
        #expect(store.isDrafting == false)
    }

    // MARK: Selektion & Handles (5c)

    /// Erzeugt ein Rechteck bei (10,10)-(30,30) über das übliche Draft-Verfahren, ohne dabei die
    /// automatische Selektion nach `commitDraft()` weiter zu testen.
    @discardableResult
    private func makeRectangle(in store: CanvasStore, from: CGPoint = CGPoint(x: 10, y: 10), to: CGPoint = CGPoint(x: 30, y: 30)) -> DesignObject {
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: from)
        store.updateDraft(toDesignPoint: to)
        return store.commitDraft()!
    }

    @Test func committingDraftSelectsTheNewObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        #expect(store.selectedObjectID == object.id)
    }

    @Test func switchingAwayFromSelectToolClearsSelection() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        makeRectangle(in: store)
        #expect(store.selectedObjectID != nil)
        store.selectTool(.circle)
        #expect(store.selectedObjectID == nil)
    }

    @Test func clickingInsideObjectHitTestsIt() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        #expect(store.object(atDesignPoint: CGPoint(x: 20, y: 20))?.id == object.id)
        #expect(store.object(atDesignPoint: CGPoint(x: 5, y: 5)) == nil)
    }

    @Test func hitTestReturnsTopmostObjectAtOverlap() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let bottom = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 40))
        let top = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 50))
        #expect(bottom.zIndex < top.zIndex)
        #expect(store.object(atDesignPoint: CGPoint(x: 20, y: 20))?.id == top.id)
    }

    @Test func movingSelectedObjectTranslatesPosition() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        store.beginTransformDrag(object: object, handle: nil, atDesignPoint: CGPoint(x: 15, y: 15))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 25, y: 20))
        store.endTransformDrag()

        #expect(object.positionX == 20)
        #expect(object.positionY == 15)
        #expect(object.width == 20)
        #expect(object.height == 20)
    }

    @Test func resizingViaCornerHandleKeepsOppositeCornerFixed() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store) // (10,10)-(30,30)
        store.beginTransformDrag(object: object, handle: .bottomRight, atDesignPoint: CGPoint(x: 30, y: 30))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 40, y: 50))
        store.endTransformDrag()

        // topLeft (10,10) bleibt fix, bottomRight wandert auf (40,50).
        #expect(abs(object.positionX - 10) < 0.0001)
        #expect(abs(object.positionY - 10) < 0.0001)
        #expect(abs(object.width - 30) < 0.0001)
        #expect(abs(object.height - 40) < 0.0001)
    }

    @Test func resizingViaEdgeHandleOnlyChangesOneAxis() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store) // (10,10)-(30,30)
        store.beginTransformDrag(object: object, handle: .right, atDesignPoint: CGPoint(x: 30, y: 20))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 50, y: 999))
        store.endTransformDrag()

        #expect(abs(object.positionX - 10) < 0.0001)
        #expect(abs(object.positionY - 10) < 0.0001)
        #expect(abs(object.width - 40) < 0.0001)
        #expect(abs(object.height - 20) < 0.0001)
    }

    @Test func resizeRespectsMinimumShapeSize() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store) // (10,10)-(30,30)
        store.beginTransformDrag(object: object, handle: .bottomRight, atDesignPoint: CGPoint(x: 30, y: 30))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 10.1, y: 10.1))
        store.endTransformDrag()

        #expect(object.width >= CanvasStore.minimumShapeSize)
        #expect(object.height >= CanvasStore.minimumShapeSize)
    }

    @Test func rotateHandleSetsRotationTowardsDragDirection() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store) // Mitte bei (20,20)
        let topHandle = store.handlePositions(for: object)[.rotate]!
        store.beginTransformDrag(object: object, handle: .rotate, atDesignPoint: topHandle)

        // Direkt rechts der Mitte ziehen -> 90° im Uhrzeigersinn zur Ausgangslage des Griffs.
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 40, y: 20))
        store.endTransformDrag()
        #expect(abs(object.rotationDegrees - 90) < 0.0001)
    }

    @Test func rotatingObjectMovesHandlePositionsWithIt() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store) // Mitte bei (20,20), halfHeight 10
        object.rotationDegrees = 90
        let top = store.handlePositions(for: object)[.top]!
        // Nach 90°-Drehung zeigt "oben" (lokal (0,-10)) design-räumlich nach rechts (20+10, 20).
        #expect(abs(top.x - 30) < 0.0001)
        #expect(abs(top.y - 20) < 0.0001)
    }

    @Test func cornerRadiusHandleAdjustsRadiusOnlyForRectangles() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store) // (10,10)-(30,30), width=height=20
        store.beginTransformDrag(object: object, handle: .cornerRadius, atDesignPoint: CGPoint(x: 10, y: 10))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 15, y: 10))
        store.endTransformDrag()

        #expect(abs(object.cornerRadius - 5) < 0.0001)

        store.beginTransformDrag(object: object, handle: .cornerRadius, atDesignPoint: CGPoint(x: 15, y: 10))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 999, y: 10))
        store.endTransformDrag()
        #expect(abs(object.cornerRadius - 10) < 0.0001) // geklemmt auf min(width,height)/2
    }

    // MARK: Verzerren (Issue #9)

    /// Rechteck (0,0)-(10,10), Mitte (5,5) — Top-Griff sitzt unrotiert bei (5,0). Dragt man ihn nach
    /// rechts, muss der sichtbare Top-Mittelpunkt (per `visualTransform`) dem Mauszeiger folgen.
    @Test func skewDragOnTopHandleMovesVisibleTopEdgeTowardsDragDirection() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))

        store.beginSkewDrag(object: object, handle: .top, atDesignPoint: CGPoint(x: 5, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 10, y: 0))
        store.endTransformDrag()

        #expect(abs(object.skewXDegrees - (-45)) < 0.01)
        #expect(object.skewYDegrees == 0)

        let visibleTopCenter = CGPoint(x: 5, y: 0).applying(object.visualTransform)
        #expect(abs(visibleTopCenter.x - 10) < 0.01)
        #expect(abs(visibleTopCenter.y - 0) < 0.01)
    }

    @Test func skewDragOnRightHandleSetsSkewY() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))

        store.beginSkewDrag(object: object, handle: .right, atDesignPoint: CGPoint(x: 10, y: 5))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 10, y: 10))
        store.endTransformDrag()

        #expect(abs(object.skewYDegrees - 45) < 0.01)
        #expect(object.skewXDegrees == 0)
    }

    @Test func skewDragIgnoresCornerAndRotateHandles() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))

        store.beginSkewDrag(object: object, handle: .topLeft, atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 20, y: 20))

        #expect(object.skewXDegrees == 0)
        #expect(object.skewYDegrees == 0)
        #expect(store.selectedObjectID == object.id) // Selektion passiert trotzdem.
    }

    @Test func skewDragIgnoresLockedObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
        object.isLocked = true

        store.beginSkewDrag(object: object, handle: .top, atDesignPoint: CGPoint(x: 5, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 10, y: 0))

        #expect(object.skewXDegrees == 0)
    }

    @Test func skewIsClampedToMaxDegrees() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 200, height: 200))
        let object = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))

        store.beginSkewDrag(object: object, handle: .right, atDesignPoint: CGPoint(x: 10, y: 5))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 10, y: 1000))

        #expect(object.skewYDegrees == CanvasStore.maxSkewDegrees)
    }

    @Test func lockedObjectIgnoresTransformDrag() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        object.isLocked = true
        store.beginTransformDrag(object: object, handle: nil, atDesignPoint: CGPoint(x: 15, y: 15))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 50, y: 50))
        store.endTransformDrag()

        #expect(object.positionX == 10)
        #expect(object.positionY == 10)
        #expect(store.selectedObjectID == object.id) // Selektion bleibt trotz Sperre erhalten.
    }

    @Test func handleAtDesignPointFindsNearbyHandleWithinTolerance() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store) // (10,10)-(30,30)
        let bottomRight = store.handlePositions(for: object)[.bottomRight]!
        #expect(store.handle(atDesignPoint: bottomRight, for: object) == .bottomRight)
        #expect(store.handle(atDesignPoint: CGPoint(x: 20, y: 20), for: object) == nil)
    }

    @Test func selectObjectAndDeselect() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        store.selectObject(nil)
        #expect(store.selectedObject == nil)
        store.selectObject(object.id)
        #expect(store.selectedObject?.id == object.id)
    }

    // MARK: Text (5d)

    @Test func draggingTextToolCreatesTextObjectAndStartsEditing() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.text)
        store.beginDraft(atDesignPoint: CGPoint(x: 10, y: 10))
        store.updateDraft(toDesignPoint: CGPoint(x: 50, y: 25))
        let created = store.commitDraft()

        #expect(created?.kind == .text)
        #expect(created?.positionX == 10)
        #expect(created?.positionY == 10)
        #expect(created?.width == 40)
        #expect(created?.height == 15)
        #expect(created?.text == "")
        #expect(store.selectedObjectID == created?.id)
        #expect(store.editingTextObjectID == created?.id)
        // Text bekommt bewusst keine Default-Sticheinstellungen — die Text-zu-Stich-Konvertierung
        // ist noch nicht implementiert (siehe CLAUDE.md Phase 5d), anders als bei Formen/Pfaden.
        #expect(created?.stitchSettings == nil)
    }

    @Test func clickingTextToolCreatesDefaultSizedBox() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.text)
        store.beginDraft(atDesignPoint: CGPoint(x: 10, y: 10))
        let created = store.commitDraft()

        #expect(created?.kind == .text)
        #expect(created?.positionX == 10)
        #expect(created?.positionY == 10)
        #expect(created?.width == 40)
        #expect(created?.height == 12)
    }

    @Test func endingEditingDiscardsObjectThatStayedEmpty() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.text)
        store.beginDraft(atDesignPoint: CGPoint(x: 10, y: 10))
        store.commitDraft()

        store.endEditingText()

        #expect(store.editingTextObjectID == nil)
        #expect(store.objects.isEmpty)
        #expect(store.selectedObjectID == nil)
    }

    @Test func endingEditingKeepsObjectWithText() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.text)
        store.beginDraft(atDesignPoint: CGPoint(x: 10, y: 10))
        let created = store.commitDraft()
        created?.text = "Bobbi"

        store.endEditingText()

        #expect(store.editingTextObjectID == nil)
        #expect(store.objects.count == 1)
        #expect(store.objects.first?.text == "Bobbi")
    }

    @Test func beginEditingTextIgnoresNonTextAndLockedObjects() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let rectangle = makeRectangle(in: store)
        store.beginEditingText(rectangle.id)
        #expect(store.editingTextObjectID == nil)

        store.selectTool(.text)
        store.beginDraft(atDesignPoint: CGPoint(x: 50, y: 50))
        store.updateDraft(toDesignPoint: CGPoint(x: 70, y: 60))
        let text = store.commitDraft()!
        text.text = "Bobbi"
        store.endEditingText() // beendet den Auto-Edit-Modus von commitDraft, Objekt bleibt (nicht leer)
        text.isLocked = true

        store.beginEditingText(text.id)
        #expect(store.editingTextObjectID == nil)
    }

    // MARK: Ebenen & Z-Order (5e)

    @Test func objectsFrontToBackListsHighestZIndexFirst() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)
        let third = makeRectangle(in: store)

        #expect(store.objectsFrontToBack.map(\.id) == [third.id, second.id, first.id])
    }

    @Test func moveObjectToFrontPutsItAheadOfAllOthers() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)
        let third = makeRectangle(in: store)

        store.moveObject(first.id, .toFront)

        #expect(store.objectsFrontToBack.map(\.id) == [first.id, third.id, second.id])
        #expect(first.zIndex == 2)
        #expect(third.zIndex == 1)
        #expect(second.zIndex == 0)
    }

    @Test func moveObjectToBackPutsItBehindAllOthers() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)
        let third = makeRectangle(in: store)

        store.moveObject(third.id, .toBack)

        #expect(store.objectsFrontToBack.map(\.id) == [second.id, first.id, third.id])
        #expect(third.zIndex == 0)
    }

    @Test func moveObjectForwardSwapsWithNextObjectTowardsFront() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)
        let third = makeRectangle(in: store)

        store.moveObject(first.id, .forward)

        #expect(store.objectsFrontToBack.map(\.id) == [third.id, first.id, second.id])
    }

    @Test func moveObjectBackwardSwapsWithNextObjectTowardsBack() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)
        let third = makeRectangle(in: store)

        store.moveObject(third.id, .backward)

        #expect(store.objectsFrontToBack.map(\.id) == [second.id, third.id, first.id])
    }

    @Test func moveObjectAtFrontIgnoresForwardAndMoveObjectAtBackIgnoresBackward() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)

        store.moveObject(second.id, .forward) // second ist bereits vorne
        #expect(store.objectsFrontToBack.map(\.id) == [second.id, first.id])

        store.moveObject(first.id, .backward) // first ist bereits hinten
        #expect(store.objectsFrontToBack.map(\.id) == [second.id, first.id])
    }

    @Test func moveObjectReordersLockedObjectsToo() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)
        first.isLocked = true

        store.moveObject(first.id, .toFront)

        #expect(store.objectsFrontToBack.map(\.id) == [first.id, second.id])
    }

    @Test func reorderObjectsMatchesListOnMoveSemantics() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store)
        let second = makeRectangle(in: store)
        let third = makeRectangle(in: store)
        // Front-to-back vor dem Umsortieren: [third, second, first]

        store.reorderObjects(fromFrontToBackOffsets: IndexSet(integer: 0), toFrontToBackOffset: 3)

        #expect(store.objectsFrontToBack.map(\.id) == [second.id, first.id, third.id])
    }

    @Test func toggleVisibilityFlipsIsVisible() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        #expect(object.isVisible)

        store.toggleVisibility(of: object.id)
        #expect(!object.isVisible)

        store.toggleVisibility(of: object.id)
        #expect(object.isVisible)
    }

    @Test func toggleLockFlipsIsLocked() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        #expect(!object.isLocked)

        store.toggleLock(of: object.id)
        #expect(object.isLocked)

        store.toggleLock(of: object.id)
        #expect(!object.isLocked)
    }

    @Test func deleteObjectRemovesItAndClearsSelectionIfSelected() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        #expect(store.selectedObjectID == object.id)

        store.deleteObject(object.id)

        #expect(store.objects.isEmpty)
        #expect(store.selectedObjectID == nil)
    }

    @Test func deleteObjectLeavesSelectionUntouchedForOtherObjects() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let first = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        let second = makeRectangle(in: store, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 50, y: 50))
        #expect(store.selectedObjectID == second.id)

        store.deleteObject(first.id)

        #expect(store.objects.map(\.id) == [second.id])
        #expect(store.selectedObjectID == second.id)
    }

    @Test func deleteSelectedObjectDeletesCurrentSelectionOnly() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        _ = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        let second = makeRectangle(in: store, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 50, y: 50))

        store.deleteSelectedObject()

        #expect(store.objects.count == 1)
        #expect(store.objects.first?.id != second.id)
    }

    @Test func deleteSelectedObjectDoesNothingWithoutSelection() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        _ = makeRectangle(in: store)
        store.selectObject(nil)

        store.deleteSelectedObject()

        #expect(store.objects.count == 1)
    }

    @Test func deletingLockedObjectAlsoRemovesIt() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        store.toggleLock(of: object.id)

        store.deleteObject(object.id)

        #expect(store.objects.isEmpty)
    }

    // MARK: Garnfarben-Zuweisung (8e)

    @Test func assignColorSetsThreadColorAndMatchingFillHex() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)

        store.assignColor(name: "Rot", red: 255, green: 0, blue: 0, catalogNumber: "R-1", to: object.id)

        #expect(object.threadColor?.name == "Rot")
        #expect(object.threadColor?.red == 255)
        #expect(object.threadColor?.catalogNumber == "R-1")
        #expect(object.fillColorHex == "#FF0000")
    }

    @Test func assignColorToUnknownIDDoesNothing() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makeRectangle(in: store)
        let originalHex = object.fillColorHex

        store.assignColor(name: "Rot", red: 255, green: 0, blue: 0, catalogNumber: nil, to: UUID())

        #expect(object.threadColor == nil)
        #expect(object.fillColorHex == originalHex)
    }

    // MARK: Live-Stichvorschau (6e)

    @Test func selectingObjectWithStitchSettingsPopulatesStitchPreview() async throws {
        let mockStitches = [StitchPoint(x: 0, y: 0, command: .stitch), StitchPoint(x: 5, y: 0, command: .stitch)]
        let mockService = MockStitchGenerationService(stitchesToReturn: mockStitches)
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100), stitchGenerationService: mockService)
        let object = makeRectangle(in: store)
        object.stitchSettings = StitchSettings(stitchType: .tatami, density: 0.4, angleDegrees: 0, underlayType: .none)

        store.selectObject(nil) // Auswahl aufheben, damit der nächste Aufruf tatsächlich einen Wechsel auslöst
        #expect(store.stitchPreview == nil)

        store.selectObject(object.id)
        // Debounce (CanvasStore.stitchPreviewDebounce) abwarten, bevor die Vorschau gesetzt wird.
        try await Task.sleep(for: .milliseconds(400))

        #expect(store.stitchPreview == mockStitches)
    }

    @Test func deselectingObjectClearsStitchPreview() {
        let mockService = MockStitchGenerationService(stitchesToReturn: [StitchPoint(x: 0, y: 0, command: .stitch)])
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100), stitchGenerationService: mockService)
        let object = makeRectangle(in: store)
        object.stitchSettings = StitchSettings(stitchType: .tatami, density: 0.4, angleDegrees: 0, underlayType: .none)

        store.selectObject(object.id)
        store.selectObject(nil)

        #expect(store.stitchPreview == nil)
    }

    @Test func selectingObjectWithoutStitchSettingsClearsStitchPreview() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100), stitchGenerationService: MockStitchGenerationService())
        let object = makeRectangle(in: store)

        store.selectObject(object.id)

        #expect(store.stitchPreview == nil)
    }

    // MARK: Fehlersichtbarkeit (6f)

    @Test func failedGenerationSurfacesErrorAndClearsPreview() async throws {
        struct DummyError: LocalizedError {
            var errorDescription: String? { "Stichgenerierung fehlgeschlagen: Testfehler" }
        }
        let mockService = MockStitchGenerationService(errorToThrow: DummyError())
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100), stitchGenerationService: mockService)
        let object = makeRectangle(in: store)
        object.stitchSettings = StitchSettings(stitchType: .satin, density: 0.4, angleDegrees: 0, underlayType: .none)

        store.selectObject(nil)
        store.selectObject(object.id)
        try await Task.sleep(for: .milliseconds(400))

        #expect(store.stitchPreview == nil)
        #expect(store.stitchPreviewError == "Stichgenerierung fehlgeschlagen: Testfehler")
    }

    // MARK: Mehrfachauswahl & Gruppierung (Issue #16)

    /// Zwei Rechtecke bei (0,0)-(10,10) und (20,0)-(30,10), gruppiert — Gruppenrahmen ist damit
    /// exakt (0,0,30,10), Gruppenzentrum (15,5). Von den Rotations-/Skalierungstests unten genutzt,
    /// die auf diesen konkreten Zahlen aufbauen.
    @discardableResult
    private func makeGroupOfTwoRectangles(in store: CanvasStore) -> (DesignObject, DesignObject) {
        let a = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
        let b = makeRectangle(in: store, from: CGPoint(x: 20, y: 0), to: CGPoint(x: 30, y: 10))
        store.replaceSelection([a.id, b.id])
        store.groupSelectedObjects()
        return (a, b)
    }

    @Test func groupingFewerThanTwoObjectsDoesNothing() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let a = makeRectangle(in: store)
        store.replaceSelection([a.id])
        store.groupSelectedObjects()
        #expect(a.groupID == nil)
    }

    @Test func groupSelectedObjectsAssignsSharedGroupIDAndExposesGroupBounds() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)

        #expect(a.groupID != nil)
        #expect(a.groupID == b.groupID)
        #expect(store.selectedGroupID == a.groupID)
        #expect(store.selectedGroupBounds == CGRect(x: 0, y: 0, width: 30, height: 10))
    }

    @Test func groupingMakesMemberZIndicesContiguous() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let a = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
        makeRectangle(in: store, from: CGPoint(x: 40, y: 40), to: CGPoint(x: 50, y: 50)) // liegt dazwischen
        let b = makeRectangle(in: store, from: CGPoint(x: 20, y: 0), to: CGPoint(x: 30, y: 10))
        store.replaceSelection([a.id, b.id])
        store.groupSelectedObjects()

        let indices = store.objectsFrontToBack.enumerated().compactMap { index, object in
            (object.id == a.id || object.id == b.id) ? index : nil
        }
        #expect(indices.count == 2)
        #expect(abs(indices[0] - indices[1]) == 1)
    }

    @Test func ungroupSelectedObjectsClearsGroupIDButKeepsSelection() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)
        store.ungroupSelectedObjects()

        #expect(a.groupID == nil)
        #expect(b.groupID == nil)
        #expect(store.selectedObjectIDs == Set([a.id, b.id]))
        #expect(store.selectedGroupID == nil)
    }

    @Test func ungroupByIDWorksIndependentOfCurrentSelection() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)
        let groupID = a.groupID!
        store.selectObject(nil)

        store.ungroup(groupID: groupID)

        #expect(a.groupID == nil)
        #expect(b.groupID == nil)
    }

    @Test func clickingGroupMemberSelectsWholeGroup() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)
        store.selectObject(nil)

        store.beginTransformDrag(object: a, handle: nil, atDesignPoint: CGPoint(x: 5, y: 5))

        #expect(store.selectedObjectIDs == Set([a.id, b.id]))
    }

    @Test func toggleSelectionOnGroupMemberTogglesWholeGroup() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)
        store.selectObject(nil)

        store.toggleSelection(of: a.id)
        #expect(store.selectedObjectIDs == Set([a.id, b.id]))

        store.toggleSelection(of: b.id)
        #expect(store.selectedObjectIDs.isEmpty)
    }

    @Test func partialGroupSelectionExposesNeitherGroupNorSingleObjectAmbiguity() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, _) = makeGroupOfTwoRectangles(in: store)
        store.replaceSelection([a.id])

        #expect(store.selectedGroupID == nil)
        #expect(store.selectedGroupBounds == nil)
        #expect(store.selectedObject?.id == a.id) // Einzelauswahl-Ansicht bleibt für dieses eine Mitglied nutzbar.
    }

    @Test func marqueeSelectionAddsIntersectingObjectsAndExpandsHitGroupsToFullMembership() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)
        let lone = makeRectangle(in: store, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 60, y: 60))
        store.selectObject(nil)

        store.beginMarqueeSelection(atDesignPoint: CGPoint(x: -5, y: -5))
        store.updateMarqueeSelection(toDesignPoint: CGPoint(x: 12, y: 12)) // schneidet nur `a`, nicht `b`
        store.endMarqueeSelection()

        #expect(store.selectedObjectIDs == Set([a.id, b.id])) // Treffer auf ein Mitglied erweitert auf die ganze Gruppe.
        #expect(!store.selectedObjectIDs.contains(lone.id))
        #expect(store.marqueeRect == nil) // zurückgesetzt nach Abschluss.
    }

    @Test func deleteSelectedObjectRemovesEveryObjectInMultiSelection() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let a = makeRectangle(in: store, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
        let b = makeRectangle(in: store, from: CGPoint(x: 20, y: 0), to: CGPoint(x: 30, y: 10))
        store.replaceSelection([a.id, b.id])

        store.deleteSelectedObject()

        #expect(store.objects.isEmpty)
        #expect(store.selectedObjectIDs.isEmpty)
    }

    @Test func groupMoveTranslatesAllMembersByTheSameDelta() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)

        store.beginGroupTransformDrag(handle: nil, atDesignPoint: CGPoint(x: 15, y: 5))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 25, y: 15))
        store.endTransformDrag()

        #expect(abs(a.positionX - 10) < 0.001)
        #expect(abs(a.positionY - 10) < 0.001)
        #expect(abs(b.positionX - 30) < 0.001)
        #expect(abs(b.positionY - 10) < 0.001)
    }

    /// Dreht die Gruppe (Rahmen (0,0,30,10), Zentrum (15,5)) um 90° — starrer Körper: beide
    /// Mitglieder behalten ihren Abstand zum Gruppenzentrum, wandern aber auf der Kreisbahn mit,
    /// und `rotationDegrees` jedes Mitglieds erhöht sich um denselben Delta-Winkel.
    @Test func groupRotationRotatesMembersRigidlyAroundGroupCenter() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)

        store.beginGroupTransformDrag(handle: .rotate, atDesignPoint: CGPoint(x: 15, y: -8))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 100, y: 5)) // Winkel 0° -> Delta 90°
        store.endTransformDrag()

        #expect(abs(a.positionX - 10) < 0.001)
        #expect(abs(a.positionY - (-10)) < 0.001)
        #expect(abs(a.rotationDegrees - 90) < 0.001)

        #expect(abs(b.positionX - 10) < 0.001)
        #expect(abs(b.positionY - 10) < 0.001)
        #expect(abs(b.rotationDegrees - 90) < 0.001)
    }

    /// Skaliert die Gruppe über den unten-rechts-Griff (Anker oben-links, (0,0)) — Breite ×2,
    /// Höhe ×0.5. Beide Mitglieder behalten ihre Grösse relativ zum Anker skaliert.
    @Test func groupResizeScalesMembersRelativeToFixedAnchor() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 200, height: 200))
        let (a, b) = makeGroupOfTwoRectangles(in: store)

        store.beginGroupTransformDrag(handle: .bottomRight, atDesignPoint: CGPoint(x: 30, y: 10))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 60, y: 5))
        store.endTransformDrag()

        #expect(abs(a.positionX - 0) < 0.001)
        #expect(abs(a.positionY - 0) < 0.001)
        #expect(abs(a.width - 20) < 0.001)
        #expect(abs(a.height - 5) < 0.001)

        #expect(abs(b.positionX - 40) < 0.001)
        #expect(abs(b.positionY - 0) < 0.001)
        #expect(abs(b.width - 20) < 0.001)
        #expect(abs(b.height - 5) < 0.001)
    }

    @Test func groupTransformDragIsBlockedIfAnyMemberIsLocked() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let (a, b) = makeGroupOfTwoRectangles(in: store)
        b.isLocked = true

        store.beginGroupTransformDrag(handle: nil, atDesignPoint: CGPoint(x: 15, y: 5))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 25, y: 15))

        #expect(a.positionX == 0) // Drag wurde gar nicht erst gestartet.
    }
}
