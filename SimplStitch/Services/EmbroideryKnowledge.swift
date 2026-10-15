//
//  EmbroideryKnowledge.swift
//  SimplStitch
//
//  Stickwissen als feste, testbare Regeln: welche Unterlage, welche Dichte, wann eine Stichart
//  an ihre Grenzen kommt. Grundlage sind die Anleitungen von Ink/Stitch (inkstitch.org, GPL-3.0
//  wie SimplStitch) — v.a. das Tutorial "Die wichtige Rolle der Unterleger", die Seiten zu
//  Satinsäule, Tatami-Füllung und Laufstich sowie die Standardwerte im vendorten Ink/Stitch-Code
//  (`Vendor/inkstitch_lib`). In eigenen Worten zusammengefasst, nicht wörtlich übernommen.
//
//  Die Regeln wirken immer, auch ohne Apple Intelligence: als Vorbelegung beim Bild-Nachzeichnen
//  und als Hinweise im Objekt-Inspektor. Ist Apple Intelligence an, bekommt das Modell
//  `modelInstructions` als Leitplanken — Unterlage und Dichte bestimmen aber auch dann diese
//  Regeln, nicht das Modell (deterministisch, nachvollziehbar, kein "halluzinierter" Wert).
//
//  Bewusst nicht abgebildet: Zugausgleich. Ink/Stitch nennt dafür keine festen Werte (hängt von
//  Stoff, Vlies, Garn ab und muss per Probestick ermittelt werden), und die App bietet den
//  Parameter (noch) nicht an — ein Hinweis, den man nicht umsetzen kann, wäre nur Rauschen.
//

import Foundation

