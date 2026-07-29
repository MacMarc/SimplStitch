//
//  PreviewImageRenderer.swift
//  SimplStitch
//
//  Erzeugt preview.png fürs Document Package (QuickLook). Vor der
//  Canvas-Engine (Phase 5) gibt es noch keinen echten Renderer — Formen
//  werden hier bewusst vereinfacht (Bounding-Box statt exaktem Pfad)
//  gezeichnet. Sobald Phase 5 einen Canvas-Renderer hat, sollte dieser
//  hier wiederverwendet statt dupliziert werden.
//
//  Text (5d): läuft direkt über CoreText (CTLine), nicht über den
//  SwiftUI-GraphicsContext des Canvas-Renderers — dieser Service arbeitet mit
//  einem rohen CGContext, daher kein gemeinsamer Code mit CanvasView.drawText.
//

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

protocol PreviewImageRendering {
    func renderPreviewPNG(objects: [DesignObject], canvasSize: CGSize) -> Data?
}

final class PreviewImageRenderer: PreviewImageRendering {
    private let pixelsPerMillimeter: CGFloat = 4

    func renderPreviewPNG(objects: [DesignObject], canvasSize: CGSize) -> Data? {
        let width = max(Int(canvasSize.width * pixelsPerMillimeter), 1)
        let height = max(Int(canvasSize.height * pixelsPerMillimeter), 1)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let scale = pixelsPerMillimeter
        for object in objects.sorted(by: { $0.zIndex < $1.zIndex }) where object.isVisible {
            draw(object, in: context, scale: scale, canvasHeightPixels: CGFloat(height))
        }

        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func draw(_ object: DesignObject, in context: CGContext, scale: CGFloat, canvasHeightPixels: CGFloat) {
        let color = CGColor.fromHex(object.fillColorHex) ?? CGColor(gray: 0, alpha: 1)
        context.setFillColor(color)
        context.setStrokeColor(color)

        // SVG-Koordinaten: Ursprung oben-links. CGContext: Ursprung unten-links — Y spiegeln.
        let rect = CGRect(
            x: object.positionX * Double(scale),
            y: Double(canvasHeightPixels) - (object.positionY + object.height) * Double(scale),
            width: object.width * Double(scale),
            height: object.height * Double(scale)
        )

        switch object.kind {
        case .rectangle:
            context.fill(rect)
        case .circle:
            context.fillEllipse(in: rect)
        case .star, .path:
            context.stroke(rect, width: max(scale * 0.2, 1))
        case .text:
            drawText(object, in: context, scale: scale, canvasHeightPixels: canvasHeightPixels, color: color)
        }
    }

    private func drawText(_ object: DesignObject, in context: CGContext, scale: CGFloat, canvasHeightPixels: CGFloat, color: CGColor) {
        guard let string = object.text, !string.isEmpty else { return }
        let fontSize = (object.fontSize ?? 12) * Double(scale)
        let font = CTFontCreateWithName((object.fontName ?? "Helvetica") as CFString, fontSize, nil)
        let attributedString = CFAttributedStringCreate(
            nil,
            string as CFString,
            [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        )
        let line = CTLineCreateWithAttributedString(attributedString!)

        // SVG-Koordinaten: Ursprung oben-links, positionY ist die Textbox-Oberkante.
        // CGContext-Textzeichnen läuft über die Baseline, nicht die Oberkante — daher um fontSize nach unten versetzen.
        let originX = object.positionX * Double(scale)
        let baselineY = Double(canvasHeightPixels) - object.positionY * Double(scale) - fontSize

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: originX, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

// Nicht `private` — wird auch vom Canvas-Rendering (Phase 5) wiederverwendet.
extension CGColor {
    static func fromHex(_ hex: String) -> CGColor? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return CGColor(red: red, green: green, blue: blue, alpha: 1)
    }
}
