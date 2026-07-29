//
//  GPLPaletteImporterTests.swift
//  SimplStitchTests
//
//  Phase 7: reiner Swift-Parser für .gpl (GIMP Palette), kein Python-Bridge-Bezug.
//

import Testing
import Foundation
@testable import SimplStitch

struct GPLPaletteImporterTests {

    @Test func parsesNameAndColorsWithNamesAndComments() throws {
        let contents = """
        GIMP Palette
        Name: Stickgarn Basis
        Columns: 4
        #
        255   0   0\tRot
          0 255   0\tGrün
          0   0 255\tBlau
        """
        let palette = try GPLPaletteImporter().importPalette(contents: contents, sourceFileName: "basis.gpl")

        #expect(palette.name == "Stickgarn Basis")
        #expect(palette.sourceFileName == "basis.gpl")
        #expect(palette.colors.count == 3)
        #expect(palette.colors[0].red == 255 && palette.colors[0].green == 0 && palette.colors[0].blue == 0)
        #expect(palette.colors[0].name == "Rot")
        #expect(palette.colors[2].blue == 255)
        #expect(palette.colors.allSatisfy { $0.palette === palette })
    }

    @Test func fallsBackToFileNameWhenNoNameDirective() throws {
        let contents = """
        GIMP Palette
        10 20 30
        """
        let palette = try GPLPaletteImporter().importPalette(contents: contents, sourceFileName: "MeineListe.gpl")
        #expect(palette.name == "MeineListe")
    }

    @Test func toleratesColorsWithoutNames() throws {
        let contents = """
        GIMP Palette
        1 2 3
        4 5 6
        """
        let palette = try GPLPaletteImporter().importPalette(contents: contents, sourceFileName: nil)
        #expect(palette.colors.count == 2)
        #expect(palette.colors[0].name == "")
    }

    @Test func throwsOnMissingHeader() {
        let contents = "255 0 0 Rot"
        #expect(throws: GPLPaletteImportError.self) {
            try GPLPaletteImporter().importPalette(contents: contents, sourceFileName: nil)
        }
    }

    @Test func throwsOnEmptyPalette() {
        let contents = """
        GIMP Palette
        Name: Leer
        #
        """
        #expect(throws: GPLPaletteImportError.self) {
            try GPLPaletteImporter().importPalette(contents: contents, sourceFileName: nil)
        }
    }

    @Test func skipsMalformedColorLines() throws {
        let contents = """
        GIMP Palette
        not a color line
        255 255 255 Weiss
        """
        let palette = try GPLPaletteImporter().importPalette(contents: contents, sourceFileName: nil)
        #expect(palette.colors.count == 1)
        #expect(palette.colors[0].name == "Weiss")
    }
}
