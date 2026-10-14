//
//  CanvasStoreGuideTests.swift
//  SimplStitchTests
//
//  Issue #31 (Phase 1): Hilfslinien anlegen, verschieben, löschen, Trefferzone und Undo/Redo,
//  sowie der content.svg-Roundtrip.
//

import Testing
import Foundation
import CoreGraphics
@testable import SimplStitch

@MainActor
struct CanvasStoreGuideTests {

    private func makeStore() -> CanvasStore {
        CanvasStore(canvasSizeMillimeters: CGSize(width: 100, height: 80))
    }

    @Test func draggingFromRulerCreatesGuideOnCommit() {
        let store = makeStore()
        store.beginNewGuide(orientation: .horizontal, atDesignPoint: CGPoint(x: 10, y: 5))
        store.updateNewGuide(toDesignPoint: CGPoint(x: 30, y: 42.5))
        #expect(store.draftGuide?.position == 42.5)
        #expect(store.guides.isEmpty)

        store.commitNewGuide()
        #expect(store.draftGuide == nil)
        #expect(store.guides.count == 1)
        #expect(store.guides[0].orientation == .horizontal)
        #expect(store.guides[0].position == 42.5)
    }

    @Test func verticalGuideUsesXCoordinate() {
        let store = makeStore()
        store.beginNewGuide(orientation: .vertical, atDesignPoint: CGPoint(x: 12, y: 70))
        store.commitNewGuide()
        #expect(store.guides.first?.position == 12)
    }

    @Test func cancelledDraftCreatesNoGuide() {
        let store = makeStore()
        store.beginNewGuide(orientation: .vertical, atDesignPoint: CGPoint(x: 20, y: 0))
        store.cancelNewGuide()
        #expect(store.draftGuide == nil)
        #expect(store.guides.isEmpty)
    }

    @Test func hitTestUsesScreenPointToleranceIndependentOfZoom() {
        let store = makeStore()
        store.addGuideAtCanvasCenter(orientation: .vertical) // x = 50mm
        store.setZoomScale(2)
        // View-x = 50mm * 2 = 100pt (panOffset 0). 4pt daneben trifft, 6pt daneben nicht.
        #expect(store.guide(atViewPoint: CGPoint(x: 104, y: 10)) != nil)
        #expect(store.guide(atViewPoint: CGPoint(x: 106, y: 10)) == nil)
    }

    @Test func hiddenGuidesAreNotHit() {
        let store = makeStore()
        store.addGuideAtCanvasCenter(orientation: .horizontal) // y = 40mm
        store.areGuidesVisible = false
        #expect(store.guide(atViewPoint: CGPoint(x: 10, y: 40)) == nil)
    }

    @Test func movingGuideUpdatesPosition() {
        let store = makeStore()
        store.addGuideAtCanvasCenter(orientation: .horizontal)
        let id = store.guides[0].id
        store.beginGuideDrag(id)
        store.updateGuideDrag(toDesignPoint: CGPoint(x: 99, y: 12))
        store.endGuideDrag(remove: false)
        #expect(store.guides.count == 1)
        #expect(store.guides[0].position == 12)
    }

    @Test func draggingGuideBackOntoRulerRemovesIt() {
        let store = makeStore()
        store.addGuideAtCanvasCenter(orientation: .vertical)
        store.beginGuideDrag(store.guides[0].id)
        store.updateGuideDrag(toDesignPoint: CGPoint(x: -3, y: 10))
        store.endGuideDrag(remove: true)
        #expect(store.guides.isEmpty)
    }

    @Test func undoAndRedoCoverAddMoveAndDelete() {
        let store = makeStore()
        let undoManager = UndoManager()
        // Ohne laufende Run-Loop würde `groupsByEvent` alle drei Schritte in eine Gruppe packen —
        // explizite Gruppen bilden die drei getrennten Nutzeraktionen nach.
        undoManager.groupsByEvent = false
        store.undoManager = undoManager
        func step(_ action: () -> Void) {
            undoManager.beginUndoGrouping()
            action()
            undoManager.endUndoGrouping()
        }

        step {
            store.beginNewGuide(orientation: .horizontal, atDesignPoint: CGPoint(x: 0, y: 20))
            store.commitNewGuide()
        }
        let id = store.guides[0].id

        step {
            store.beginGuideDrag(id)
            store.updateGuideDrag(toDesignPoint: CGPoint(x: 0, y: 30))
            store.endGuideDrag(remove: false)
        }

        step { store.removeGuide(id) }
        #expect(store.guides.isEmpty)

        undoManager.undo()
        #expect(store.guides.first?.position == 30)
        undoManager.undo()
        #expect(store.guides.first?.position == 20)
        undoManager.undo()
        #expect(store.guides.isEmpty)

        undoManager.redo()
        #expect(store.guides.first?.position == 20)
    }

    @Test func clickOnGuideWithoutMovementRegistersNoUndoStep() {
        let store = makeStore()
        store.addGuideAtCanvasCenter(orientation: .horizontal)
        let undoManager = UndoManager()
        store.undoManager = undoManager

        store.beginGuideDrag(store.guides[0].id)
        store.endGuideDrag(remove: false)
        #expect(!undoManager.canUndo)
    }

    @Test func removeAllGuidesClearsList() {
        let store = makeStore()
        store.addGuideAtCanvasCenter(orientation: .horizontal)
        store.addGuideAtCanvasCenter(orientation: .vertical)
        store.removeAllGuides()
        #expect(store.guides.isEmpty)
    }

    // MARK: content.svg-Roundtrip

    @Test func guidesSurviveSVGRoundtrip() throws {
        let serializer = SVGDesignSerializer()
        let guides = [
            Guide(orientation: .horizontal, position: 42.5),
            Guide(orientation: .vertical, position: 12.25),
        ]
        let svg = serializer.encode(
            objects: [],
            canvasSize: CGSize(width: 100, height: 80),
            backgroundImageFileName: nil,
            guides: guides
        )
        let decoded = try serializer.decode(svg: svg)
        #expect(decoded.objects.isEmpty)
        #expect(decoded.guides.map(\.orientation) == [.horizontal, .vertical])
        #expect(decoded.guides.map(\.position) == [42.5, 12.25])
    }

    @Test func fileWithoutGuidesDecodesToEmptyList() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="80mm" viewBox="0 0 100 80">
          <line x1="0" y1="0" x2="10" y2="10" stroke="#000"/>
        </svg>
        """
        let decoded = try SVGDesignSerializer().decode(svg: svg)
        #expect(decoded.guides.isEmpty)
    }
}
