//
//  SwiftDataModelsTests.swift
//  SimplStitchTests
//
//  Phase-3-Checkpoint: Models persistent, Roundtrip + Cascade-Delete grün.
//

import Testing
import SwiftData
@testable import SimplStitch

struct SwiftDataModelsTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            StitchProject.self,
            DesignObject.self,
            StitchSettings.self,
            ThreadColor.self,
            ThreadPalette.self,
            AppSettings.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func projectWithDesignObjectsAndStitchSettingsRoundtrips() throws {
        let context = try makeInMemoryContext()

        let project = StitchProject(name: "Testprojekt", lastKnownPath: "/tmp/Testprojekt.stitchdesign")

        let circle = DesignObject(name: "Kreis 1", kind: .circle, positionX: 10, positionY: 20, width: 30, height: 30)
        circle.stitchSettings = StitchSettings(stitchType: .tatami, density: 0.35, angleDegrees: 45, underlayType: .zigzagNet)
        circle.project = project

        let text = DesignObject(name: "Text 1", kind: .text)
        text.text = "SimplStitch"
        text.fontName = "Helvetica"
        text.fontSize = 24
        text.project = project

        project.objects = [circle, text]

        context.insert(project)
        try context.save()

        let fetchedProjects = try context.fetch(FetchDescriptor<StitchProject>())
        #expect(fetchedProjects.count == 1)
        let fetchedProject = try #require(fetchedProjects.first)
        #expect(fetchedProject.objects.count == 2)

        let fetchedCircle = try #require(fetchedProject.objects.first { $0.kind == .circle })
        #expect(fetchedCircle.stitchSettings?.stitchType == .tatami)
        #expect(fetchedCircle.stitchSettings?.underlayType == .zigzagNet)

        let fetchedText = try #require(fetchedProject.objects.first { $0.kind == .text })
        #expect(fetchedText.text == "SimplStitch")
    }

    @Test func deletingProjectCascadesToObjectsAndStitchSettings() throws {
        let context = try makeInMemoryContext()

        let project = StitchProject(name: "Löschtest", lastKnownPath: "/tmp/Löschtest.stitchdesign")
        let object = DesignObject(name: "Form", kind: .rectangle)
        object.stitchSettings = StitchSettings()
        object.project = project
        project.objects = [object]

        context.insert(project)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<DesignObject>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<StitchSettings>()) == 1)

        context.delete(project)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<DesignObject>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<StitchSettings>()) == 0)
    }

    @Test func threadPaletteWithColorsRoundtrips() throws {
        let context = try makeInMemoryContext()

        let palette = ThreadPalette(name: "Madeira Rayon No. 40", isBuiltIn: true)
        let red = ThreadColor(name: "Poppy Red", red: 218, green: 37, blue: 29, manufacturerName: "Madeira", catalogNumber: "1147")
        let blue = ThreadColor(name: "Ocean Blue", red: 20, green: 70, blue: 160, manufacturerName: "Madeira", catalogNumber: "1244")
        red.palette = palette
        blue.palette = palette
        palette.colors = [red, blue]

        context.insert(palette)
        try context.save()

        let fetchedPalettes = try context.fetch(FetchDescriptor<ThreadPalette>())
        #expect(fetchedPalettes.count == 1)
        #expect(fetchedPalettes.first?.colors.count == 2)

        context.delete(palette)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ThreadColor>()) == 0)
    }

    @Test func appSettingsDefaults() throws {
        let context = try makeInMemoryContext()
        let settings = AppSettings()
        context.insert(settings)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<AppSettings>()).first)
        #expect(fetched.preferredMeasurementUnit == .millimeters)
        #expect(fetched.maxRecentProjects == 10)
        #expect(fetched.toolbarSize == .medium)
    }

    // Issue #23: ObjectInspectorView rechnet Position/Grösse/Randdicke jetzt je nach
    // `preferredMeasurementUnit` um — die reine Umrechnungslogik gehört ins Modell, nicht in die View.
    @Test func measurementUnitConvertsMillimetersToInchesAndBack() {
        #expect(MeasurementUnit.millimeters.value(fromMillimeters: 25.4) == 25.4)
        #expect(MeasurementUnit.inches.value(fromMillimeters: 25.4) == 1)
        #expect(MeasurementUnit.inches.millimeters(from: 1) == 25.4)
        #expect(MeasurementUnit.millimeters.millimeters(from: 12) == 12)
    }

    @Test func measurementUnitSymbols() {
        #expect(MeasurementUnit.millimeters.symbol == "mm")
        #expect(MeasurementUnit.inches.symbol == "in")
    }
}
