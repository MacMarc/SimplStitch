//
//  BobbiView.swift
//  SimplStitch
//
//  Issue #27: Bobbi the Twister, das SimplStitch-Maskottchen — eine kleine Spule mit
//  Regenbogen-Faden, Gesicht und einer separaten Garnrolle, die sich dreht, solange
//  SimplStitch Stiche rechnet. Flach/cartoonig wie im Issue entschieden, 4 statische Mimiken.
//
//  Bewusst direkt in SwiftUI gezeichnet statt als SVG-Asset: skaliert verlustfrei, passt sich
//  hell/dunkel nicht an (feste Markenfarben, auf beiden Hintergründen lesbar) und braucht kein
//  Rendering eines Fremdformats. Ein später gelieferter Illustrations-Entwurf kann diese View
//  1:1 ersetzen, alle Einsatzorte nutzen nur `BobbiView(mood:isSpinning:)`.
//
//  Zeichenraum: 100 × 120 Einheiten, wird auf die verfügbare Fläche skaliert.
//

import SwiftUI

enum BobbiMood: CaseIterable {
    /// Leerzustände: freundlich, schaut geradeaus.
    case idle
    /// Während Stiche gerechnet werden: konzentrierter Blick zur Garnrolle.
    case working
    /// Erfolg: geschlossene, lachende Augen.
    case happy
    /// Fehler: betretener Blick nach unten.
    case oops
}

struct BobbiView: View {
    var mood: BobbiMood = .idle
    var isSpinning = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let aspectRatio: CGFloat = 100.0 / 120.0
    /// Sekunden pro Umdrehung der Garnrolle.
    static let spinPeriod: Double = 1.2

    var body: some View {
        TimelineView(.animation(paused: !isSpinning || reduceMotion)) { timeline in
            let angle = isSpinning && !reduceMotion
                ? Angle.degrees(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.spinPeriod) / Self.spinPeriod * 360)
                : .zero
            Canvas { context, size in
                let scale = min(size.width / 100, size.height / 120)
                context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 120 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                BobbiDrawing.draw(in: &context, mood: mood, spoolAngle: angle)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("bobbi.accessibilityLabel"))
    }
}

/// Kleine Sprechblase neben Bobbi (Issue #27: Bobbi darf "sprechen").
struct BobbiSpeechBubble: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum BobbiDrawing {
    static let outline = Color(red: 0.29, green: 0.20, blue: 0.13)
    static let wood = Color(red: 0.85, green: 0.63, blue: 0.40)
    static let face = Color(red: 1.0, green: 0.96, blue: 0.88)
    static let rainbow: [Color] = [
        Color(red: 0.91, green: 0.30, blue: 0.24),
        Color(red: 0.95, green: 0.61, blue: 0.07),
        Color(red: 0.97, green: 0.86, blue: 0.44),
        Color(red: 0.35, green: 0.84, blue: 0.55),
        Color(red: 0.36, green: 0.68, blue: 0.89),
        Color(red: 0.69, green: 0.48, blue: 0.77),
    ]
    static let lineWidth: CGFloat = 2.2

    static func draw(in context: inout GraphicsContext, mood: BobbiMood, spoolAngle: Angle) {
        drawThreadAndSpool(in: &context, angle: spoolAngle)
        drawBody(in: &context)
        drawFace(in: &context, mood: mood)
    }

    private static func drawBody(in context: inout GraphicsContext) {
        // Kern mit Regenbogen-Faden.
        let core = CGRect(x: 18, y: 20, width: 52, height: 80)
        let bandHeight = core.height / CGFloat(rainbow.count)
        for (index, color) in rainbow.enumerated() {
            let band = CGRect(x: core.minX, y: core.minY + CGFloat(index) * bandHeight, width: core.width, height: bandHeight + 0.5)
            context.fill(Path(band), with: .color(color))
        }
        context.stroke(Path(core), with: .color(outline), lineWidth: lineWidth)

        // Flansche oben und unten.
        for y in [CGFloat(10), 98] {
            let flange = Path(roundedRect: CGRect(x: 8, y: y, width: 72, height: 12), cornerRadius: 6)
            context.fill(flange, with: .color(wood))
            context.stroke(flange, with: .color(outline), lineWidth: lineWidth)
        }

        // Helles Gesichtsfeld, damit die Mimik vor den Streifen lesbar bleibt.
        let facePatch = Path(roundedRect: CGRect(x: 24, y: 32, width: 40, height: 56), cornerRadius: 14)
        context.fill(facePatch, with: .color(face))
        context.stroke(facePatch, with: .color(outline), lineWidth: lineWidth * 0.7)
    }

