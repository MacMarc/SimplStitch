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
