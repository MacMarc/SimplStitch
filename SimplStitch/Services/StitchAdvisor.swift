//
//  StitchAdvisor.swift
//  SimplStitch
//
//  Entscheidet beim Bild-Nachzeichnen (Issue #3) pro Fläche Stichart, Dichte, Winkel und
//  Unterlage. Zwei Umsetzungen hinter einem Protokoll:
//  - `RuleBasedStitchAdvisor`: nur die festen Stickregeln (`EmbroideryKnowledge`), läuft immer.
//  - `AppleIntelligenceStitchAdvisor`: fragt zusätzlich das On-Device-Modell von Apple
//    Intelligence (Foundation Models), das die Stickregeln als Leitplanken bekommt. Nur, wenn der
//    Nutzer es in den Einstellungen nicht ausgeschaltet hat UND Apple Intelligence auf dem Mac
//    verfügbar ist. Jede Antwort wird gegen die Regeln geprüft; Dichte und Unterlage kommen immer
//    aus den Regeln. Scheitert das Modell (nicht verfügbar, Fehler, Kontext zu gross), gilt
//    stillschweigend das regelbasierte Ergebnis — die App funktioniert ohne Apple Intelligence
//    vollständig.
//

import Foundation
import CoreGraphics
import FoundationModels

nonisolated struct RegionStitchAdvice: Equatable, Sendable {
    var stitchType: StitchType
    var density: Double
    var angleDegrees: Double
    var underlayType: UnderlayType

    /// Regeln: Unterlage und Dichte passend zur Stichart und zur Breite der Fläche.
    static func make(stitchType: StitchType, angleDegrees: Double, width: Double) -> RegionStitchAdvice {
        RegionStitchAdvice(
            stitchType: stitchType,
            density: EmbroideryKnowledge.recommendedDensity(for: stitchType),
            angleDegrees: stitchType == .tatami ? angleDegrees : 0,
            underlayType: EmbroideryKnowledge.recommendedUnderlay(for: stitchType, width: width)
        )
    }
}

nonisolated protocol StitchAdvising: Sendable {
    func advice(for regions: [TracedRegion]) async -> [RegionStitchAdvice]
}

// MARK: Regeln

nonisolated struct RuleBasedStitchAdvisor: StitchAdvising {
    var suggester = RuleBasedStitchTypeSuggester()

    func advice(for regions: [TracedRegion]) async -> [RegionStitchAdvice] {
        ruleAdvice(for: regions)
    }

    func ruleAdvice(for regions: [TracedRegion]) -> [RegionStitchAdvice] {
        regions.map { region in
            RegionStitchAdvice.make(
                stitchType: suggester.suggestedStitchType(for: region),
                angleDegrees: Self.longAxisAngle(of: region),
                width: region.averageWidth
            )
        }
    }

    /// Füllreihen entlang der längeren Seite der Fläche — wirkt ruhiger und braucht weniger
    /// Richtungswechsel. 0° = waagrecht.
    static func longAxisAngle(of region: TracedRegion) -> Double {
        let bounds = region.bounds
        return bounds.width >= bounds.height ? 0 : 90
    }
}

// MARK: Apple Intelligence

nonisolated enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    case notEnabled
    case deviceNotEligible
    case modelNotReady
    case unavailable

    static var current: AppleIntelligenceStatus {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return .available }
        if case .unavailable(let reason) = availability {
            switch reason {
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .deviceNotEligible: return .deviceNotEligible
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unavailable
            }
        }
        return .unavailable
    }
}

nonisolated struct AppleIntelligenceStitchAdvisor: StitchAdvising {
    /// Das Systemmodell hat ein kleines Kontextfenster — nur die grössten Flächen fragen, der
    /// Rest (meist Kleinkram) bleibt bei den Regeln.
    static let maximumRegionCount = 40

    var rules = RuleBasedStitchAdvisor()

    func advice(for regions: [TracedRegion]) async -> [RegionStitchAdvice] {
        var advice = rules.ruleAdvice(for: regions)
        guard !regions.isEmpty, AppleIntelligenceStatus.current == .available else { return advice }

        let considered = Array(regions.prefix(Self.maximumRegionCount))
        do {
            let session = LanguageModelSession(instructions: EmbroideryKnowledge.modelInstructions)
            let response = try await session.respond(
                to: Self.prompt(for: considered),
                generating: TracedDesignPlan.self
            )
            for plan in response.content.regions {
                let index = plan.regionNumber - 1
                guard considered.indices.contains(index) else { continue }
                advice[index] = Self.validated(plan.stitch, fillAngleDegrees: plan.fillAngleDegrees, for: considered[index])
            }
        } catch {
            // Bewusst still: die Regel-Vorschläge sind ein vollwertiges Ergebnis.
        }
        return advice
    }

    static func prompt(for regions: [TracedRegion]) -> String {
        var lines = ["Choose a stitch for each of these traced areas (sizes in millimetres):"]
        for (index, region) in regions.enumerated() {
            let bounds = region.bounds
            lines.append(String(
                format: "Region %d: colour %@, area %.0f mm², %.1f × %.1f mm, average width %.1f mm",
                index + 1,
                region.color.hex,
                region.area,
                bounds.width,
                bounds.height,
                region.averageWidth
            ))
        }
        return lines.joined(separator: "\n")
    }

    /// Die Stickregeln haben das letzte Wort: Laufstich nur für Flächen, die für eine Füllung zu
    /// schmal sind, Füllung nur, wo sie überhaupt Platz hat. Dichte und Unterlage kommen immer aus
    /// den Regeln, das Modell darf nur Stichart (im Graubereich) und Füllwinkel beitragen.
    static func validated(_ stitch: PlannedStitch, fillAngleDegrees: Int, for region: TracedRegion) -> RegionStitchAdvice {
        let width = region.averageWidth
        var stitchType: StitchType = stitch == .runningStitch ? .straight : .tatami
        if width < RuleBasedStitchTypeSuggester.runningStitchMaxWidthMillimeters {
            stitchType = .straight
        } else if width >= EmbroideryKnowledge.fillMinWidthMillimeters {
            stitchType = .tatami
        }
        let angle = Double(min(max(fillAngleDegrees, 0), 179))
        return RegionStitchAdvice.make(stitchType: stitchType, angleDegrees: angle, width: width)
    }
}

@Generable
nonisolated struct TracedDesignPlan {
    @Guide(description: "One entry for every numbered region")
    var regions: [RegionPlan]
}

@Generable
nonisolated struct RegionPlan {
    @Guide(description: "The region number from the list")
    var regionNumber: Int
    @Guide(description: "How this region should be stitched")
    var stitch: PlannedStitch
    @Guide(description: "Direction of the fill rows in degrees, 0 is horizontal", .range(0...179))
    var fillAngleDegrees: Int
}

@Generable
nonisolated enum PlannedStitch {
    case runningStitch
    case fill
}
