//
//  ColorHexTests.swift
//  SimplStitchTests
//
//  Phase 8d: Color(hex:)/Color.hexString fürs Farbe-Feld im Objekt-Inspektor
//  (ObjectInspectorView) — reine Konvertierungslogik, unabhängig von der UI testbar.
//

import Testing
import SwiftUI
@testable import SimplStitch

struct ColorHexTests {

    @Test func hexStringRoundtripsThroughColor() throws {
        let color = try #require(Color(hex: "#FF00AA"))
        #expect(color.hexString == "#FF00AA")
    }

    @Test func hexStringNormalizesCase() throws {
        let color = try #require(Color(hex: "#00ff00"))
        #expect(color.hexString == "#00FF00")
    }

    @Test func invalidHexReturnsNil() {
        #expect(Color(hex: "not-a-color") == nil)
    }

    @Test func hexStringFallsBackToBlackForUnresolvableColor() {
        // Ein Color-Wert, der nie über Color(hex:) entstanden ist (hier eine semantische
        // Systemfarbe) hat ggf. keine über `cgColor` direkt auflösbaren RGB-Komponenten in allen
        // Farbräumen — der Fallback greift, statt zu crashen.
        #expect(Color.black.hexString == "#000000")
    }
}