    private static func drawThreadAndSpool(in context: inout GraphicsContext, angle: Angle) {
        let spoolCenter = CGPoint(x: 88, y: 64)

        // Faden vom Kern zur Garnrolle.
        var thread = Path()
        thread.move(to: CGPoint(x: 70, y: 52))
        thread.addQuadCurve(to: CGPoint(x: spoolCenter.x - 2, y: spoolCenter.y - 9), control: CGPoint(x: 82, y: 44))
        context.stroke(thread, with: .color(rainbow[0]), lineWidth: 1.6)

        // Arm, der die Garnrolle hält.
        var arm = Path()
        arm.move(to: CGPoint(x: 70, y: 72))
        arm.addQuadCurve(to: CGPoint(x: spoolCenter.x - 4, y: spoolCenter.y + 4), control: CGPoint(x: 78, y: 76))
        context.stroke(arm, with: .color(outline), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

        // Garnrolle: dreht sich um ihren Mittelpunkt.
        var spool = context
        spool.translateBy(x: spoolCenter.x, y: spoolCenter.y)
        spool.rotate(by: angle)
        let radius: CGFloat = 9
        let disc = Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        spool.fill(disc, with: .color(rainbow[4]))
        spool.stroke(disc, with: .color(outline), lineWidth: lineWidth * 0.8)
        for spoke in 0..<3 {
            let spokeAngle = Double(spoke) * 2 * .pi / 3
            var line = Path()
            line.move(to: .zero)
            line.addLine(to: CGPoint(x: cos(spokeAngle) * (radius - 2), y: sin(spokeAngle) * (radius - 2)))
            spool.stroke(line, with: .color(outline), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        spool.fill(Path(ellipseIn: CGRect(x: -2, y: -2, width: 4, height: 4)), with: .color(wood))
    }

    private static func drawFace(in context: inout GraphicsContext, mood: BobbiMood) {
        let leftEye = CGPoint(x: 36, y: 52)
        let rightEye = CGPoint(x: 52, y: 52)
        let eyeRadius: CGFloat = 6.5

        switch mood {
        case .happy:
            // Geschlossene, lachende Augen (^ ^).
            for eye in [leftEye, rightEye] {
                var arc = Path()
                arc.move(to: CGPoint(x: eye.x - 5, y: eye.y + 2))
                arc.addQuadCurve(to: CGPoint(x: eye.x + 5, y: eye.y + 2), control: CGPoint(x: eye.x, y: eye.y - 6))
                context.stroke(arc, with: .color(outline), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        case .idle, .working, .oops:
            let pupilOffset: CGPoint
            switch mood {
            case .working: pupilOffset = CGPoint(x: 2.5, y: -0.5)
            case .oops: pupilOffset = CGPoint(x: -1.5, y: 2.5)
            default: pupilOffset = .zero
            }
            for eye in [leftEye, rightEye] {
                let white = Path(ellipseIn: CGRect(x: eye.x - eyeRadius, y: eye.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
                context.fill(white, with: .color(.white))
                context.stroke(white, with: .color(outline), lineWidth: lineWidth * 0.8)
                let pupil = CGRect(x: eye.x + pupilOffset.x - 2.8, y: eye.y + pupilOffset.y - 2.8, width: 5.6, height: 5.6)
                context.fill(Path(ellipseIn: pupil), with: .color(outline))
            }
        }

        // Augenbrauen: Neigung trägt die Mimik (innen = zur Gesichtsmitte, negativ = nach oben).
        let lift: (inner: CGFloat, outer: CGFloat) = switch mood {
        case .idle: (0, 0)
        case .working: (1.5, -0.5)
        case .happy: (-1.5, -1.5)
        case .oops: (-2.5, 1)
        }
        for (eye, direction) in [(leftEye, CGFloat(1)), (rightEye, CGFloat(-1))] {
            var brow = Path()
            let baseY = eye.y - 11
            brow.move(to: CGPoint(x: eye.x - 5 * direction, y: baseY + lift.outer))
            brow.addLine(to: CGPoint(x: eye.x + 5 * direction, y: baseY + lift.inner))
            context.stroke(brow, with: .color(outline), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }

        // Mund.
        var mouth = Path()
        let mouthCenter = CGPoint(x: 44, y: 72)
        switch mood {
        case .idle:
            mouth.move(to: CGPoint(x: mouthCenter.x - 7, y: mouthCenter.y))
            mouth.addQuadCurve(to: CGPoint(x: mouthCenter.x + 7, y: mouthCenter.y), control: CGPoint(x: mouthCenter.x, y: mouthCenter.y + 6))
        case .working:
            mouth.move(to: CGPoint(x: mouthCenter.x - 4, y: mouthCenter.y + 1))
            mouth.addLine(to: CGPoint(x: mouthCenter.x + 4, y: mouthCenter.y + 1))
        case .happy:
            mouth.move(to: CGPoint(x: mouthCenter.x - 9, y: mouthCenter.y - 1))
            mouth.addQuadCurve(to: CGPoint(x: mouthCenter.x + 9, y: mouthCenter.y - 1), control: CGPoint(x: mouthCenter.x, y: mouthCenter.y + 11))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(rainbow[0]))
        case .oops:
            mouth.move(to: CGPoint(x: mouthCenter.x - 6, y: mouthCenter.y + 3))
            mouth.addQuadCurve(to: CGPoint(x: mouthCenter.x + 6, y: mouthCenter.y + 3), control: CGPoint(x: mouthCenter.x, y: mouthCenter.y - 3))
        }
        context.stroke(mouth, with: .color(outline), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(Array(BobbiMood.allCases.enumerated()), id: \.offset) { _, mood in
            BobbiView(mood: mood, isSpinning: mood == .working)
                .frame(width: 100, height: 120)
        }
    }
    .padding()
}
