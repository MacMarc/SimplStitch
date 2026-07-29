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

    // Phase 7: generischer Multi-Format-Export mit Garnfarben, Formatwahl über die
    // Dateiendung (write_embroidery dispatcht via pyembroidery.write, siehe bridge.py).
    //
    // Empirischer Befund: exaktes RGB-Roundtrip gilt nicht für alle Formate — VP3 speichert
    // die exakte Farbe, PES/JEF runden dagegen auf die nächste Farbe der Marken-eigenen
    // Fadenkarte (z.B. 255,0,0 → 237,23,31 "Red" bei PES), und EXP/DST kennen gar keine
    // Farbinformation im Format (threadlist bleibt beim Zurücklesen leer). Dieser Test nutzt
    // daher VP3, wo Roundtrip-Exaktheit tatsächlich zutrifft.
    @Test func writeEmbroideryRoundtripWithThreads() async throws {
        let bridge = PythonBridge()

        let stitches: [[Any]] = [
            [0, 0, 0],
            [10, 0, 0],
            [10, 0, 5], // COLOR_CHANGE
            [10, 10, 0],
            [0, 10, 0],
        ]
        let threads: [[String: Any]] = [
            ["red": 255, "green": 0, "blue": 0, "name": "Red"],
            ["red": 0, "green": 255, "blue": 0, "name": "Green"],
        ]

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vp3")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let writeResult = try await bridge.send(
            command: "write_embroidery",
            payload: ["stitches": stitches, "threads": threads, "outputPath": outputURL.path]
        )
        #expect((writeResult["colorCount"] as? Int) == 2)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        let readResult = try await bridge.send(command: "read_embroidery", payload: ["inputPath": outputURL.path])
        let readThreads = try #require(readResult["threads"] as? [[String: Any]])
        #expect(readThreads.count == 2)
        #expect(readThreads[0]["red"] as? Int == 255)
        #expect(readThreads[1]["green"] as? Int == 255)

        await bridge.stop()
    }

    @Test func writeEmbroideryUnsupportedExtensionThrows() async throws {
        let bridge = PythonBridge()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("vip")

        await #expect(throws: PythonBridgeError.self) {
            try await bridge.send(
                command: "write_embroidery",
                payload: ["stitches": [[0, 0, 0], [1, 1, 4]], "threads": [], "outputPath": outputURL.path]
            )
        }
        await bridge.stop()
    }
}
