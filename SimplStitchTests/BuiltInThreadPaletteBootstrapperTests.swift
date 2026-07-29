//
//  BuiltInThreadPaletteBootstrapperTests.swift
//  SimplStitchTests
//
//  Issue #13: Standard-Garnlisten müssen beim ersten Start automatisch vorhanden sein — reiner
//  Swift-Test gegen ein Temp-Verzeichnis mit Wegwerf-.gpl-Dateien statt der echten (grossen)
//  vendorten InkStitch-Paletten, und einen in-memory `ModelContainer`.
//

import Testing
import Foundation
import SwiftData
@testable import SimplStitch

struct BuiltInThreadPaletteBootstrapperTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([ThreadColor.self, ThreadPalette.self, AppSettings.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeSampleGPLDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = """
        GIMP Palette
        Name: Test-Garnliste
        255 0 0\tRot
        0 255 0\tGrün
        """
        try contents.write(to: directory.appendingPathComponent("test.gpl"), atomically: true, encoding: .utf8)
        // Nicht-.gpl-Dateien im selben Verzeichnis müssen ignoriert werden.
        try "not a palette".write(to: directory.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        return directory
    }

    @Test func importsVendoredGPLFilesAndBasicColorsPaletteAsBuiltIn() throws {
        let context = try makeInMemoryContext()
        let directory = try makeSampleGPLDirectory()
        let bootstrapper = BuiltInThreadPaletteBootstrapper(paletteDirectory: directory)

        bootstrapper.bootstrapIfNeeded(context: context)

        let palettes = try context.fetch(FetchDescriptor<ThreadPalette>())
        #expect(palettes.allSatisfy { $0.isBuiltIn })
        #expect(palettes.contains { $0.name == "Test-Garnliste" })
        #expect(palettes.contains { $0.name == "Grundfarben" })

        let imported = try #require(palettes.first { $0.name == "Test-Garnliste" })
        #expect(imported.colors.count == 2)

        let basics = try #require(palettes.first { $0.name == "Grundfarben" })
        #expect(!basics.colors.isEmpty)
        #expect(basics.colors.allSatisfy { $0.palette === basics })
    }

    @Test func doesNothingIfBuiltInPalettesAlreadyExist() throws {
        let context = try makeInMemoryContext()
        let existing = ThreadPalette(name: "Bereits vorhanden", isBuiltIn: true)
        context.insert(existing)

        let bootstrapper = BuiltInThreadPaletteBootstrapper(paletteDirectory: try makeSampleGPLDirectory())
        bootstrapper.bootstrapIfNeeded(context: context)

        let palettes = try context.fetch(FetchDescriptor<ThreadPalette>())
        #expect(palettes.count == 1) // kein zusätzlicher Import, keine Duplikate.
        #expect(palettes.first?.name == "Bereits vorhanden")
    }

    @Test func userImportedNonBuiltInPalettesDoNotPreventBootstrap() throws {
        let context = try makeInMemoryContext()
        let userPalette = ThreadPalette(name: "Eigene Liste", isBuiltIn: false)
        context.insert(userPalette)

        let bootstrapper = BuiltInThreadPaletteBootstrapper(paletteDirectory: try makeSampleGPLDirectory())
        bootstrapper.bootstrapIfNeeded(context: context)

        let palettes = try context.fetch(FetchDescriptor<ThreadPalette>())
        #expect(palettes.contains { $0.name == "Grundfarben" })
        #expect(palettes.contains { $0.name == "Eigene Liste" })
    }

    @Test func missingPaletteDirectoryImportsOnlyBasicColors() throws {
        let context = try makeInMemoryContext()
        let bootstrapper = BuiltInThreadPaletteBootstrapper(paletteDirectory: nil)

        bootstrapper.bootstrapIfNeeded(context: context)

        let palettes = try context.fetch(FetchDescriptor<ThreadPalette>())
        #expect(palettes.map(\.name) == ["Grundfarben"])
    }
}
