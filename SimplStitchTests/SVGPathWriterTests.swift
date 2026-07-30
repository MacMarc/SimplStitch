//
//  SVGPathWriterTests.swift
//  SimplStitchTests
//
//  Gemeinsamer Bézier-Pfad-Schreiber (Text-embroiderable + Issue #19).
//

import Testing
import CoreGraphics
@testable import SimplStitch

struct SVGPathWriterTests {

    @Test func writesMoveLineAndClose() {
        let segments: [SVGPathSegment] = [
            .moveTo(CGPoint(x: 0, y: 0)),
            .lineTo(CGPoint(x: 10, y: 0)),
            .closePath,
        ]
        #expect(SVGPathWriter.string(from: segments) == "M0.0000,0.0000 L10.0000,0.0000 Z")
    }

    @Test func writesCubicCurve() {
        let segments: [SVGPathSegment] = [
            .moveTo(CGPoint(x: 0, y: 0)),
            .curveTo(CGPoint(x: 10, y: 0), control1: CGPoint(x: 3, y: 6), control2: CGPoint(x: 7, y: 6)),
        ]
        #expect(SVGPathWriter.string(from: segments) == "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
    }

    @Test func cubicControlPointsMatchHandComputedQuadraticConversion() {
        // Q: Start (0,0), Kontrollpunkt (5,10), Ende (10,0) — 2/3-Regel von Hand durchgerechnet:
        // C1 = (0,0) + 2/3*(5,10) = (3.3333, 6.6667); C2 = (10,0) + 2/3*(5-10, 10-0) = (6.6667, 6.6667)
        let (c1, c2) = SVGPathWriter.cubicControlPoints(
            start: CGPoint(x: 0, y: 0),
            quadControl: CGPoint(x: 5, y: 10),
            end: CGPoint(x: 10, y: 0)
        )
        #expect(abs(c1.x - 3.3333) < 0.001)
        #expect(abs(c1.y - 6.6667) < 0.001)
        #expect(abs(c2.x - 6.6667) < 0.001)
        #expect(abs(c2.y - 6.6667) < 0.001)
    }

    @Test func cgPathQuadCurveProducesExactCubicSVGData() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addQuadCurve(to: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 10))
        #expect(path.svgPathData() == "M0.0000,0.0000 C3.3333,6.6667 6.6667,6.6667 10.0000,0.0000")
    }

    @Test func cgPathLineAndCloseRoundtrips() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 0))
        path.addLine(to: CGPoint(x: 10, y: 10))
        path.closeSubpath()
        #expect(path.svgPathData() == "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000 Z")
    }

    @Test func cgPathRealCubicCurvePassesThroughUnchanged() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addCurve(to: CGPoint(x: 10, y: 0), control1: CGPoint(x: 2, y: 5), control2: CGPoint(x: 8, y: 5))
        #expect(path.svgPathData() == "M0.0000,0.0000 C2.0000,5.0000 8.0000,5.0000 10.0000,0.0000")
    }
}
