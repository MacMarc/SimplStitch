//
//  CanvasRulers.swift
//  SimplStitch
//
//  Lineal oben+links am Canvas (Issue #30), aus CanvasView ausgelagert (Issue #32, Finding 1):
//  die Mausposition für den Lineal-Positionszeiger lebt in `RulerHoverTracker` und wird nur hier
//  gelesen. Dadurch löst eine Mausbewegung nur ein Neuzeichnen der beiden schmalen Lineal-Streifen
//  aus, nicht mehr der kompletten Haupt-Canvas (Objekte, Stichvorschau, Griffe) in CanvasView.
//

import SwiftUI

/// Mausposition relativ zum Canvas selbst (nicht zum Lineal), `nil` sobald die Maus den Canvas
/// verlässt. CanvasView SCHREIBT nur (`.onContinuousHover`), liest aber nie — Observation hängt
/// damit ausschliesslich `CanvasRulers` an diesen Wert.
@Observable
@MainActor
final class RulerHoverTracker {
    var location: CGPoint?
}

/// Reine Beschriftungs-Logik der Lineale, separat testbar (siehe `RulerLabelFormatterTests`).
enum RulerLabelFormatter {
    /// Zoll-Stufen sind Zweierpotenz-Brüche bis 1/64 (siehe `CanvasRulers.niceStepsInches`).
    static let inchFractionDenominator = 64

    /// mm: Zahl ohne unnötige Nachkommastellen, locale-gerecht ("0,5" auf Deutsch) — Issue #32
    /// Finding 10, vorher `%g` mit hart verdrahtetem Dezimalpunkt. Zoll: gekürzter Bruch wie auf
    /// echten Massbändern ("1/4", "1 1/8") — Issue #32 Finding 4, Nutzerentscheidung für Brüche.
    static func label(forValue value: Double, unit: MeasurementUnit, locale: Locale = .current) -> String {
        switch unit {
        case .millimeters:
            let rounded = (value * 1000).rounded() / 1000
            // `+ 0` wandelt ein eventuelles -0.0 in 0.0, damit nie "-0" erscheint.
            return (rounded + 0).formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
        case .inches:
            return fractionLabel(forInches: value)
        }
    }

    static func fractionLabel(forInches inches: Double) -> String {
        let denominator = inchFractionDenominator
        let totalParts = Int((abs(inches) * Double(denominator)).rounded())
        guard totalParts != 0 else { return "0" }
        let sign = inches < 0 ? "-" : ""
        let whole = totalParts / denominator
        let remainder = totalParts % denominator
        guard remainder != 0 else { return "\(sign)\(whole)" }
        let divisor = greatestCommonDivisor(remainder, denominator)
        let fraction = "\(remainder / divisor)/\(denominator / divisor)"
        return whole == 0 ? "\(sign)\(fraction)" : "\(sign)\(whole) \(fraction)"
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : greatestCommonDivisor(b, a % b)
    }
}

struct CanvasRulers: View {
    static let thickness: CGFloat = 20

    let viewportSize: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize
    let unit: MeasurementUnit
    /// Issue #30 (Nullpunkt zentrieren): rein optischer Versatz der Lineal-BESCHRIFTUNG, wenn
    /// `AppSettings.rulerOriginXCentered`/`…YCentered` aktiv ist — `object.positionX`/`positionY`,
    /// Export und Stichgenerierung bleiben unverändert auf der oberen linken Ecke verankert, nur die
    /// gedruckte Zahl auf dem Lineal verschiebt sich um die halbe Canvas-Breite/-Höhe.
    let originOffsetXMillimeters: Double
    let originOffsetYMillimeters: Double
    let hoverTracker: RulerHoverTracker

    var body: some View {
        ZStack(alignment: .topLeading) {
            horizontalRuler(cursorViewPosition: hoverTracker.location?.x)
                .offset(x: Self.thickness, y: 0)
            verticalRuler(cursorViewPosition: hoverTracker.location?.y)
                .offset(x: 0, y: Self.thickness)
            rulerCorner
        }
    }

    /// "Nice" Zahlen in der jeweiligen Anzeige-Einheit — für mm das klassische 1/2/5-Dekaden-Raster
    /// von Papiralinealen, für Zoll die klassische Halbierungsfolge echter Zollmassstäbe/Bandmasse
    /// (1", 1/2", 1/4", 1/8", …), beschriftet als Bruch (`RulerLabelFormatter`). `majorStepValueInUnit`
    /// wählt die kleinste, die auf dem aktuellen Zoom mindestens `minMajorPixelSpacing` zwischen zwei
    /// beschrifteten Strichen ergibt, sonst würden sich Beschriftungen beim Rauszoomen überlappen.
    private static let niceStepsMillimeters: [Double] = [0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000]
    private static let niceStepsInches: [Double] = [
        1.0 / 64, 1.0 / 32, 1.0 / 16, 1.0 / 8, 1.0 / 4, 1.0 / 2, 1, 2, 4, 8, 16, 32, 64, 128, 256,
    ]

