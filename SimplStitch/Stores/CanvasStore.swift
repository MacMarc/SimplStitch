//
//  CanvasStore.swift
//  SimplStitch
//
//  Zeichenfläche: Zoom/Pan-Zustand und die Umrechnung zwischen Design-
//  Koordinaten (Millimeter, Ursprung oben-links — wie content.svg, Phase 4)
//  und View-Koordinaten (Punkte). Formen/Selektion/Handles folgen in 5b–5c.
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

    init(canvasSizeMillimeters: CGSize, zoomScale: CGFloat = 1, panOffset: CGSize = .zero) {
        self.canvasSizeMillimeters = canvasSizeMillimeters
        self.zoomScale = min(max(zoomScale, Self.minZoomScale), Self.maxZoomScale)
        self.panOffset = panOffset
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
}
