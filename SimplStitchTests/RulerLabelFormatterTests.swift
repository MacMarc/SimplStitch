//
//  RulerLabelFormatterTests.swift
//  SimplStitchTests
//
//  Issue #32 (Findings 4 + 10): Lineal-Beschriftung — Zoll als gekürzter Bruch, mm ohne
//  unnötige Nachkommastellen und mit dem Dezimaltrennzeichen der jeweiligen Sprache.
//

import Testing
import Foundation
@testable import SimplStitch

@MainActor
struct RulerLabelFormatterTests {

    @Test func inchesAreShownAsReducedFractions() {
        #expect(RulerLabelFormatter.fractionLabel(forInches: 0.25) == "1/4")
        #expect(RulerLabelFormatter.fractionLabel(forInches: 0.5) == "1/2")
        #expect(RulerLabelFormatter.fractionLabel(forInches: 1.0) == "1")
        #expect(RulerLabelFormatter.fractionLabel(forInches: 1.125) == "1 1/8")
        #expect(RulerLabelFormatter.fractionLabel(forInches: 3.0 / 64) == "3/64")
        #expect(RulerLabelFormatter.fractionLabel(forInches: 16) == "16")
    }

    @Test func inchFractionsHandleZeroAndNegativeValues() {
        // Negative Werte entstehen beim zentrierten Lineal-Nullpunkt (Issue #30).
        #expect(RulerLabelFormatter.fractionLabel(forInches: 0) == "0")
        #expect(RulerLabelFormatter.fractionLabel(forInches: -0.0) == "0")
        #expect(RulerLabelFormatter.fractionLabel(forInches: -0.75) == "-3/4")
        #expect(RulerLabelFormatter.fractionLabel(forInches: -2.5) == "-2 1/2")
    }

    @Test func inchFractionsTolerateFloatingPointNoise() {
        // 25.4mm-Umrechnung hin und zurück liefert selten exakt den Bruchwert.
        let roundTripped = MeasurementUnit.inches.value(fromMillimeters: MeasurementUnit.inches.millimeters(from: 0.375))
        #expect(RulerLabelFormatter.fractionLabel(forInches: roundTripped) == "3/8")
    }

    @Test func millimetersDropTrailingZeros() {
        let english = Locale(identifier: "en_US")
        #expect(RulerLabelFormatter.label(forValue: 10, unit: .millimeters, locale: english) == "10")
        #expect(RulerLabelFormatter.label(forValue: 2000, unit: .millimeters, locale: english) == "2000")
        #expect(RulerLabelFormatter.label(forValue: 0.5, unit: .millimeters, locale: english) == "0.5")
        #expect(RulerLabelFormatter.label(forValue: -0.0, unit: .millimeters, locale: english) == "0")
        #expect(RulerLabelFormatter.label(forValue: -20, unit: .millimeters, locale: english) == "-20")
    }

    @Test func millimetersUseLocaleDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        #expect(RulerLabelFormatter.label(forValue: 0.5, unit: .millimeters, locale: german) == "0,5")
    }

    @Test func inchUnitUsesFractions() {
        #expect(RulerLabelFormatter.label(forValue: 0.25, unit: .inches) == "1/4")
    }
}
