//
//  ColorHexTests.swift
//  SimplStitchTests
//
//  `Color(hex:)` fürs read-only Farb-Swatch im Objekt-Inspektor — reine
//  Konvertierungslogik, unabhängig von der UI testbar. Die Rückrichtung
//  (`Color.hexString`) wurde mit Issue #13 entfernt (siehe Color+Hex.swift).
//

import Testing
import SwiftUI
@testable import SimplStitch

struct ColorHexTests {

    @Test func hexInitProducesResolvableColor() throws {
        let color = try #require(Color(hex: "#FF00AA"))
        let components = try #require(color.cgColor?.components)
        #expect(components.count >= 3)
    }

    @Test func invalidHexReturnsNil() {
        #expect(Color(hex: "not-a-color") == nil)
    }
}
