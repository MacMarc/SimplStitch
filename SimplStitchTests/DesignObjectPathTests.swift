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

    // MARK: visualTransform (Issue #9)

    @Test func visualTransformIsIdentityWithoutSkewOrRotation() {
        let object = DesignObject(name: "R", kind: .rectangle, positionX: 0, positionY: 0, width: 10, height: 10)
        #expect(object.visualTransform == .identity)
    }

    /// Rechteck (0,0)-(10,10), Mitte (5,5), skewXDegrees=45 (tan=1). Erwartungswerte von Hand
    /// durchgerechnet: relativ zur Mitte verschiebt sich jeder Punkt um `y * tanX` in x.
    @Test func visualTransformAppliesSkewXAroundCenter() {
        let object = DesignObject(name: "R", kind: .rectangle, positionX: 0, positionY: 0, width: 10, height: 10)
        object.skewXDegrees = 45
        let transform = object.visualTransform

        let topLeft = CGPoint(x: 0, y: 0).applying(transform)
        let bottomRight = CGPoint(x: 10, y: 10).applying(transform)

        #expect(abs(topLeft.x - (-5)) < 0.001)
        #expect(abs(topLeft.y - 0) < 0.001)
        #expect(abs(bottomRight.x - 15) < 0.001)
        #expect(abs(bottomRight.y - 10) < 0.001)
    }

    @Test func visualTransformAppliesSkewYAroundCenter() {
        let object = DesignObject(name: "R", kind: .rectangle, positionX: 0, positionY: 0, width: 10, height: 10)
        object.skewYDegrees = 45
        let transform = object.visualTransform

        let topLeft = CGPoint(x: 0, y: 0).applying(transform)
        let bottomRight = CGPoint(x: 10, y: 10).applying(transform)

        #expect(abs(topLeft.x - 0) < 0.001)
        #expect(abs(topLeft.y - (-5)) < 0.001)
        #expect(abs(bottomRight.x - 10) < 0.001)
        #expect(abs(bottomRight.y - 15) < 0.001)
    }
}