    private func majorStepValueInUnit() -> Double {
        let minMajorPixelSpacing: Double = 45
        let stepsInUnit = unit == .millimeters ? Self.niceStepsMillimeters : Self.niceStepsInches
        for step in stepsInUnit {
            let stepMm = unit.millimeters(from: step)
            if stepMm * Double(zoomScale) >= minMajorPixelSpacing {
                return step
            }
        }
        return stepsInUnit.last ?? 1000
    }

    /// Wie viele Minor-Striche zwischen zwei Major-Strichen liegen — mm folgt dem Leitziffer-Muster
    /// echter Massstäbe (führende 1 → 10 Unterteilungen wie 10mm→1mm, führende 2 → 4 wie 20mm→5mm,
    /// führende 5 → 5 wie 50mm→10mm), Zoll halbiert einfach jede Stufe (1/2, 1/4, 1/8, …).
    private func minorSubdivisionFactor(majorStepValueInUnit: Double) -> Int {
        guard unit == .millimeters else { return 2 }
        let magnitude = pow(10, floor(log10(majorStepValueInUnit)))
        let leadingDigit = (majorStepValueInUnit / magnitude).rounded()
        switch leadingDigit {
        case 2: return 4
        case 5: return 5
        default: return 10
        }
    }

    /// `originOffsetMillimeters` verschiebt NUR die angezeigte Zahl (Nullpunkt-Zentrierung) — die
    /// tatsächliche Strich-POSITION bleibt unverändert an der realen Design-Koordinate.
    private func label(forMillimeters millimeters: Double, originOffsetMillimeters: Double) -> String {
        RulerLabelFormatter.label(forValue: unit.value(fromMillimeters: millimeters - originOffsetMillimeters), unit: unit)
    }

    /// Zeichnet Minor- (kurz, dezent) und Major-Striche (lang, kräftig, beschriftet) für eine Achse.
    /// `minorTick`/`majorTick` bekommen die View-Position des jeweiligen Strichs; gemeinsame Iteration
    /// für horizontales und vertikales Lineal, nur die Zeichen-Closures unterscheiden sich.
    private func drawTicks(
        axisLengthDesign: Double,
        origin: Double,
        scale: CGFloat,
        originOffsetMillimeters: Double,
        minorTick: (Double) -> Void,
        majorTick: (Double, String) -> Void
    ) {
        guard scale > 0 else { return }
        let majorStepValueInUnit = majorStepValueInUnit()
        let majorStepMm = unit.millimeters(from: majorStepValueInUnit)
        let subdivisionFactor = minorSubdivisionFactor(majorStepValueInUnit: majorStepValueInUnit)
        let minorStepMm = majorStepMm / Double(subdivisionFactor)
        let minMinorPixelSpacing: Double = 6
        let drawMinorTicks = minorStepMm * Double(scale) >= minMinorPixelSpacing

        // Issue #30 (Nullpunkt-Bug): das Raster ist am gewählten Nullpunkt selbst verankert
        // (`originOffsetMillimeters`), nicht an der absoluten Canvas-Ecke — sonst landete "0" nur
        // zufällig exakt auf einem Strich, oft aber daneben und wurde dadurch gar nicht angezeigt.
        let firstMajorMm = originOffsetMillimeters
            + (floor(((-origin / scale) - originOffsetMillimeters) / majorStepMm) - 1) * majorStepMm
        let lastMm = (axisLengthDesign - origin) / scale + majorStepMm

        if drawMinorTicks {
            var mm = firstMajorMm
            while mm <= lastMm {
                for step in 1..<subdivisionFactor {
                    let minorMm = mm + minorStepMm * Double(step)
                    minorTick(origin + minorMm * scale)
                }
                mm += majorStepMm
            }
        }

        var mm = firstMajorMm
        while mm <= lastMm {
            majorTick(origin + mm * scale, label(forMillimeters: mm, originOffsetMillimeters: originOffsetMillimeters))
            mm += majorStepMm
        }
    }

