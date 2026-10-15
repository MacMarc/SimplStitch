//
//  EmbroideryKnowledgeTests.swift
//  SimplStitchTests
//
//  Stickregeln nach Ink/Stitch (Unterlage, Dichte, Grenzen der Sticharten), die Absicherung der
//  Apple-Intelligence-Vorschläge durch diese Regeln, die Garnzuordnung beim Bild-Nachzeichnen
//  und der Kontrast der Stichvorschau.
//

import Testing
import Foundation
import CoreGraphics
@testable import SimplStitch

struct EmbroideryKnowledgeTests {

    private typealias Knowledge = EmbroideryKnowledge

    // MARK: Unterlage

    @Test func satinUnderlayFollowsColumnWidth() {
        #expect(Knowledge.recommendedUnderlay(for: .satin, width: 1.8) == .centerWalk)
        #expect(Knowledge.recommendedUnderlay(for: .satin, width: 3) == .edgeWalk)
        #expect(Knowledge.recommendedUnderlay(for: .satin, width: 6) == .zigzagNet)
    }

    @Test func fillGetsUnderlayUnlessVeryOpen() {
        #expect(Knowledge.recommendedUnderlay(for: .tatami, width: 20) != .none)
        #expect(Knowledge.recommendedUnderlay(for: .tatami, width: 20, density: 1.2) == .none)
    }

    @Test func runningStitchNeverGetsUnderlay() {
        #expect(Knowledge.recommendedUnderlay(for: .straight, width: 0.5) == .none)
        #expect(UnderlayType.suggested(for: .straight) == .none)
    }

    @Test func runningStitchDefaultLengthIsInkStitchDefault() {
        #expect(Knowledge.recommendedDensity(for: .straight) == 2.5)
        #expect(Knowledge.recommendedDensity(for: .satin) == 0.4)
    }

    // MARK: Hinweise

    @Test func fillWithoutUnderlayGetsHintWithFix() {
        let hints = Knowledge.hints(stitchType: .tatami, density: 0.4, underlay: .none, width: 30)
        #expect(hints.contains(.init(kind: .fillNeedsUnderlay, adjustment: .underlay(.centerWalk))))
    }

    @Test func wellSetUpObjectsGetNoHints() {
        #expect(Knowledge.hints(stitchType: .tatami, density: 0.4, underlay: .centerWalk, width: 30).isEmpty)
        #expect(Knowledge.hints(stitchType: .satin, density: 0.4, underlay: .edgeWalk, width: 3).isEmpty)
        #expect(Knowledge.hints(stitchType: .straight, density: 2.5, underlay: .none, width: nil).isEmpty)
    }

    @Test func satinLimitsAreFlagged() {
        let narrow = Knowledge.hints(stitchType: .satin, density: 0.4, underlay: .centerWalk, width: 1)
        #expect(narrow.contains { $0.kind == .satinTooNarrow && $0.adjustment == .stitchType(.straight) })
        let wide = Knowledge.hints(stitchType: .satin, density: 0.4, underlay: .zigzagNet, width: 12)
        #expect(wide.contains { $0.kind == .satinTooWide && $0.adjustment == .stitchType(.tatami) })
        let wrongUnderlay = Knowledge.hints(stitchType: .satin, density: 0.4, underlay: .centerWalk, width: 6)
        #expect(wrongUnderlay.contains { $0.kind == .satinUnderlay && $0.adjustment == .underlay(.zigzagNet) })
    }

    @Test func tooShortRunningStitchIsFlagged() {
        let hints = Knowledge.hints(stitchType: .straight, density: 0.4, underlay: .none, width: nil)
        #expect(hints.contains { $0.kind == .runningStitchTooShort && $0.adjustment == .density(2.5) })
    }

    // MARK: Bild nachzeichnen

