//
//  SVGDesignSerializerTests.swift
//  SimplStitchTests
//
//  Issue #6: generischer SVG-Import (beliebige Illustrator/Inkscape-Dateien, nicht nur unser
//  eigenes content.svg-Schema). Der bestehende Roundtrip unseres eigenen Schemas bleibt über
//  DocumentPackageManagerTests abgedeckt — hier geht es um die neu unterstützten Fälle:
//  Einheiten-Umrechnung, viewBox-Skalierung, <circle>, <g transform>, CSS style=, Polygon/Polyline.
//

import Testing
import CoreGraphics
@testable import SimplStitch

struct SVGDesignSerializerTests {

    private func decode(_ svg: String) throws -> SVGDecodedDesign {
        try SVGDesignSerializer().decode(svg: svg)
    }

    @Test func convertsPixelWidthAndHeightToMillimeters() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="96px" height="192px">
          <rect x="0" y="0" width="48" height="96" fill="#FF0000"/>
        </svg>
        """
        let decoded = try decode(svg)
        #expect(decoded.canvasSize.width == 25.4)
        #expect(decoded.canvasSize.height == 50.8)
        #expect(decoded.objects.count == 1)
        #expect(decoded.objects[0].width == 12.7)
        #expect(decoded.objects[0].height == 25.4)
    }

    @Test func scalesCoordinatesByViewBoxRatio() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm" viewBox="0 0 200 200">
          <rect x="20" y="20" width="40" height="40" fill="#00FF00"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.positionX == 10)
        #expect(object.positionY == 10)
        #expect(object.width == 20)
        #expect(object.height == 20)
    }

    /// Issue #28 (RC3): SVGs ohne `width`/`height`, aber mit gültiger `viewBox` — sehr verbreitet
    /// bei Figma-/Web-Icon-Exporten (`<svg viewBox="0 0 24 24">`). Vor dem Fix kollabierten
    /// `canvasSize` und `unitsToMillimeters` auf 0 (Division durch die fehlende Breite), alle
    /// Objekte landeten auf dem Nullpunkt mit Grösse 0. Fallback: viewBox-Ausdehnung 1:1 als
    /// mm-Canvasgrösse übernehmen (1 User-Unit = 1mm), keine Skalierung.
    /// Issue #28 (RC1): fremde `<path>`-Elemente (kein `data-ss-*`-Schema) wurden bisher gar nicht
    /// skaliert/positioniert — `makePathElement` war `static` und hatte keinen Zugriff auf die
    /// viewBox-/Einheiten-Umrechnung. Jetzt läuft jeder Pfad-Punkt durch dieselbe Pipeline wie bei
    /// `<rect>`/`<polygon>`. 100mm-Canvas, viewBox 0..200 (Faktor 0.5): Dreieck (20,20)-(60,20)-(60,60)
    /// -> (10,10)-(30,10)-(30,30), Bounding-Box (10,10)-(30,30).
    @Test func foreignPathElementIsScaledByViewBoxRatio() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm" viewBox="0 0 200 200">
          <path d="M20,20 L60,20 L60,60 Z" fill="#FF0000"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.kind == .path)
        #expect(abs(object.positionX - 10) < 0.0001)
        #expect(abs(object.positionY - 10) < 0.0001)
        #expect(abs(object.width - 20) < 0.0001)
        #expect(abs(object.height - 20) < 0.0001)
    }

    /// Wie `composesGroupTranslateAndScaleTransform` (für `<rect>`), aber für `<path>` — bestätigt,
    /// dass `makePathElement` dieselbe `<g transform>`-Komposition anwendet wie alle anderen
    /// Elementarten, nicht nur die viewBox-Skalierung.
    @Test func foreignPathElementRespectsGroupTransform() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <g transform="translate(10,20) scale(2)">
            <path d="M0,0 L5,0 L5,5 Z" fill="#000000"/>
          </g>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(abs(object.positionX - 10) < 0.0001)
        #expect(abs(object.positionY - 20) < 0.0001)
        #expect(abs(object.width - 10) < 0.0001)
        #expect(abs(object.height - 10) < 0.0001)
    }

    /// Unser eigenes Schema (`data-ss-x` vorhanden) muss weiterhin unverändert 1:1 durchgereicht
    /// werden — kein Neu-Parsen/-Serialisieren, exakter String-Vergleich (derselbe Roundtrip-Vertrag
    /// wie `DocumentPackageManagerTests`).
    @Test func ownSchemaPathElementPathDataPassesThroughVerbatim() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <path d="M50,60 L70,90 L90,60 Z" data-ss-x="50" data-ss-y="60" data-ss-w="40" data-ss-h="30"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.pathData == "M50,60 L70,90 L90,60 Z")
        #expect(object.positionX == 50)
        #expect(object.positionY == 60)
    }

    @Test func viewBoxOnlySVGWithoutWidthHeightFallsBackToViewBoxAsMillimeters() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
          <rect x="2" y="2" width="10" height="10" fill="#FF0000"/>
        </svg>
        """
        let decoded = try decode(svg)
        #expect(decoded.canvasSize.width == 24)
        #expect(decoded.canvasSize.height == 24)
        let object = try #require(decoded.objects.first)
        #expect(object.positionX == 2)
        #expect(object.positionY == 2)
        #expect(object.width == 10)
        #expect(object.height == 10)
    }

    /// Issue #10: Dateien ohne die neuen `data-ss-bg-opacity`/`data-ss-bg-visible`-Attribute (z.B.
    /// aus einer Zeit vor diesem Feature) müssen auf volle Deckkraft/sichtbar zurückfallen statt auf
    /// 0/versteckt — `DocumentPackageManager`s eigener Schreibpfad setzt diese Attribute inzwischen
    /// immer, daher hier direkt gegen einen handgeschriebenen, absichtlich älteren `<image>`-String.
    @Test func backgroundImageWithoutOpacityOrVisibilityAttributesDefaultsToFullyVisible() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <image href="assets/bg.png" x="0" y="0" width="100" height="100" data-ss-role="background" />
        </svg>
        """
        let decoded = try decode(svg)
        #expect(decoded.backgroundImageFileName == "bg.png")
        #expect(decoded.backgroundImageOpacity == 1.0)
        #expect(decoded.isBackgroundImageVisible == true)
    }

    @Test func parsesCircleShorthandElement() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <circle cx="50" cy="50" r="10" fill="#0000FF"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.kind == .circle)
        #expect(object.positionX == 40)
        #expect(object.positionY == 40)
        #expect(object.width == 20)
        #expect(object.height == 20)
    }

    @Test func composesGroupTranslateAndScaleTransform() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <g transform="translate(10,20) scale(2)">
            <rect x="0" y="0" width="5" height="5" fill="#000000"/>
          </g>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.positionX == 10)
        #expect(object.positionY == 20)
        #expect(object.width == 10)
        #expect(object.height == 10)
    }

    @Test func groupTransformDoesNotLeakToSiblingsAfterClosingTag() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <g transform="translate(50,50)">
            <rect x="0" y="0" width="5" height="5" fill="#000000"/>
          </g>
          <rect x="0" y="0" width="5" height="5" fill="#FFFFFF"/>
        </svg>
        """
        let decoded = try decode(svg)
        #expect(decoded.objects.count == 2)
        #expect(decoded.objects[0].positionX == 50)
        #expect(decoded.objects[1].positionX == 0)
    }

    @Test func readsFillColorFromCSSStyleAttribute() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <rect x="0" y="0" width="10" height="10" style="stroke:#000000;fill:#ABCDEF"/>
        </svg>
        """
        let decoded = try decode(svg)
        #expect(decoded.objects.first?.fillColorHex == "#ABCDEF")
    }

    @Test func fillNoneMarksObjectAsUnfilled() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <rect x="0" y="0" width="10" height="10" fill="none"/>
        </svg>
        """
        let decoded = try decode(svg)
        #expect(decoded.objects.first?.hasFill == false)
    }

    // Issue #30: eine fremde SVG-Datei ohne data-ss-x hat nie inkstitch:*-Attribute — hasFill wird
    // nur aus der Quell-Füllfarbe hergeleitet (siehe fillNoneMarksObjectAsUnfilled). Ohne einen
    // Fallback in applyCommonAttributes bliebe stitchSettings dauerhaft nil: refreshStitchPreview()s
    // Guard (hasFill && stitchSettings != nil) generiert dann NIE eine Stichvorschau, und .path hat
    // ohnehin keine eigene Vektor-Füllfarbe im Canvas-Rendering — das importierte Objekt bliebe
    // dauerhaft leer/weiss, obwohl "Füllung" laut Inspector schon aktiv ist.
    @Test func foreignFilledPathGetsDefaultStitchSettings() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <path d="M0,0 L10,0 L10,10 L0,10 Z" fill="#a71930"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.hasFill == true)
        #expect(object.stitchSettings?.stitchType == .tatami)
    }

    @Test func foreignUnfilledPathGetsNoStitchSettings() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <path d="M0,0 L10,0 L10,10 L0,10 Z" fill="none"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.hasFill == false)
        #expect(object.stitchSettings == nil)
    }

    @Test func parsesClosedPolygonAsPathWithZ() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <polygon points="0,0 10,0 10,10 0,10" fill="#112233"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.kind == .path)
        #expect(object.positionX == 0)
        #expect(object.positionY == 0)
        #expect(object.width == 10)
        #expect(object.height == 10)
        #expect(object.pathData?.hasSuffix("Z") == true)
    }

    @Test func parsesOpenPolylineWithoutClosingZ() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100mm" height="100mm">
          <polyline points="0,0 10,0 10,10" fill="none"/>
        </svg>
        """
        let decoded = try decode(svg)
        let object = try #require(decoded.objects.first)
        #expect(object.kind == .path)
        #expect(object.pathData?.hasSuffix("Z") == false)
    }
}
