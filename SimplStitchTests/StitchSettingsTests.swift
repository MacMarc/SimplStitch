//
//  StitchSettingsTests.swift
//  SimplStitchTests
//
//  Issue #11: StitchType.suggested(forShapeWidth:height:) — reine Heuristik, unabhängig von der
//  UI/CanvasStore testbar. Die Integration in CanvasStore.makeShapeObject wird separat in
//  CanvasStoreTests abgedeckt (Formerzeugung setzt den vorgeschlagenen Typ tatsächlich).
//

import Testing
@testable import SimplStitch

struct StitchSettingsTests {

    @Test func suggestsSatinForNarrowElongatedShape() {
        // 3mm x 30mm: kürzere Seite (3) <= 15mm, Seitenverhältnis (0.1) <= 0.3 -> Satin.
        #expect(StitchType.suggested(forShapeWidth: 30, height: 3) == .satin)
        #expect(StitchType.suggested(forShapeWidth: 3, height: 30) == .satin)
    }

    @Test func suggestsTatamiForSquareShape() {
        #expect(StitchType.suggested(forShapeWidth: 30, height: 30) == .tatami)
    }

    @Test func suggestsTatamiForNarrowButLargeShape() {
        // Seitenverhältnis wäre satin-tauglich (0.1), aber die kürzere Seite (20mm) überschreitet
        // satinMaxShortSideMillimeters (15mm) — zu breit für einen sinnvollen Satin-Steg.
        #expect(StitchType.suggested(forShapeWidth: 200, height: 20) == .tatami)
    }

    @Test func suggestsTatamiForModeratelyElongatedShape() {
        // Seitenverhältnis 0.5 liegt über der Satin-Schwelle (0.3).
        #expect(StitchType.suggested(forShapeWidth: 20, height: 10) == .tatami)
    }

    @Test func suggestsTatamiForZeroOrNegativeDimensions() {
        #expect(StitchType.suggested(forShapeWidth: 0, height: 10) == .tatami)
        #expect(StitchType.suggested(forShapeWidth: 10, height: 0) == .tatami)
    }

    // MARK: UnderlayType.suggested (Issue #18)

    @Test func suggestsNoUnderlayForStraightStitch() {
        #expect(UnderlayType.suggested(for: .straight) == .none)
    }

    @Test func suggestsCenterWalkUnderlayForTatamiAndSatin() {
        #expect(UnderlayType.suggested(for: .tatami) == .centerWalk)
        #expect(UnderlayType.suggested(for: .satin) == .centerWalk)
    }
}