    private func strip(width: Double, length: Double = 40) -> TracedRegion {
        TracedRegion(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: length, y: 0), CGPoint(x: length, y: width), CGPoint(x: 0, y: width)],
            color: TraceColor(red: 10, green: 20, blue: 30)
        )
    }

    @Test func ruleAdviceGivesFillAnUnderlayAndLongAxisAngle() {
        let tall = TracedRegion(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 40), CGPoint(x: 0, y: 40)],
            color: TraceColor(red: 0, green: 0, blue: 0)
        )
        let advice = RuleBasedStitchAdvisor().ruleAdvice(for: [tall, strip(width: 0.5)])
        #expect(advice[0].stitchType == .tatami)
        #expect(advice[0].underlayType != .none)
        #expect(advice[0].angleDegrees == 90)
        #expect(advice[1].stitchType == .straight)
        #expect(advice[1].underlayType == .none)
        #expect(advice[1].density == 2.5)
    }

    @Test func rulesOverrideImplausibleModelAnswers() {
        let wideArea = strip(width: 10)
        let advice = AppleIntelligenceStitchAdvisor.validated(.runningStitch, fillAngleDegrees: 45, for: wideArea)
        #expect(advice.stitchType == .tatami)
        #expect(advice.angleDegrees == 45)
        #expect(advice.underlayType != .none)

        #expect(AppleIntelligenceStitchAdvisor.validated(.fill, fillAngleDegrees: 30, for: strip(width: 0.4)).stitchType == .straight)
    }

    @Test func modelMayDecideInTheGreyZone() {
        #expect(AppleIntelligenceStitchAdvisor.validated(.runningStitch, fillAngleDegrees: 0, for: strip(width: 2)).stitchType == .straight)
    }

    @Test func promptListsEveryRegion() {
        let prompt = AppleIntelligenceStitchAdvisor.prompt(for: [strip(width: 2), strip(width: 5)])
        #expect(prompt.contains("Region 1:"))
        #expect(prompt.contains("Region 2:"))
        #expect(prompt.contains("#0A141E"))
    }

    @Test func nearestThreadIsChosen() {
        let threads = [
            ThreadCandidate(name: "Schwarz", red: 0, green: 0, blue: 0),
            ThreadCandidate(name: "Rot", red: 255, green: 0, blue: 0),
            ThreadCandidate(name: "Weiss", red: 255, green: 255, blue: 255),
        ]
        #expect(ThreadCandidate.nearest(to: TraceColor(red: 200, green: 30, blue: 20), in: threads)?.name == "Rot")
        #expect(ThreadCandidate.nearest(to: TraceColor(red: 30, green: 30, blue: 40), in: threads)?.name == "Schwarz")
        #expect(ThreadCandidate.nearest(to: TraceColor(red: 1, green: 2, blue: 3), in: []) == nil)
    }

    @MainActor
    @Test func tracedObjectsUseMatchedThread() {
        let threads = [ThreadCandidate(name: "Rot", red: 255, green: 0, blue: 0, catalogNumber: "R1")]
        let region = TracedRegion(
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)],
            color: TraceColor(red: 200, green: 10, blue: 10)
        )
        let object = ImageTraceService.designObjects(from: [region], threads: threads)[0]
        #expect(object.fillColorHex == "#FF0000")
        #expect(object.threadColor?.name == "Rot")
        #expect(object.threadColor?.catalogNumber == "R1")
    }

    // MARK: Stichvorschau

    @Test func stitchPreviewIsLightOnDarkThreads() {
        #expect(StitchPreviewStyle.usesLightStitches(onHex: "#000000"))
        #expect(StitchPreviewStyle.usesLightStitches(onHex: "#000080"))
        #expect(StitchPreviewStyle.usesLightStitches(onHex: "#8B0000"))
        #expect(!StitchPreviewStyle.usesLightStitches(onHex: "#FFFF00"))
        #expect(!StitchPreviewStyle.usesLightStitches(onHex: "#FFFFFF"))
        #expect(!StitchPreviewStyle.usesLightStitches(onHex: nil))
    }

    // MARK: Serialisierung

    @MainActor
    @Test func zigzagUnderlayAlsoWritesContourAndReadsBack() throws {
        let object = DesignObject(name: "Satin", kind: .rectangle, positionX: 0, positionY: 0, width: 40, height: 6)
        object.stitchSettings = StitchSettings(stitchType: .satin, density: 0.4, angleDegrees: 0, underlayType: .zigzagNet)
        let element = SVGDesignSerializer().element(for: object)
        #expect(element.contains("inkstitch:contour_underlay=\"true\""))
        #expect(element.contains("inkstitch:zigzag_underlay=\"true\""))

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:inkstitch="http://inkstitch.org/namespace" width="100mm" height="100mm">
          \(element)
        </svg>
        """
        let decoded = try SVGDesignSerializer().decode(svg: svg)
        #expect(decoded.objects.first?.stitchSettings?.underlayType == .zigzagNet)
    }
}