nonisolated enum EmbroideryKnowledge {

    // MARK: Grenzwerte

    /// Ink/Stitch: Satinsäulen aus einer Kontur sollten breiter als 1,5 mm sein — schmaler wird
    /// daraus kaum mehr als ein Strich; dafür ist ein (Mehrfach-)Laufstich gedacht.
    static let satinMinWidthMillimeters = 1.5
    /// Breitere Satinstiche liegen lose auf, verhaken sich leicht und ziehen den Stoff zusammen;
    /// grössere Flächen gehören in eine Füllung. Gleicher Wert wie `StitchType.satinMaxShortSide`.
    static let satinMaxWidthMillimeters = 8.0
    /// Ink/Stitch-Unterlage-Tutorial: Mittellinie bis 2 mm, Kontur bis ca. 3,5–4 mm, darüber
    /// Kontur + Zickzack ("deutsche Unterlage").
    static let satinCenterWalkMaxWidthMillimeters = 2.0
    static let satinContourMaxWidthMillimeters = 4.0
    /// Sehr kleine Füllflächen werden mit Tatami unruhig; Ink/Stitch empfiehlt dafür Satin.
    static let fillMinWidthMillimeters = 3.0
    /// Ab diesem Reihenabstand ist eine Füllung so locker, dass die Unterlage eher stört als
    /// stützt (Ink/Stitch: Unterlage z.B. bei grossem Reihenabstand abschalten).
    static let fillUnderlayOptionalSpacingMillimeters = 1.0

    /// Ink/Stitch-Standardwerte (vendorter Code): Laufstich 2,5 mm, Satin-Zickzackabstand 0,4 mm.
    /// Tatami: Ink/Stitch nimmt 0,25 mm; SimplStitch bleibt bei seinen bisherigen 0,4 mm (deckt
    /// auf den üblichen Heimstick-Stoffen gut und spart Stiche), beides liegt im sinnvollen Bereich.
    static let defaultRunningStitchLength = 2.5
    static let defaultSatinSpacing = 0.4
    static let defaultFillRowSpacing = 0.4

    static let recommendedFillRowSpacing: ClosedRange<Double> = 0.2...0.8
    static let recommendedSatinSpacing: ClosedRange<Double> = 0.2...0.8
    static let recommendedRunningStitchLength: ClosedRange<Double> = 1.0...4.0

    // MARK: Empfehlungen

    static func recommendedDensity(for stitchType: StitchType) -> Double {
        switch stitchType {
        case .straight: return defaultRunningStitchLength
        case .satin: return defaultSatinSpacing
        case .tatami: return defaultFillRowSpacing
        }
    }

    /// `width` ist die Breite des Objekts quer zur Stichrichtung in mm (bei Formen die kürzere
    /// Seite, bei einem Rand die Randbreite). `nil`, wenn unbekannt.
    static func recommendedUnderlay(for stitchType: StitchType, width: Double?, density: Double? = nil) -> UnderlayType {
        switch stitchType {
        case .straight:
            return .none
        case .tatami:
            if let density, density >= fillUnderlayOptionalSpacingMillimeters { return .none }
            // Ink/Stitch kennt für Füllungen nur "Unterlage an/aus" (um 90° gedrehte, lockere
            // Füllung) — jeder Wert ausser `.none` schaltet sie ein; Mittellinie ist der App-Standard.
            return .centerWalk
        case .satin:
            guard let width else { return .centerWalk }
            if width <= satinCenterWalkMaxWidthMillimeters { return .centerWalk }
            if width <= satinContourMaxWidthMillimeters { return .edgeWalk }
            return .zigzagNet
        }
    }

    // MARK: Hinweise

    enum HintKind: String, Equatable, Sendable {
        case satinTooNarrow
        case satinTooWide
        case satinUnderlay
        case fillTooSmall
        case fillNeedsUnderlay
        case fillUnderlayOptional
        case fillTooDense
        case fillTooSparse
        case satinTooDense
        case satinTooSparse
        case runningStitchTooShort
        case runningStitchTooLong
    }

    /// Was "Übernehmen" an den Sticheinstellungen ändert — `nil` bei rein informativen Hinweisen.
    enum Adjustment: Equatable, Sendable {
        case stitchType(StitchType)
        case underlay(UnderlayType)
        case density(Double)
    }

    struct Hint: Equatable, Identifiable, Sendable {
        var kind: HintKind
        var adjustment: Adjustment?
        var id: String { kind.rawValue }
    }

    static func hints(stitchType: StitchType, density: Double, underlay: UnderlayType, width: Double?) -> [Hint] {
        var hints: [Hint] = []
        switch stitchType {
        case .straight:
            if density < recommendedRunningStitchLength.lowerBound {
                hints.append(Hint(kind: .runningStitchTooShort, adjustment: .density(defaultRunningStitchLength)))
            } else if density > recommendedRunningStitchLength.upperBound {
                hints.append(Hint(kind: .runningStitchTooLong, adjustment: .density(defaultRunningStitchLength)))
            }

        case .satin:
            if let width, width < satinMinWidthMillimeters {
                hints.append(Hint(kind: .satinTooNarrow, adjustment: .stitchType(.straight)))
            } else if let width, width > satinMaxWidthMillimeters {
                hints.append(Hint(kind: .satinTooWide, adjustment: .stitchType(.tatami)))
            }
            let recommended = recommendedUnderlay(for: .satin, width: width)
            if width != nil, underlay != recommended {
                hints.append(Hint(kind: .satinUnderlay, adjustment: .underlay(recommended)))
            }
            if density < recommendedSatinSpacing.lowerBound {
                hints.append(Hint(kind: .satinTooDense, adjustment: .density(defaultSatinSpacing)))
            } else if density > recommendedSatinSpacing.upperBound {
                hints.append(Hint(kind: .satinTooSparse, adjustment: .density(defaultSatinSpacing)))
            }

        case .tatami:
            if let width, width < fillMinWidthMillimeters {
                hints.append(Hint(kind: .fillTooSmall, adjustment: .stitchType(.satin)))
            }
            if density >= fillUnderlayOptionalSpacingMillimeters {
                if underlay != .none {
                    hints.append(Hint(kind: .fillUnderlayOptional, adjustment: .underlay(.none)))
                }
            } else if underlay == .none {
                hints.append(Hint(kind: .fillNeedsUnderlay, adjustment: .underlay(.centerWalk)))
            }
            if density < recommendedFillRowSpacing.lowerBound {
                hints.append(Hint(kind: .fillTooDense, adjustment: .density(defaultFillRowSpacing)))
            } else if density > recommendedFillRowSpacing.upperBound {
                hints.append(Hint(kind: .fillTooSparse, adjustment: .density(defaultFillRowSpacing)))
            }
        }
        return hints
    }

    // MARK: Leitplanken für Apple Intelligence

    /// Englisch, weil das On-Device-Modell darauf am verlässlichsten antwortet; der Nutzer sieht
    /// diesen Text nie. Kurz gehalten — das Kontextfenster des Systemmodells ist klein.
    static let modelInstructions = """
    You are an expert machine-embroidery digitizer. You decide how each area of a traced image \
    should be stitched on a home embroidery machine. Follow these rules (based on the Ink/Stitch \
    documentation):
    - Running stitch: for thin lines, outlines and fine details narrower than about 1.5 mm. No underlay.
    - Fill (tatami): for areas of one colour wider than about 3 mm. Fills always get an underlay \
    that runs at 90 degrees to the top stitches; it binds fabric and stabilizer and keeps the \
    stitches from sinking in.
    - Satin columns suit narrow bands 1.5 to 8 mm wide (borders, lettering, small shapes). \
    Satin is not available for traced areas here, so choose between running stitch and fill.
    - Fill angle: stitch rows usually look best along the longer direction of an area; give \
    neighbouring areas of different colours different angles so the edges stay crisp. \
    0 degrees is horizontal, angles go counter-clockwise.
    - Very small specks are better as running stitch than as fill.
    """
}