    /// Issue #30 (Lineal-Positionsanzeiger): kleiner Punkt an der Ruler-Kante, der der Maus folgt
    /// (Photoshop/Illustrator-Konvention) — `rect` kommt bereits fertig positioniert vom Aufrufer
    /// (an der Aussenkante des jeweiligen Lineals verankert: oben beim horizontalen, links beim
    /// vertikalen Lineal). War ursprünglich als Dreieck geplant, aber ein handgebauter
    /// `move/addLine/closeSubpath`-Pfad blieb aus ungeklärten Gründen unsichtbar (vermutlich eine
    /// GraphicsContext-Eigenheit bei sehr kleinen, manuell konstruierten Pfaden) — ein einfacher
    /// `Path(ellipseIn:)` rendert dagegen zuverlässig auf beiden Linealen.
    private func drawCursorMarker(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(ellipseIn: rect), with: .color(.accentColor))
    }

    /// Oberes Lineal: X-Position in Design-Koordinaten (mm/Zoll je `AppSettings.preferredMeasurementUnit`).
    /// Läuft über die GESAMTE sichtbare Breite (nicht nur innerhalb der Canvas-Seitenränder) — bei
    /// weit rausgezoomter/verschobener Ansicht sind auch Positionen ausserhalb der Zeichenfläche
    /// sichtbar, dieselbe Konvention wie in Illustrator/Figma. `cursorViewPosition` (dieselbe lokale
    /// Koordinate wie der Canvas selbst) zeichnet den kleinen Positionszeiger, `nil` solange die Maus
    /// nicht über dem Canvas ist.
    private func horizontalRuler(cursorViewPosition: CGFloat?) -> some View {
        let scale = zoomScale
        let originX = panOffset.width
        let originOffset = originOffsetXMillimeters
        let unitLabel = unit.symbol

        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(DesignSystem.rulerBackground))

            drawTicks(
                axisLengthDesign: size.width,
                origin: originX,
                scale: scale,
                originOffsetMillimeters: originOffset,
                minorTick: { viewX in
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: viewX, y: size.height - 4))
                            path.addLine(to: CGPoint(x: viewX, y: size.height))
                        },
                        with: .color(DesignSystem.rulerMinorTick)
                    )
                },
                majorTick: { viewX, label in
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: viewX, y: size.height - 9))
                            path.addLine(to: CGPoint(x: viewX, y: size.height))
                        },
                        with: .color(DesignSystem.rulerMajorTick),
                        lineWidth: 1.2
                    )
                    context.draw(
                        Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(DesignSystem.rulerMajorTick),
                        at: CGPoint(x: viewX + 2, y: 3),
                        anchor: .topLeading
                    )
                }
            )
            context.draw(
                Text(unitLabel).font(.system(size: 8)).foregroundStyle(DesignSystem.rulerMinorTick),
                at: CGPoint(x: size.width - 3, y: size.height - 2),
                anchor: .bottomTrailing
            )
            if let cursorViewPosition {
                let markerSize: CGFloat = 6
                drawCursorMarker(
                    in: &context,
                    rect: CGRect(x: cursorViewPosition - markerSize / 2, y: 0, width: markerSize, height: markerSize)
                )
            }
        }
        .frame(width: viewportSize.width, height: Self.thickness)
        .clipped()
        .border(DesignSystem.rulerBorder, width: 0.5)
    }

    /// Linkes Lineal: Y-Position, gespiegelte Logik zu `horizontalRuler` (Text um 90° gedreht,
    /// damit er in der schmalen Spalte lesbar bleibt).
    private func verticalRuler(cursorViewPosition: CGFloat?) -> some View {
        let scale = zoomScale
        let originY = panOffset.height
        let originOffset = originOffsetYMillimeters

        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(DesignSystem.rulerBackground))

            drawTicks(
                axisLengthDesign: size.height,
                origin: originY,
                scale: scale,
                originOffsetMillimeters: originOffset,
                minorTick: { viewY in
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: size.width - 4, y: viewY))
                            path.addLine(to: CGPoint(x: size.width, y: viewY))
                        },
                        with: .color(DesignSystem.rulerMinorTick)
                    )
                },
                majorTick: { viewY, label in
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: size.width - 9, y: viewY))
                            path.addLine(to: CGPoint(x: size.width, y: viewY))
                        },
                        with: .color(DesignSystem.rulerMajorTick),
                        lineWidth: 1.2
                    )
                    let text = Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(DesignSystem.rulerMajorTick)
                    context.drawLayer { layerContext in
                        layerContext.translateBy(x: 3, y: viewY + 2)
                        layerContext.rotate(by: .degrees(-90))
                        layerContext.draw(text, at: .zero, anchor: .topLeading)
                    }
                }
            )
            if let cursorViewPosition {
                let markerSize: CGFloat = 6
                drawCursorMarker(
                    in: &context,
                    rect: CGRect(x: 0, y: cursorViewPosition - markerSize / 2, width: markerSize, height: markerSize)
                )
            }
        }
        .frame(width: Self.thickness, height: viewportSize.height)
        .clipped()
        .border(DesignSystem.rulerBorder, width: 0.5)
    }

    /// Leere Ecke oben links, wo sich beide Lineale träfen.
    private var rulerCorner: some View {
        Rectangle()
            .fill(DesignSystem.rulerBackground)
            .frame(width: Self.thickness, height: Self.thickness)
            .border(DesignSystem.rulerBorder, width: 0.5)
    }
}
