//
//  EditablePathTests.swift
//  SimplStitchTests
//
//  Issue #19 (Punktgenaues Editieren) — Schritt B1: EditablePath-Modell/-Parser/-Serialisierer.
//

import Testing
import CoreGraphics
import SwiftUI
@testable import SimplStitch

struct EditablePathTests {

    @Test func parsesSimpleLineSegments() {
        let path = EditablePath(pathData: "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000 Z")
        #expect(path.anchors.count == 3)
        #expect(path.anchors[0].point == CGPoint(x: 0, y: 0))
        #expect(path.anchors[1].point == CGPoint(x: 10, y: 0))
        #expect(path.anchors[2].point == CGPoint(x: 10, y: 10))
        #expect(path.anchors.allSatisfy { $0.controlIn == nil && $0.controlOut == nil })
        #expect(path.isClosed)
    }

    @Test func lineRoundtripsThroughSvgPathData() {
        let original = "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000"
        let path = EditablePath(pathData: original)
        #expect(path.svgPathData() == original)
    }

    @Test func parsesCubicCurveAndSetsControlOutOnPreviousAnchor() {
        let path = EditablePath(pathData: "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
        #expect(path.anchors.count == 2)
        #expect(path.anchors[0].point == CGPoint(x: 0, y: 0))
        #expect(path.anchors[0].controlOut == CGPoint(x: 3, y: 6))
        #expect(path.anchors[1].point == CGPoint(x: 10, y: 0))
        #expect(path.anchors[1].controlIn == CGPoint(x: 7, y: 6))
        #expect(path.anchors[1].controlOut == nil)
    }

    @Test func cubicCurveRoundtripsThroughSvgPathData() {
        let original = "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000"
        let path = EditablePath(pathData: original)
        #expect(path.svgPathData() == original)
    }

    @Test func quadraticCurveIsConvertedToExactCubicOnParse() throws {
        // Q: Start (0,0), Kontrollpunkt (5,10), Ende (10,0) — von Hand durchgerechnete 2/3-Regel:
        // C1 = (3.3333, 6.6667), C2 = (6.6667, 6.6667) (siehe SVGPathWriterTests, identische Werte).
        let path = EditablePath(pathData: "M0.0000,0.0000 Q5.0000,10.0000 10.0000,0.0000")
        #expect(path.anchors.count == 2)
        let c1 = try #require(path.anchors[0].controlOut)
        let c2 = try #require(path.anchors[1].controlIn)
        #expect(abs(c1.x - 3.3333) < 0.001)
        #expect(abs(c1.y - 6.6667) < 0.001)
        #expect(abs(c2.x - 6.6667) < 0.001)
        #expect(abs(c2.y - 6.6667) < 0.001)
        // Nach dem Parsen wird nur noch kubisch serialisiert — kein `Q` im Output.
        #expect(path.svgPathData() == "M0.0000,0.0000 C3.3333,6.6667 6.6667,6.6667 10.0000,0.0000")
    }

    @Test func emptyPathDataProducesEmptyPath() {
        let path = EditablePath(pathData: "")
        #expect(path.anchors.isEmpty)
        #expect(path.svgPathData() == "")
        #expect(path.path.isEmpty)
    }

    @Test func boundingBoxOfCubicCurveIncludesControlPoints() {
        // Kontrollpunkte liegen hier weiter aussen als die Endpunkte (0,0)/(10,0) — die konvexe
        // Hülle (und damit die Bounding-Box) muss sie einschliessen, auch wenn die tatsächliche
        // Kurve selbst näher an der Sehne bleibt.
        let path = EditablePath(pathData: "M0.0000,0.0000 C-5.0000,20.0000 15.0000,20.0000 10.0000,0.0000")
        let bounds = path.boundingBox
        #expect(bounds.minX == -5)
        #expect(bounds.maxX == 15)
        #expect(bounds.minY == 0)
        #expect(bounds.maxY == 20)
    }

    @Test func nonDegenerateCurvedPathRendersAsSwiftUIPath() {
        let path = EditablePath(pathData: "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
        let boundingRect = path.path.boundingRect
        #expect(!boundingRect.isEmpty)
        // Eine echte Kurve (Kontrollpunkte bei y=6) wölbt sich über die reine Endpunkt-Sehne
        // (y=0) hinaus — die gerenderte Path-Bounding-Box muss das zeigen, sonst würde trotz
        // Kurvensegmenten fälschlich eine gerade Linie gerendert.
        #expect(boundingRect.maxY > 0.1)
    }
}
