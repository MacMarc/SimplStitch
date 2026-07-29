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
}
