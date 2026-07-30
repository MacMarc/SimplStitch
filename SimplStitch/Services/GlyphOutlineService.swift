//
//  GlyphOutlineService.swift
//  SimplStitch
//
//  Text embroiderable: echte Vektor-Glyphen-Umrisse für die Stichgenerierung.
//  Opus-Konsultation ergab: Text bleibt als editierbares `<text>`-Element
//  erhalten (unverändert seit Phase 5d/CLAUDE.md "Konvertierung zu Pfaden nur
//  beim Export/Stichberechnung") — dieser Service erzeugt den Glyphen-Pfad rein
//  generierungsseitig (nie persistiert, nie gerendert), aufgerufen von
//  `SVGDesignSerializing.generationElement(for:)`.
//
//  CoreText statt eines SwiftUI-Pfads: nur CoreText liefert echte Bézier-
//  Glyphen-Konturen (`CTFontCreatePathForGlyph`) statt blosser Rasterung.
//  Reuse derselben CTLine-Grundlagen wie `PreviewImageRenderer.drawText`
//  (Font/Attributed-String-Aufbau), aber Pfad-Extraktion statt `CTLineDraw`.
//

import Foundation
import CoreGraphics
import CoreText

protocol GlyphOutlining {
    /// Kompound-Pfad aller Glyphen von `object.text`, bereits in Design-Koordinaten (mm, Ursprung
    /// oben-links, unrotiert/unverzerrt — dieselbe Konvention wie die übrige Stichgenerierung,
    /// die Rotation/Skew ebenfalls nicht einbäckt, siehe Phase 6c). `nil` bei leerem/fehlendem Text.
    func glyphOutlinePath(for object: DesignObject) -> CGPath?
}

final class GlyphOutlineService: GlyphOutlining {
    func glyphOutlinePath(for object: DesignObject) -> CGPath? {
        guard let string = object.text, !string.isEmpty else { return nil }

        let fontSize = object.fontSize ?? 12
        let fontName = object.fontName ?? "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        guard let attributedString = CFAttributedStringCreate(
            nil, string as CFString, [kCTFontAttributeName: font] as CFDictionary
        ) else { return nil }
        let line = CTLineCreateWithAttributedString(attributedString)
        let ascent = CTFontGetAscent(font)

        // Textbox-Oberkante (`object.positionY`) + Ascent ergibt die Baseline — dieselbe
        // Referenz wie das live gerenderte Canvas-Text (`CanvasView.drawText`, `anchor: .topLeading`).
        let baselineOrigin = CGPoint(x: object.positionX, y: object.positionY + Double(ascent))

        let combinedPath = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            let runAttributes = CTRunGetAttributes(run) as? [String: Any] ?? [:]
            let runFont = (runAttributes[kCTFontAttributeName as String] as! CTFont?) ?? font

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)

            for i in 0..<glyphCount {
                // Glyph-lokale Konturen (y-oben, Ursprung Pen-Position) -> per-Glyph-Position
                // innerhalb der Zeile -> Y-Spiegelung (CoreText y-oben, Design-Raum y-unten) ->
                // Verschiebung auf die Baseline im Design-Raum. Eine Matrix statt drei
                // Einzelschritten, direkt an CTFontCreatePathForGlyph übergeben.
                var matrix = CGAffineTransform(translationX: positions[i].x, y: positions[i].y)
                    .concatenating(CGAffineTransform(scaleX: 1, y: -1))
                    .concatenating(CGAffineTransform(translationX: baselineOrigin.x, y: baselineOrigin.y))
                if let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[i], &matrix) {
                    combinedPath.addPath(glyphPath)
                }
            }
        }
        return combinedPath.isEmpty ? nil : combinedPath
    }
}
