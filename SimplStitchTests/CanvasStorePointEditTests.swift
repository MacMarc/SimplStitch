//
//  CanvasStorePointEditTests.swift
//  SimplStitchTests
//
//  Issue #19 (Punktgenaues Editieren) — Schritt B2: Anker-/Kontrollpunkt-Griffe und Punkt-Editier-
//  Interaktionsmodus. Von Hand durchgerechnete Erwartungswerte, wie bei den übrigen Transform-Tests
//  (Skew/Rotation/Gruppen-Transformationen).
//

import Testing
import Foundation
import CoreGraphics
@testable import SimplStitch

@MainActor
struct CanvasStorePointEditTests {

    /// Erzeugt ein `.path`-Objekt über den normalen Zeichen-Flow (Freihand-Pfad-Werkzeug, zwei
    /// Klick-Punkte reichen für eine gültige Mindestgrösse) und ersetzt danach `pathData` durch den
    /// für den jeweiligen Test benötigten exakten Pfadstring — der Draft-Flow selbst kann nur
    /// gerade M/L-Segmente erzeugen, keine Kurven.
    private func makePathObject(in store: CanvasStore, pathData: String) -> DesignObject {
        store.selectTool(.path)
        store.beginDraft(atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateDraft(toDesignPoint: CGPoint(x: 10, y: 10))
        let object = store.commitDraft()!
        object.pathData = pathData
        store.selectTool(.select)
        return object
    }

    @Test func beginPointEditingEntersModeForPathObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000")

        store.beginPointEditing(object.id)

        #expect(store.pointEditingObjectID == object.id)
        #expect(store.selectedObjectID == object.id)
    }

    @Test func beginPointEditingIgnoresRectangle() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateDraft(toDesignPoint: CGPoint(x: 10, y: 10))
        let object = store.commitDraft()!

        store.beginPointEditing(object.id)

