//
//  GlyphOutlineServiceTests.swift
//  SimplStitchTests
//
//  Text embroiderable: echte Vektor-Glyphen-Umrisse fürs Stichgenerierungs-Payload.
//

import Testing
import CoreGraphics
@testable import SimplStitch

struct GlyphOutlineServiceTests {

    private func makeTextObject(text: String?) -> DesignObject {
        let object = DesignObject(name: "T", kind: .text, positionX: 10, positionY: 20, width: 40, height: 12)
        object.text = text
        object.fontSize = 8
        object.fontName = "Helvetica"
        return object
    }

    @Test func emptyTextReturnsNil() {
        let service = GlyphOutlineService()
        #expect(service.glyphOutlinePath(for: makeTextObject(text: "")) == nil)
    }

    @Test func missingTextReturnsNil() {
        let service = GlyphOutlineService()
        #expect(service.glyphOutlinePath(for: makeTextObject(text: nil)) == nil)
    }

    @Test func nonEmptyTextProducesNonDegeneratePathNearTextBox() throws {
        let object = makeTextObject(text: "A")
        let service = GlyphOutlineService()
        let path = try #require(service.glyphOutlinePath(for: object))
        let bounds = path.boundingBoxOfPath

        #expect(!bounds.isEmpty)
        // Baseline sitzt bei positionY + Ascent, das Glyph liegt darüber — grobe Plausibilitäts-
        // prüfung statt exakter Pixelwerte (Systemfont-Metriken sind hier bewusst nicht hart codiert).
        #expect(bounds.minX >= object.positionX - 0.5)
        #expect(bounds.minY >= object.positionY - 0.5)
        #expect(bounds.maxY <= object.positionY + (object.fontSize ?? 8) + 4)
    }

    @Test func nonEmptyTextObjectHasNonNilPath() throws {
        // Zwei verschiedene Buchstaben ergeben unterschiedliche Pfade (keine leere/konstante
        // Rückgabe unabhängig vom Inhalt).
        let service = GlyphOutlineService()
        let pathA = try #require(service.glyphOutlinePath(for: makeTextObject(text: "A")))
        let pathI = try #require(service.glyphOutlinePath(for: makeTextObject(text: "I")))
        #expect(pathA != pathI)
    }
}
