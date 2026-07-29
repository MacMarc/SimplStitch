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

    // Phase 6a/6b: echte InkStitch-Stichgenerierung (vendored, siehe Vendor/inkstitch_lib/)
    // über den generate_stitches-Befehl. Testet ein Rechteck mit Tatami-Füllung.
    @Test func generateStitchesTatamiFill() async throws {
        let bridge = PythonBridge()

        let objectSvg = """
        <rect x="10" y="10" width="30" height="20" \
        inkstitch:fill_method="tatami_fill" inkstitch:angle="45" inkstitch:row_spacing_mm="0.4" />
        """

        let result = try await bridge.send(
            command: "generate_stitches",
            payload: ["canvasWidthMm": 50, "canvasHeightMm": 50, "objectSvg": objectSvg, "stitchType": "tatami"]
        )
        let stitches = try #require(result["stitches"] as? [[Double]])

        #expect(!stitches.isEmpty)
        for stitch in stitches {
            #expect(stitch.count == 3)
            // Stiche sollten (mit etwas Toleranz für die Stichlänge über den Formrand hinaus)
            // innerhalb der 50x50mm-Zeichenfläche liegen.
            #expect(stitch[0] >= -5 && stitch[0] <= 55)
            #expect(stitch[1] >= -5 && stitch[1] <= 55)
        }

        await bridge.stop()
    }

    @Test func generateStitchesUnknownTypeThrows() async throws {
        let bridge = PythonBridge()
        await #expect(throws: PythonBridgeError.self) {
            try await bridge.send(
                command: "generate_stitches",
                payload: ["canvasWidthMm": 50, "canvasHeightMm": 50, "objectSvg": "<rect x=\"0\" y=\"0\" width=\"5\" height=\"5\" />", "stitchType": "unknown"]
            )
        }
        await bridge.stop()
    }
}
