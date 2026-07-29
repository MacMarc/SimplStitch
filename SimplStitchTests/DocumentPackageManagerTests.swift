//
//  DocumentPackageManagerTests.swift
//  SimplStitchTests
//
//  Phase-4-Checkpoint: Projekt speichern und wieder öffnen — alle Objekte erhalten.
//

import Testing
import Foundation
@testable import SimplStitch

struct DocumentPackageManagerTests {

    /// Feste ID statt `UUID()` pro Aufruf — `makeSampleProject()` wird von mehreren Tests
    /// aufgerufen, die dieselbe Gruppen-ID nach dem Roundtrip wiedererkennen müssen (Issue #16).
    private static let sampleGroupID = UUID()
    private static let sampleDefaultThreadPaletteID = UUID()

    private func makeTempPackageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("stitchdesign")
    }

    private func makeSampleProject() -> StitchProject {
        let project = StitchProject(name: "Testdesign", lastKnownPath: "", canvasWidthMillimeters: 130, canvasHeightMillimeters: 180)

        let rectangle = DesignObject(name: "Rechteck", kind: .rectangle, positionX: 5, positionY: 10, width: 40, height: 20)
        rectangle.cornerRadius = 4
        rectangle.zIndex = 0
        rectangle.fillColorHex = "#FF0000"
        rectangle.groupID = Self.sampleGroupID
        // Real InkStitch kennt für Tatami nur ein An/Aus-Bool (kein Typ) — jeder Nicht-.none-Wert
        // wird beim Roundtrip auf .centerWalk normalisiert (siehe SVGDesignSerializer, Phase 6c).
        rectangle.stitchSettings = StitchSettings(stitchType: .tatami, density: 0.4, angleDegrees: 45, underlayType: .centerWalk)
        // Issue #18: Füllung UND Rand gleichzeitig, um zu verifizieren, dass beide unabhängig
        // voneinander persistieren.
        rectangle.hasBorder = true
        rectangle.borderWidthMillimeters = 0.6
        rectangle.borderColorHex = "#00FFFF"
        rectangle.borderStitchSettings = StitchSettings(stitchType: .straight, density: 0.25, angleDegrees: 0, underlayType: .none)

        let line = DesignObject(name: "Linie", kind: .line, positionX: 0, positionY: 0, width: 20, height: 10)
        line.pathData = "M0,0 L20,10"
        line.zIndex = 5
        line.hasFill = false
        line.hasBorder = true
        line.borderStitchSettings = StitchSettings(stitchType: .straight, density: 0.3, angleDegrees: 0, underlayType: .none)

        let circle = DesignObject(name: "Kreis", kind: .circle, positionX: 60, positionY: 10, width: 30, height: 30)
        circle.zIndex = 1
        circle.fillColorHex = "#00FF00"
        circle.rotationDegrees = 15
        circle.stitchSettings = StitchSettings(stitchType: .satin, density: 0.3, angleDegrees: 90, underlayType: .edgeWalk)

        let star = DesignObject(name: "Stern", kind: .star, positionX: 10, positionY: 60, width: 25, height: 25)
        star.starPointCount = 6
        star.zIndex = 2
        star.isLocked = true

        let path = DesignObject(name: "Freihand", kind: .path, positionX: 50, positionY: 60, width: 40, height: 30)
        path.pathData = "M50,60 L70,90 L90,60 Z"
        path.zIndex = 3
        path.isVisible = false

        let text = DesignObject(name: "Text", kind: .text, positionX: 10, positionY: 110, width: 60, height: 20)
        text.text = "SimplStitch äöü"
        text.fontName = "Helvetica"
        text.fontSize = 18
        text.zIndex = 4
        text.skewXDegrees = 5
        text.skewYDegrees = -3

        let objects = [rectangle, circle, star, path, text, line]
        for object in objects {
            object.project = project
        }
        project.objects = objects
        project.defaultThreadPaletteID = Self.sampleDefaultThreadPaletteID

        return project
    }

    @Test func saveAndReopenPreservesAllObjects() throws {
        let manager = DocumentPackageManager()
        let project = makeSampleProject()
        let packageURL = makeTempPackageURL()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        try manager.write(project, to: packageURL, importingBackgroundImageFrom: nil)

        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("content.svg").path))
        let previewURL = packageURL.appendingPathComponent("preview.png")
        #expect(FileManager.default.fileExists(atPath: previewURL.path))
        let previewData = try Data(contentsOf: previewURL)
        #expect(previewData.starts(with: [0x89, 0x50, 0x4E, 0x47])) // PNG-Magic-Bytes

        let reopened = try manager.read(from: packageURL)

        #expect(reopened.objects.count == 6)
        #expect(abs(reopened.canvasWidthMillimeters - 130) < 0.001)
        #expect(abs(reopened.canvasHeightMillimeters - 180) < 0.001)
        #expect(reopened.defaultThreadPaletteID == Self.sampleDefaultThreadPaletteID)

        let rectangle = try #require(reopened.objects.first { $0.kind == .rectangle })
        #expect(rectangle.name == "Rechteck")
        #expect(abs(rectangle.positionX - 5) < 0.001)
        #expect(abs(rectangle.positionY - 10) < 0.001)
        #expect(abs(rectangle.width - 40) < 0.001)
        #expect(abs(rectangle.height - 20) < 0.001)
        #expect(abs(rectangle.cornerRadius - 4) < 0.001)
        #expect(rectangle.fillColorHex == "#FF0000")
        #expect(rectangle.groupID == Self.sampleGroupID)
        let rectangleSettings = try #require(rectangle.stitchSettings)
        #expect(rectangleSettings.stitchType == .tatami)
        #expect(rectangleSettings.underlayType == .centerWalk)
        #expect(abs(rectangleSettings.angleDegrees - 45) < 0.001)
        #expect(abs(rectangleSettings.density - 0.4) < 0.001)
        #expect(rectangle.hasFill == true)
        #expect(rectangle.hasBorder == true)
        #expect(abs(rectangle.borderWidthMillimeters - 0.6) < 0.001)
        #expect(rectangle.borderColorHex == "#00FFFF")
        let rectangleBorderSettings = try #require(rectangle.borderStitchSettings)
        #expect(rectangleBorderSettings.stitchType == .straight)
        #expect(abs(rectangleBorderSettings.density - 0.25) < 0.001)

        let circle = try #require(reopened.objects.first { $0.kind == .circle })
        #expect(abs(circle.positionX - 60) < 0.001)
        #expect(abs(circle.width - 30) < 0.001)
        #expect(abs(circle.rotationDegrees - 15) < 0.001)
        let circleSettings = try #require(circle.stitchSettings)
        #expect(circleSettings.stitchType == .satin)
        // Satin kennt (anders als Tatami) drei unterscheidbare Unterlage-Typen — .edgeWalk
        // (contour_underlay) roundtrippt daher verlustfrei.
        #expect(circleSettings.underlayType == .edgeWalk)
        #expect(abs(circleSettings.density - 0.3) < 0.001)

        let star = try #require(reopened.objects.first { $0.kind == .star })
        #expect(star.starPointCount == 6)
        #expect(star.isLocked == true)
        #expect(star.pathData == nil) // wird beim Schreiben aus Position/Grösse synthetisiert, nicht zurückgespeichert

        let path = try #require(reopened.objects.first { $0.kind == .path })
        #expect(path.pathData == "M50,60 L70,90 L90,60 Z")
        #expect(path.isVisible == false)

        let text = try #require(reopened.objects.first { $0.kind == .text })
        #expect(text.text == "SimplStitch äöü")
        #expect(text.fontName == "Helvetica")
        #expect(abs((text.fontSize ?? 0) - 18) < 0.001)
        #expect(abs(text.skewXDegrees - 5) < 0.001)
        #expect(abs(text.skewYDegrees - (-3)) < 0.001)

        let line = try #require(reopened.objects.first { $0.kind == .line })
        #expect(line.pathData == "M0,0 L20,10")
        #expect(line.hasFill == false)
        #expect(line.hasBorder == true)
        #expect(line.borderStitchSettings?.stitchType == .straight)
    }

    @Test func backgroundImageIsCopiedIntoAssetsFolder() throws {
        let manager = DocumentPackageManager()
        let project = makeSampleProject()
        let packageURL = makeTempPackageURL()
        defer { try? FileManager.default.removeItem(at: packageURL) }

        let sourceImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: sourceImageURL)
        defer { try? FileManager.default.removeItem(at: sourceImageURL) }

        try manager.write(project, to: packageURL, importingBackgroundImageFrom: sourceImageURL)

        #expect(project.backgroundImageFileName == sourceImageURL.lastPathComponent)
        let assetPath = packageURL.appendingPathComponent("assets").appendingPathComponent(sourceImageURL.lastPathComponent)
        #expect(FileManager.default.fileExists(atPath: assetPath.path))

        let reopened = try manager.read(from: packageURL)
        #expect(reopened.backgroundImageFileName == sourceImageURL.lastPathComponent)
    }

    @Test func writingRejectsWrongExtension() throws {
        let manager = DocumentPackageManager()
        let project = makeSampleProject()
        let wrongURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")

        #expect(throws: DocumentPackageError.self) {
            try manager.write(project, to: wrongURL, importingBackgroundImageFrom: nil)
        }
    }
}
