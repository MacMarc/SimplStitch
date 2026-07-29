//
//  CanvasView.swift
//  SimplStitch
//
//  Basis-Zeichenfläche: rendert die Stickfläche (weisses Rechteck in
//  Canvas-Grösse) mit einem 10mm-Raster zur Orientierung, Zoom per
//  Trackpad-Pinch, Pan per Klick-Drag. Formen/Selektion/Text folgen in
//  den nächsten Unteraufgaben (5b–5e).
//

import SwiftUI

struct CanvasView: View {
    let store: CanvasStore

    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveDragTranslation: CGSize = .zero

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
            Canvas { context, _ in
                drawCanvasBackground(in: &context)
                drawGrid(in: &context)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .gesture(panGesture)
            .gesture(magnificationGesture)
            .onAppear {
                store.zoomToFit(viewportSize: proxy.size)
            }
        }
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

    private var panGesture: some Gesture {
        DragGesture()
            .updating($liveDragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                store.pan(by: value.translation)
            }
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
}

#Preview {
    CanvasView(store: CanvasStore(canvasSizeMillimeters: CGSize(width: 130, height: 180)))
}
