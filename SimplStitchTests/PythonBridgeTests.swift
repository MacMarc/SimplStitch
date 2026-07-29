//
//  PythonBridgeTests.swift
//  SimplStitchTests
//
//  Roundtrip-Test für Phase 2: Swift → Python-Subprocess → VP3-Datei → zurücklesen.
//

import Testing
import Foundation
@testable import SimplStitch

struct PythonBridgeTests {

    @Test func ping() async throws {
        let bridge = PythonBridge()
        let result = try await bridge.send(command: "ping")
        #expect(result["pong"] as? Bool == true)
        await bridge.stop()
    }

    @Test func vp3Roundtrip() async throws {
        let bridge = PythonBridge()

        // Dummy-Stichkoordinaten (Quadrat). Commands gemäss pyembroidery: STITCH=0, END=4.
        let dummyStitches: [[Int]] = [
            [0, 0, 0],
            [10, 0, 0],
            [10, 10, 0],
            [0, 10, 0],
            [0, 0, 4],
        ]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vp3")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let writeResult = try await bridge.send(
            command: "write_vp3",
            payload: ["stitches": dummyStitches, "outputPath": outputURL.path]
        )
        #expect(writeResult["stitchCount"] as? Int == dummyStitches.count)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let readResult = try await bridge.send(
            command: "read_embroidery",
            payload: ["inputPath": outputURL.path]
        )
        let readStitches = try #require(readResult["stitches"] as? [[Int]])

        // VP3 kann beim Schreiben zusätzliche TRIM/STOP-Befehle einfügen —
        // wir vergleichen daher nur die reinen STITCH-Koordinaten (command == 0).
        let originalPoints = dummyStitches.filter { $0[2] == 0 }.map { ($0[0], $0[1]) }
        let readPoints = readStitches.filter { $0[2] == 0 }.map { ($0[0], $0[1]) }

        #expect(readPoints.elementsEqual(originalPoints, by: ==))

        await bridge.stop()
    }
}
