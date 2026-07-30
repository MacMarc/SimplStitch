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

    // MARK: Issue #28 (RC2) — echter SVG-Pfad-Tokenizer, H/V/S/T/A, relative Kommandos, implizite
    // Kommando-Wiederholung, an Kommandos geklebte Zahlen.

    @Test func parsesRelativeLineCommands() {
        let path = EditablePath(pathData: "M0,0 l10,0 l0,10")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    }

    @Test func parsesImplicitLinetoRepeatAfterMoveto() {
        // SVG-Spec: auf ein `M` folgende weitere Koordinatenpaare ohne neues Kommando sind implizite `L`.
        let path = EditablePath(pathData: "M0,0 10,0 10,10")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    }

    @Test func parsesImplicitCommandRepeatForLineto() {
        let path = EditablePath(pathData: "M0,0 L10,0 20,0 30,0")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 0)])
    }

    @Test func parsesHorizontalAndVerticalLineto() {
        let path = EditablePath(pathData: "M0,0 H10 V10")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    }

    @Test func parsesRelativeHorizontalAndVerticalLineto() {
        let path = EditablePath(pathData: "M0,0 h10 v10")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    }

    /// Reale Exporte kleben Kommandos direkt an die erste Zahl (`M10,20C30,40 …`) statt ein
    /// Leerzeichen zu setzen — der alte `split(" ")`-Parser scheiterte daran.
    @Test func parsesCommandsGluedDirectlyToNumbersWithoutSeparator() {
        let glued = EditablePath(pathData: "M0,0C3,6 7,6 10,0")
        let spaced = EditablePath(pathData: "M0.0000,0.0000 C3.0000,6.0000 7.0000,6.0000 10.0000,0.0000")
        #expect(glued.anchors == spaced.anchors)
    }

    /// Zwei aneinandergereihte Dezimalzahlen ohne Trennzeichen (`0.5.5`) — der zweite Punkt
    /// beendet die erste Zahl und beginnt die nächste, ein bekanntes reales SVG-Minifizierungsmuster.
    @Test func parsesGluedDecimalNumbersWithoutSeparator() {
        let path = EditablePath(pathData: "M0.5.5L1.5.5")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1.5, y: 0.5)])
    }

    /// `S` spiegelt den ersten Kontrollpunkt an der aktuellen Position, wenn das vorherige Kommando
    /// aus der C/S-Familie stammt: C endet mit Kontrollpunkt (10,10) bei aktueller Position (10,0) ->
    /// gespiegelt (2*10-10, 2*0-10) = (10,-10).
    @Test func smoothCubicReflectsPreviousControlPointFromCurve() throws {
        let path = EditablePath(pathData: "M0,0 C0,10 10,10 10,0 S20,-10 20,0")
        #expect(path.anchors.count == 3)
        let reflectedControl1 = try #require(path.anchors[1].controlOut)
        #expect(abs(reflectedControl1.x - 10) < 0.0001)
        #expect(abs(reflectedControl1.y - (-10)) < 0.0001)
        #expect(path.anchors[2].point == CGPoint(x: 20, y: 0))
    }

    /// Ohne vorangehende Kurve derselben Familie (hier: `L` statt `C`/`S`) ist der erste
    /// Kontrollpunkt von `S` per Spec die aktuelle Position selbst, keine Spiegelung.
    @Test func smoothCubicWithoutPrecedingCurveUsesCurrentPointAsFirstControl() throws {
        let path = EditablePath(pathData: "M0,0 L10,0 S20,10 20,0")
        let control1 = try #require(path.anchors[1].controlOut)
        #expect(control1 == CGPoint(x: 10, y: 0))
    }

    /// `T` (glatte Quadratik) analog zu `S`, aber für die Q/T-Familie.
    @Test func smoothQuadraticReflectsPreviousControlPointFromCurve() throws {
        // Q: Start (0,0), Kontrollpunkt (5,10), Ende (10,0) -> gespiegelter Kontrollpunkt für T bei
        // aktueller Position (10,0): (2*10-5, 2*0-10) = (15,-10).
        let path = EditablePath(pathData: "M0,0 Q5,10 10,0 T20,0")
        #expect(path.anchors.count == 3)
        // Q/T werden intern exakt in kubisch überführt — die Reflektion selbst prüfen wir über den
        // Vergleich mit einem manuell mit dem erwarteten Kontrollpunkt geschriebenen Q-Äquivalent.
        let expectedViaExplicitQ = EditablePath(pathData: "M0,0 Q5,10 10,0 Q15,-10 20,0")
        #expect(path.anchors[2].controlIn == expectedViaExplicitQ.anchors[2].controlIn)
    }

    /// `A` (elliptischer Bogen) wird in eine kubische Näherung überführt. Viertelkreis von (10,0)
    /// nach (0,10), Radius 10, Mittelpunkt im Ursprung — jeder Punkt der ECHTEN Kurve liegt exakt
    /// im Abstand 10 vom Ursprung. Prüft die Näherung über den Bézier-Mittelpunkt (t=0.5, Standard-
    /// Formel `0.125·P0 + 0.375·C1 + 0.375·C2 + 0.125·P3`) statt exakter Kontrollpunkt-Koordinaten,
    /// um unabhängig von Vorzeichen-/Rotationskonventionen zu bleiben — die bekannte maximale
    /// radiale Abweichung einer kappa-approximierten 90°-Bogen-Kurve liegt bei < 0.03% des Radius.
    @Test func ellipticalArcApproximatesQuarterCircleCloseToTrueRadius() throws {
        let path = EditablePath(pathData: "M10,0 A10,10 0 0,1 0,10")
        #expect(path.anchors.count == 2)
        #expect(path.anchors[0].point == CGPoint(x: 10, y: 0))
        #expect(path.anchors[1].point == CGPoint(x: 0, y: 10))

        let p0 = path.anchors[0].point
        let c1 = try #require(path.anchors[0].controlOut)
        let c2 = try #require(path.anchors[1].controlIn)
        let p3 = path.anchors[1].point
        let midpoint = CGPoint(
            x: 0.125 * p0.x + 0.375 * c1.x + 0.375 * c2.x + 0.125 * p3.x,
            y: 0.125 * p0.y + 0.375 * c1.y + 0.375 * c2.y + 0.125 * p3.y
        )
        let radius = (midpoint.x * midpoint.x + midpoint.y * midpoint.y).squareRoot()
        #expect(abs(radius - 10) < 0.05)
    }

    /// Identische Start-/Endpunkte erzeugen laut Spec keine Kurve — muss ohne Absturz/Endlosschleife
    /// glatt durchlaufen (z.B. Division durch 0 bei identischem Start/Ende wäre sonst ein Risiko).
    @Test func ellipticalArcWithIdenticalEndpointsProducesNoSegment() {
        let path = EditablePath(pathData: "M10,0 A5,5 0 0,1 10,0 L20,0")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0)])
    }

    /// Ein Radius von 0 ist per Spec eine Gerade zum Zielpunkt statt einer echten Ellipse.
    @Test func ellipticalArcWithZeroRadiusDegeneratesToLine() {
        let path = EditablePath(pathData: "M0,0 A0,0 0 0,1 10,10")
        #expect(path.anchors.map(\.point) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        #expect(path.anchors[1].controlIn == nil || path.anchors[1].controlIn == CGPoint(x: 10, y: 10))
    }

    // MARK: Issue #30 — mehrere Teilpfade (mehrfaches `M`), z.B. JUMP-Stiche beim Reimport.

    /// Der Kernfall: ein reimportierter Pfad kodiert einen Sprung (JUMP, Nadel ohne Faden) als ein
    /// zweites `M` statt eines verbindenden `L`. Der erste Anker JEDES Teilpfad-Starts (ausser dem
    /// allerersten Anker des Pfades) muss als solcher markiert sein, sonst verschmilzt die Lücke.
    @Test func secondMoveStartsNewSubpath() {
        let path = EditablePath(pathData: "M0,0 L10,0 M20,0 L30,0")
        #expect(path.anchors.count == 4)
        #expect(path.anchors.map(\.point) == [
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 0),
        ])
        // Nur der Anker bei (20,0) beginnt einen neuen Teilpfad — der allererste Anker (0,0) nicht.
        #expect(path.anchors.map(\.startsSubpath) == [false, false, true, false])
    }

    /// Ein mehrfach-`M`-Pfad muss verlustfrei durch svgPathData() zurücklaufen — die Sprung-Grenze
    /// bleibt als eigenes `M` erhalten (vorher wurde daraus fälschlich ein durchgezogenes `L`).
    @Test func multipleSubpathsRoundtripThroughSvgPathData() {
        let original = "M0.0000,0.0000 L10.0000,0.0000 M20.0000,0.0000 L30.0000,0.0000"
        let path = EditablePath(pathData: original)
        #expect(path.svgPathData() == original)
    }

    /// Rendering: der `path`-Getter darf die beiden Teilpfade NICHT verbinden. Eine durchgezogene
    /// Linie über die ganze Breite hätte dieselbe Bounding-Box wie zwei getrennte Segmente, daher
    /// prüfen wir stattdessen die Anzahl der Teilpfade direkt über die CoreGraphics-Elemente.
    @Test func pathGetterKeepsSubpathsDisconnected() {
        let path = EditablePath(pathData: "M0,0 L10,0 M20,0 L30,0")
        var moveCount = 0
        path.path.cgPath.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { moveCount += 1 }
        }
        // Zwei `move`-Elemente == zwei getrennte Teilpfade (ein verschmolzener Pfad hätte nur eins).
        #expect(moveCount == 2)
    }

    /// Simuliert exakt den `CanvasStore.transformedEditablePath`-Pfad (Verschieben/Skalieren eines
    /// reimportierten Objekts): Anker-Punkte transformieren, dann re-serialisieren. Die Sprung-Grenze
    /// muss erhalten bleiben — sonst würde das erste Verschieben die Jump-Info permanent zerstören.
    @Test func transformingAnchorsPreservesSubpathBreakOnReserialize() {
        var path = EditablePath(pathData: "M0,0 L10,0 M20,0 L30,0")
        for index in path.anchors.indices {
            path.anchors[index].point = CGPoint(x: path.anchors[index].point.x + 5, y: path.anchors[index].point.y + 5)
        }
        #expect(path.svgPathData() == "M5.0000,5.0000 L15.0000,5.0000 M25.0000,5.0000 L35.0000,5.0000")
    }

    /// Der bisherige Einzel-Teilpfad-Fall bleibt unberührt: kein `startsSubpath`, kein zusätzliches `M`.
    @Test func singleSubpathHasNoSubpathBreaks() {
        let path = EditablePath(pathData: "M0,0 L10,0 L10,10")
        #expect(path.anchors.allSatisfy { !$0.startsSubpath })
    }
}
