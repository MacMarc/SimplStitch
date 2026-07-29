//
//  DesignObjectPathTests.swift
//  SimplStitchTests
//
//  Phase-5b-Checkpoint: DesignObject → Path fürs Canvas-Rendering.
//

import Testing
import SwiftUI
@testable import SimplStitch

struct DesignObjectPathTests {

    @Test func rectanglePathBoundingRectMatchesObjectBounds() {
        let object = DesignObject(name: "R", kind: .rectangle, positionX: 10, positionY: 20, width: 30, height: 40)
        let rect = object.designSpacePath().boundingRect
        #expect(abs(rect.minX - 10) < 0.001)
        #expect(abs(rect.minY - 20) < 0.001)
        #expect(abs(rect.width - 30) < 0.001)
        #expect(abs(rect.height - 40) < 0.001)
    }

    @Test func circlePathBoundingRectMatchesObjectBounds() {
        let object = DesignObject(name: "C", kind: .circle, positionX: 5, positionY: 5, width: 20, height: 10)
        let rect = object.designSpacePath().boundingRect
        #expect(abs(rect.minX - 5) < 0.001)
        #expect(abs(rect.minY - 5) < 0.001)
        #expect(abs(rect.width - 20) < 0.001)
        #expect(abs(rect.height - 10) < 0.001)
    }

    @Test func starPathIsNonEmptyClosedShape() {
        let object = DesignObject(name: "S", kind: .star, positionX: 0, positionY: 0, width: 20, height: 20)
        object.starPointCount = 5
        let path = object.designSpacePath()
        #expect(path.isEmpty == false)
        // Ein 5-zackiger Stern liegt innerhalb des quadratischen Umkreises der Bounding-Box.
        let rect = path.boundingRect
        #expect(rect.width <= 20.001)
        #expect(rect.height <= 20.001)
    }

    @Test func freehandPathParsesPointsFromPathData() {
        let object = DesignObject(name: "P", kind: .path, positionX: 0, positionY: 0, width: 10, height: 10)
        object.pathData = "M0.0000,0.0000 L10.0000,0.0000 L10.0000,10.0000"
        let rect = object.designSpacePath().boundingRect
        #expect(abs(rect.width - 10) < 0.001)
        #expect(abs(rect.height - 10) < 0.001)
    }

    @Test func emptyPathDataProducesEmptyPath() {
        let object = DesignObject(name: "P", kind: .path, positionX: 0, positionY: 0, width: 0, height: 0)
        let path = object.designSpacePath()
        #expect(path.isEmpty)
    }
}
