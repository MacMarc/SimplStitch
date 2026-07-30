//
//  SVGDesignSerializerGenerationTests.swift
//  SimplStitchTests
//
//  Text embroiderable: `generationElement(for:)`/`generationBorderElement(for:)` sind für alle
//  Nicht-Text-Objekte identisch zu `element(for:)`/`borderElement(for:)` — nur Text bekommt einen
//  echten `<path>` mit Glyphen-Umrissen statt `<text>`. `content.svg` (`element(for:)`) bleibt für
//  Text unverändert `<text>` (editierbar).
//

import Testing
import CoreGraphics
@testable import SimplStitch

struct SVGDesignSerializerGenerationTests {

    private func makeRectangle() -> DesignObject {
        let object = DesignObject(name: "R", kind: .rectangle, positionX: 5, positionY: 5, width: 20, height: 10)
        object.stitchSettings = StitchSettings(stitchType: .tatami)
        return object
    }

    private func makeTextObject(text: String? = "Hallo") -> DesignObject {
        let object = DesignObject(name: "T", kind: .text, positionX: 10, positionY: 20, width: 40, height: 12)
        object.text = text
        object.fontSize = 8
        object.fontName = "Helvetica"
        object.stitchSettings = StitchSettings(stitchType: .tatami)
        return object
    }

    @Test func generationElementMatchesElementForNonTextKinds() {
        let serializer = SVGDesignSerializer()
        let rectangle = makeRectangle()
        #expect(serializer.generationElement(for: rectangle) == serializer.element(for: rectangle))
    }

    @Test func generationElementForTextIsPathNotText() throws {
        let serializer = SVGDesignSerializer()
        let text = makeTextObject()

        let persistedElement = serializer.element(for: text)
        #expect(persistedElement.contains("<text"))

        let generationElement = try #require(serializer.generationElement(for: text))
        #expect(generationElement.contains("<path"))
        #expect(!generationElement.contains("<text"))
        #expect(generationElement.contains("inkstitch:fill_method=\"tatami_fill\""))
    }

    @Test func generationElementForEmptyTextIsNil() {
        let serializer = SVGDesignSerializer()
        let text = makeTextObject(text: "")
        #expect(serializer.generationElement(for: text) == nil)
    }

    @Test func generationBorderElementMatchesBorderElementForNonTextKinds() {
        let serializer = SVGDesignSerializer()
        let rectangle = makeRectangle()
        rectangle.hasBorder = true
        let borderSettings = StitchSettings(stitchType: .straight)
        borderSettings.borderOwner = rectangle
        rectangle.borderStitchSettings = borderSettings

        #expect(serializer.generationBorderElement(for: rectangle) == serializer.borderElement(for: rectangle))
    }

    @Test func generationBorderElementForTextUsesGlyphOutline() throws {
        let serializer = SVGDesignSerializer()
        let text = makeTextObject()
        text.hasBorder = true
        let borderSettings = StitchSettings(stitchType: .straight)
        borderSettings.borderOwner = text
        text.borderStitchSettings = borderSettings

        // Alte borderElement(for:) liefert für Text weiterhin nil (kein Vektorpfad im
        // content.svg-Persistenz-Pfad) — der Generierungs-Pass schliesst genau diese Lücke.
        #expect(serializer.borderElement(for: text) == nil)

        let generationBorderElement = try #require(serializer.generationBorderElement(for: text))
        #expect(generationBorderElement.contains("<path"))
        #expect(generationBorderElement.contains("inkstitch:running_stitch_length_mm"))
    }

    @Test func generationBorderElementForTextWithoutBorderSettingsIsNil() {
        let serializer = SVGDesignSerializer()
        let text = makeTextObject()
        #expect(serializer.generationBorderElement(for: text) == nil)
    }
}
