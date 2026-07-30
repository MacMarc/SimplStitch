//
//  FileImportServiceTests.swift
//  SimplStitchTests
//
//  Phase 7: Parsing der read_embroidery-Antwort gegen einen gestubbten
//  PythonBridging-Double, die Farbblock→DesignObject-Rekonstruktion, und ein
//  echter Roundtrip (write_embroidery → read_embroidery) gegen die reale Bridge.
//

import Testing
import Foundation
@testable import SimplStitch

private actor StubBridge: PythonBridging {
    var stubbedResult: [String: Any] = [:]

    func send(command: String, payload: [String: Any]) async throws -> [String: Any] {
        stubbedResult
    }

    func updateStubbedResult(_ result: [String: Any]) {
        stubbedResult = result
    }
}

struct FileImportServiceTests {

    @Test func parsesStitchesAndThreadsFromBridgeResult() async throws {
        let stub = StubBridge()
        await stub.updateStubbedResult([
            "stitches": [[0.0, 0.0, 0], [1.0, 1.0, 0]],
            "threads": [["red": 10, "green": 20, "blue": 30, "name": "Blau", "catalogNumber": "B-1"]],
        ])
        let service = FileImportService(bridge: stub)

        let pattern = try await service.importEmbroideryFile(at: URL(fileURLWithPath: "/tmp/irrelevant.dst"))

        #expect(pattern.stitches == [StitchPoint(x: 0, y: 0, command: .stitch), StitchPoint(x: 1, y: 1, command: .stitch)])
        #expect(pattern.threads == [ImportedThread(red: 10, green: 20, blue: 30, name: "Blau", catalogNumber: "B-1")])
    }

    @Test func designObjectsSplitsIntoOneObjectPerColorBlock() {
        let service = FileImportService(bridge: StubBridge())

        let pattern = ImportedEmbroideryPattern(
            stitches: [
                StitchPoint(x: 0, y: 0, command: .stitch),
                StitchPoint(x: 10, y: 0, command: .stitch),
                StitchPoint(x: 10, y: 0, command: .colorChange),
                StitchPoint(x: 10, y: 10, command: .stitch),
                StitchPoint(x: 0, y: 10, command: .stitch),
            ],
            threads: [
                ImportedThread(red: 255, green: 0, blue: 0, name: "Rot", catalogNumber: nil),
                ImportedThread(red: 0, green: 255, blue: 0, name: "Grün", catalogNumber: nil),
            ]
        )

        let objects = service.designObjects(from: pattern)

        #expect(objects.count == 2)
        #expect(objects[0].kind == .path)
        #expect(objects[0].fillColorHex == "#FF0000")
        #expect(objects[0].name == "Rot")
        #expect(objects[0].positionX == 0)
        #expect(objects[0].width == 10)
        #expect(objects[0].stitchSettings?.stitchType == .straight)

        #expect(objects[1].fillColorHex == "#00FF00")
        #expect(objects[1].name == "Grün")
        #expect(objects[1].zIndex == 1)
    }

    @Test func designObjectsStartsNewSubpathAfterJump() throws {
        let service = FileImportService(bridge: StubBridge())

        let pattern = ImportedEmbroideryPattern(
            stitches: [
                StitchPoint(x: 0, y: 0, command: .stitch),
                StitchPoint(x: 5, y: 0, command: .jump),
                StitchPoint(x: 5, y: 5, command: .stitch),
            ],
            threads: []
        )

        let objects = service.designObjects(from: pattern)

        let path = try #require(objects.first?.pathData)
        #expect(path.contains("M0.0000,0.0000"))
        #expect(path.contains("M5.0000,0.0000")) // Jump-Ziel startet ein neues Teilstück statt L
        #expect(path.contains("L5.0000,5.0000"))
    }

    // Issue #30 (Punkt 3): manche Stickdateien fügen nach einem TRIM keinen eigenen JUMP-Stich ein
    // (die neue Startposition steht direkt im nächsten STITCH). Ohne die pendingBreak-Behandlung
    // hätte hier eine durchgezogene Linie quer über den Fadenschnitt (0,0)→(50,50) gezeichnet.
    @Test func designObjectsStartsNewSubpathAfterTrimWithoutExplicitJump() throws {
        let service = FileImportService(bridge: StubBridge())

        let pattern = ImportedEmbroideryPattern(
            stitches: [
                StitchPoint(x: 0, y: 0, command: .stitch),
                StitchPoint(x: 1, y: 0, command: .trim),
                StitchPoint(x: 50, y: 50, command: .stitch),
                StitchPoint(x: 55, y: 50, command: .stitch),
            ],
            threads: []
        )

        let objects = service.designObjects(from: pattern)

        let path = try #require(objects.first?.pathData)
        #expect(path.contains("M50.0000,50.0000")) // Position nach TRIM startet neu statt zu verbinden
        #expect(!path.contains("L50.0000,50.0000"))
        #expect(path.contains("L55.0000,50.0000"))
    }

    @Test func designObjectsIgnoresEmptyStitchList() {
        let service = FileImportService(bridge: StubBridge())
        let objects = service.designObjects(from: ImportedEmbroideryPattern(stitches: [], threads: []))
        #expect(objects.isEmpty)
    }

    // Ende-zu-Ende: echte Bridge schreibt eine Stickdatei, FileImportService liest sie zurück.
    // Nutzt VP3 statt DST — DST kennt laut PythonBridgeTests.writeEmbroideryRoundtripWithThreads
    // gar keine Farbinformation im Format, threadlist bliebe beim Zurücklesen leer.
    //
    // Empirischer Befund: pyembroiderys VP3Reader wirft "read length must be non-negative or -1"
    // bei einem Farbblock mit nur einem einzigen Stich am Ende des Musters (degenerierter
    // Colorblock-Längenberechnung) — daher hier mindestens 2 Stiche je Block, wie es echte
    // Maschinendaten ohnehin haben.
    @Test func realBridgeRoundtripsWrittenPatternBackIntoDesignObjects() async throws {
        let bridge = PythonBridge()

        let writeResult = try await bridge.send(
            command: "write_embroidery",
            payload: [
                "stitches": [[0, 0, 0], [10, 0, 0], [10, 0, 5], [10, 10, 0], [0, 10, 0]],
                "threads": [
                    ["red": 200, "green": 0, "blue": 0, "name": "Rot"],
                    ["red": 0, "green": 200, "blue": 0, "name": "Grün"],
                ],
                "outputPath": FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("vp3").path,
            ]
        )
        let writtenPath = try #require(writeResult["writtenPath"] as? String)
        let writtenURL = URL(fileURLWithPath: writtenPath)
        defer { try? FileManager.default.removeItem(at: writtenURL) }

        let importService = FileImportService(bridge: bridge)
        let pattern = try await importService.importEmbroideryFile(at: writtenURL)
        #expect(!pattern.stitches.isEmpty)
        #expect(pattern.threads.count == 2)

        let objects = importService.designObjects(from: pattern)
        #expect(objects.count == 2)
        #expect(objects.allSatisfy { $0.kind == .path && $0.stitchSettings?.stitchType == .straight })

        await bridge.stop()
    }
}