        #expect(store.pointEditingObjectID == nil)
    }

    @Test func beginPointEditingIgnoresLockedObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        object.isLocked = true

        store.beginPointEditing(object.id)

        #expect(store.pointEditingObjectID == nil)
    }

    @Test func endPointEditingClearsState() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.endPointEditing()

        #expect(store.pointEditingObjectID == nil)
        #expect(store.activePointEditAnchorIndex == nil)
    }

    @Test func selectingAnotherObjectExitsPointEditMode() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        let other = makePathObject(in: store, pathData: "M20.0000,20.0000 L30.0000,20.0000")
        store.beginPointEditing(object.id)

        store.selectObject(other.id)

        #expect(store.pointEditingObjectID == nil)
    }

    @Test func selectingSameObjectKeepsPointEditMode() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.selectObject(object.id)

        #expect(store.pointEditingObjectID == object.id)
    }

    @Test func switchingToolExitsPointEditMode() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.selectTool(.rectangle)

        #expect(store.pointEditingObjectID == nil)
    }

    @Test func pointEditAnchorPositionsListsAllAnchors() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000")
        store.beginPointEditing(object.id)

        let positions = store.pointEditAnchorPositions(for: object)

        #expect(positions[.anchor(0)] == CGPoint(x: 0, y: 0))
        #expect(positions[.anchor(1)] == CGPoint(x: 10, y: 0))
        #expect(positions[.anchor(2)] == CGPoint(x: 10, y: 10))
        // Kein aktiver Anker gesetzt -> keine Kontrollpunkte in der Liste (hier ohnehin keine vorhanden).
        #expect(positions[.controlIn(0)] == nil)
    }

    @Test func pointEditHandleFindsNearbyAnchor() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        let handle = store.pointEditHandle(atDesignPoint: CGPoint(x: 10.1, y: 0.1), for: object)

        #expect(handle == .anchor(1))
    }

    @Test func draggingAnchorMovesPointAndRecomputesBounds() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000")
        store.beginPointEditing(object.id)

        store.beginPointEditDrag(object: object, component: .anchor(1), atDesignPoint: CGPoint(x: 10, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 15, y: 5))
        store.endTransformDrag()

        // Von Hand durchgerechnet: Anker 1 (10,0) -> (15,5), Anker 0/2 unverändert. Neue Bounding-Box
        // über alle drei Punkte {(0,0),(15,5),(10,10)}: minX=0, maxX=15, minY=0, maxY=10.
        #expect(object.pathData == "M0.0000,0.0000 L15.0000,5.0000 L10.0000,10.0000")
        #expect(object.positionX == 0)
        #expect(object.positionY == 0)
        #expect(object.width == 15)
        #expect(object.height == 10)
    }

    @Test func draggingAnchorMovesAttachedControlPointsWithIt() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        // Anker 0: (0,0) controlOut (3,6); Anker 1: (10,0) controlIn (7,6).
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
        store.beginPointEditing(object.id)

        // Anker 0 von (0,0) nach (2,3) ziehen -> Delta (2,3) -> controlOut wandert von (3,6) auf (5,9).
        store.beginPointEditDrag(object: object, component: .anchor(0), atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 2, y: 3))
        store.endTransformDrag()

        #expect(object.pathData == "M2.0000,3.0000 C5.0000,9.0000 7.0000,6.0000 10.0000,0.0000")
    }

    @Test func draggingControlHandleSetsItDirectlyWithoutMovingAnchor() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.beginPointEditDrag(object: object, component: .controlOut(0), atDesignPoint: CGPoint(x: 3, y: 6))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 5, y: 8))
        store.endTransformDrag()

        // Kontrollpunkt wird direkt auf den Zielpunkt gesetzt (kein Delta) — der Anker selbst (0,0)
        // bleibt unverändert, nur controlOut ändert sich.
        #expect(object.pathData == "M0.0000,0.0000 C5.0000,8.0000 7.0000,6.0000 10.0000,0.0000")
    }

    @Test func activeAnchorControlPointsAppearAfterDrag() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.beginPointEditDrag(object: object, component: .anchor(0), atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 0, y: 0))
        store.endTransformDrag()

        #expect(store.activePointEditAnchorIndex == 0)
        let positions = store.pointEditAnchorPositions(for: object)
        #expect(positions[.controlOut(0)] == CGPoint(x: 3, y: 6))
    }

    @Test func pointEditDragIgnoresLockedObject() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        let originalPathData = object.pathData
        object.isLocked = true

        store.beginPointEditDrag(object: object, component: .anchor(0), atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 5, y: 5))

        #expect(object.pathData == originalPathData)
    }

    // MARK: Linie-Biegepunkte (Issue #19, Schritt B3)

    @Test func segmentMidpointHandleAppearsForStraightSegment() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        let positions = store.pointEditAnchorPositions(for: object)

        #expect(positions[.segmentMidpoint(0)] == CGPoint(x: 5, y: 0))
    }

    @Test func segmentMidpointHandleAbsentForAlreadyCurvedSegment() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
        store.beginPointEditing(object.id)

        let positions = store.pointEditAnchorPositions(for: object)

        #expect(positions[.segmentMidpoint(0)] == nil)
    }

    @Test func draggingSegmentMidpointBendsStraightSegmentIntoCurve() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.beginPointEditDrag(object: object, component: .segmentMidpoint(0), atDesignPoint: CGPoint(x: 5, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 5, y: 4))
        store.endTransformDrag()

        // Von Hand durchgerechnet (Qc = 2*drag - 0.5*(P0+P2) = (5,8), dann 2/3-Regel):
        // C1 = (3.3333, 5.3333), C2 = (6.6667, 5.3333).
        #expect(object.pathData == "M0.0000,0.0000 C3.3333,5.3333 6.6667,5.3333 10.0000,0.0000")
        // Bounding-Box über alle Punkte inkl. Kontrollpunkte: minY=0, maxY=5.3333.
        #expect(object.positionY == 0)
        #expect(abs(object.height - 5.3333) < 0.001)
        // Der Start-Anker des gebogenen Segments wird zum aktiven Anker (seine neuen
        // Kontrollpunkte sollen sofort sichtbar/feinjustierbar sein).
        #expect(store.activePointEditAnchorIndex == 0)
    }

    @Test func draggingSegmentMidpointBackOntoChordCollapsesToStraightLine() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.beginPointEditDrag(object: object, component: .segmentMidpoint(0), atDesignPoint: CGPoint(x: 5, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 5, y: 4))
        store.endTransformDrag()
        #expect(object.pathData!.contains("C"))

        // Erneut anfassen (jetzt als aktiver Kontrollpunkt-Anker) und zurück auf die Sehne ziehen —
        // innerhalb der Kollaps-Toleranz zählt das als "wieder gerade".
        store.beginPointEditDrag(object: object, component: .segmentMidpoint(0), atDesignPoint: CGPoint(x: 5, y: 4))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 5, y: 0.05))
        store.endTransformDrag()

        #expect(object.pathData == "M0.0000,0.0000 L10.0000,0.0000")
    }

    @Test func bentSegmentShowsControlHandlesInsteadOfMidpointHandle() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        store.beginPointEditing(object.id)

        store.beginPointEditDrag(object: object, component: .segmentMidpoint(0), atDesignPoint: CGPoint(x: 5, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 5, y: 4))
        store.endTransformDrag()

        let positions = store.pointEditAnchorPositions(for: object)
        #expect(positions[.segmentMidpoint(0)] == nil)
        #expect(positions[.controlOut(0)] != nil)
    }

    @Test func undoRevertsPointEditAndRedoReappliesIt() {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 100))
        let undoManager = UndoManager()
        store.undoManager = undoManager
        let object = makePathObject(in: store, pathData: "M0.0000,0.0000 L10.0000,0.0000")
        let originalPathData = object.pathData
        store.beginPointEditing(object.id)

        store.beginPointEditDrag(object: object, component: .anchor(1), atDesignPoint: CGPoint(x: 10, y: 0))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 20, y: 20))
        store.endTransformDrag()
        let editedPathData = object.pathData
        #expect(editedPathData != originalPathData)

        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(object.pathData == originalPathData)

        #expect(undoManager.canRedo)
        undoManager.redo()
        #expect(object.pathData == editedPathData)
    }
}
