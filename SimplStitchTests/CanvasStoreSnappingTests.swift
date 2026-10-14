//
//  CanvasStoreSnappingTests.swift
//  SimplStitchTests
//
//  Issue #31 (Phase 2 + 3): Einrasten an Objektkanten/-mitten, Canvas-Mitte und Hilfslinien,
//  ⌘ zum Aussetzen, Ausrichtungslinien während des Drags.
//

import Testing
import Foundation
import CoreGraphics
@testable import SimplStitch

@MainActor
struct CanvasStoreSnappingTests {

    /// Zoom 4 → Toleranz 8pt / 4 = 2mm, damit die Testgeometrie eindeutig bleibt. Der Convenience-Init
    /// schaltet Einrasten ab (siehe CanvasStore), hier wird es explizit eingeschaltet.
    private func makeStore() -> CanvasStore {
        let store = CanvasStore(canvasSizeMillimeters: CGSize(width: 200, height: 160), zoomScale: 4)
        store.isSnappingEnabled = true
        return store
    }

    private func makeRectangle(in store: CanvasStore, from: CGPoint, to: CGPoint) -> DesignObject {
        store.selectTool(.rectangle)
        store.beginDraft(atDesignPoint: from)
        store.updateDraft(toDesignPoint: to)
        return store.commitDraft()!
    }

    @Test func nearestSnapPicksSmallestOffsetWithinTolerance() {
        let snap = CanvasStore.nearestSnap(moving: [10, 20], candidates: [11.5, 19.5, 40], tolerance: 2)
        #expect(snap?.target == 19.5)
        #expect(snap?.offset == -0.5)
        #expect(CanvasStore.nearestSnap(moving: [10], candidates: [13], tolerance: 2) == nil)
    }

    @Test func movedObjectSnapsToOtherObjectsEdge() {
        let store = makeStore()
        _ = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        let moving = makeRectangle(in: store, from: CGPoint(x: 50, y: 10), to: CGPoint(x: 70, y: 30))

        store.beginTransformDrag(object: moving, handle: nil, atDesignPoint: CGPoint(x: 60, y: 20))
        // Linke Kante landet roh bei 31.5 und rastet an der rechten Kante des anderen Objekts (30) ein.
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 41.5, y: 20))
        #expect(moving.positionX == 30)
        #expect(store.activeSnapLines.contains(CanvasStore.SnapLine(orientation: .vertical, position: 30)))

        store.endTransformDrag()
        #expect(store.activeSnapLines.isEmpty)
    }

    @Test func commandKeySuspendsSnappingForTheDrag() {
        let store = makeStore()
        _ = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        let moving = makeRectangle(in: store, from: CGPoint(x: 50, y: 10), to: CGPoint(x: 70, y: 30))

        store.beginTransformDrag(object: moving, handle: nil, atDesignPoint: CGPoint(x: 60, y: 20))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 41.5, y: 20), disableSnapping: true)
        #expect(moving.positionX == 31.5)
        #expect(store.activeSnapLines.isEmpty)
        store.endTransformDrag()
    }

    @Test func disabledSnappingLeavesDragUnchanged() {
        let store = makeStore()
        store.isSnappingEnabled = false
        _ = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        let moving = makeRectangle(in: store, from: CGPoint(x: 50, y: 10), to: CGPoint(x: 70, y: 30))

        store.beginTransformDrag(object: moving, handle: nil, atDesignPoint: CGPoint(x: 60, y: 20))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 41.5, y: 20))
        #expect(moving.positionX == 31.5)
        store.endTransformDrag()
    }

    @Test func objectCenterSnapsToCanvasCenter() {
        let store = makeStore()
        let object = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))

        store.beginTransformDrag(object: object, handle: nil, atDesignPoint: CGPoint(x: 20, y: 20))
        // Mitte landet roh bei 99, rastet an der Canvas-Mitte (100) ein.
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 99, y: 20))
        #expect(object.positionX == 90)
        store.endTransformDrag()
    }

    @Test func objectDoesNotSnapToItsOwnStartPosition() {
        let store = makeStore()
        let object = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))

        store.beginTransformDrag(object: object, handle: nil, atDesignPoint: CGPoint(x: 20, y: 20))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 20.5, y: 20))
        #expect(object.positionX == 10.5)
        store.endTransformDrag()
    }

    @Test func resizedEdgeSnapsToOtherObject() {
        let store = makeStore()
        let resized = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        _ = makeRectangle(in: store, from: CGPoint(x: 50, y: 10), to: CGPoint(x: 70, y: 30))

        store.beginTransformDrag(object: resized, handle: .right, atDesignPoint: CGPoint(x: 30, y: 20))
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 49, y: 20))
        #expect(resized.width == 40)
        store.endTransformDrag()
    }

    @Test func objectSnapsToGuide() {
        let store = makeStore()
        store.addGuideAtCanvasCenter(orientation: .horizontal) // y = 80mm
        let object = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))

        store.beginTransformDrag(object: object, handle: nil, atDesignPoint: CGPoint(x: 20, y: 20))
        // Unterkante landet roh bei 78.5, rastet an der Hilfslinie (80) ein.
        store.updateTransformDrag(toDesignPoint: CGPoint(x: 20, y: 68.5))
        #expect(object.positionY == 60)
        #expect(store.activeSnapLines.contains(CanvasStore.SnapLine(orientation: .horizontal, position: 80)))
        store.endTransformDrag()
    }

    @Test func newGuideSnapsToObjectEdge() {
        let store = makeStore()
        _ = makeRectangle(in: store, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))

        store.beginNewGuide(orientation: .vertical, atDesignPoint: CGPoint(x: 0, y: 0))
        store.updateNewGuide(toDesignPoint: CGPoint(x: 29, y: 50))
        #expect(store.draftGuide?.position == 30)
        store.commitNewGuide()
        #expect(store.guides.first?.position == 30)
        #expect(store.activeSnapLines.isEmpty)
    }

    @Test func movedGuideDoesNotSnapBackToItsOwnStartPosition() throws {
        let store = makeStore()
        store.beginNewGuide(orientation: .vertical, atDesignPoint: CGPoint(x: 40, y: 0))
        store.commitNewGuide()
        let id = try #require(store.guides.first?.id)

        store.beginGuideDrag(id)
        store.updateGuideDrag(toDesignPoint: CGPoint(x: 41, y: 0))
        #expect(store.guides.first?.position == 41)
        // Nahe an der Canvas-Mitte rastet sie dagegen ein.
        store.updateGuideDrag(toDesignPoint: CGPoint(x: 98.5, y: 0))
        #expect(store.guides.first?.position == 100)
        store.endGuideDrag(remove: false)
        #expect(store.activeSnapLines.isEmpty)
    }
}
