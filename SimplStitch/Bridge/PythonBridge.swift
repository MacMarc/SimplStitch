//
//  PythonBridge.swift
//  SimplStitch
//
//  Startet die gebündelte Python-Runtime (Contents/Resources/python) als
//  Subprocess und kommuniziert mit bridge.py über zeilenweises JSON auf
//  stdin/stdout. Ein Request pro Zeile, eine Response pro Zeile.
//

import Foundation

enum PythonBridgeError: Error, LocalizedError {
    case runtimeNotBundled(URL)
    case processTerminated(status: Int32, stderr: String)
    case invalidResponse(String)
    case bridgeError(String)

    var errorDescription: String? {
        switch self {
        case .runtimeNotBundled(let url):
            return "Python-Runtime nicht gefunden unter \(url.path). Wurde Scripts/bundle_python.sh ausgeführt?"
        case .processTerminated(let status, let stderr):
            return "Der Python-Subprocess wurde beendet (Status \(status)).\(stderr.isEmpty ? "" : " stderr: \(stderr)")"
        case .invalidResponse(let raw):
            return "Ungültige Antwort von bridge.py: \(raw)"
        case .bridgeError(let message):
            return message
        }
    }
}

/// Erlaubt Services (z.B. StitchGenerationService), gegen einen Test-Double statt den echten
/// Python-Subprocess zu testen — PythonBridge selbst ist die einzige reale Implementierung.
protocol PythonBridging {
    @discardableResult
    func send(command: String, payload: [String: Any]) async throws -> [String: Any]
}

actor PythonBridge: PythonBridging {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var stdoutBuffer = Data()

    private let pythonExecutableURL: URL
    private let bridgeScriptURL: URL

    init(
        // bridge.py und requirements.txt liegen als lose Xcode-Resourcen direkt
        // unter Contents/Resources/ (kein "Bridge/"-Unterordner in der App-Bundle).
        pythonExecutableURL: URL = Bundle.main.resourceURL!.appendingPathComponent("python/bin/python3"),
        bridgeScriptURL: URL = Bundle.main.resourceURL!.appendingPathComponent("bridge.py")
    ) {
        self.pythonExecutableURL = pythonExecutableURL
        self.bridgeScriptURL = bridgeScriptURL
    }

    /// Startet den Python-Subprocess, falls er noch nicht läuft.
    func start() async throws {
        guard process == nil else { return }

        guard FileManager.default.isExecutableFile(atPath: pythonExecutableURL.path) else {
            throw PythonBridgeError.runtimeNotBundled(pythonExecutableURL)
        }

        let process = Process()
        process.executableURL = pythonExecutableURL
        process.arguments = [bridgeScriptURL.path]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
    }

    /// Beendet den Python-Subprocess.
    func stop() async {
        stdinHandle?.closeFile()
        process?.terminate()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        stdoutBuffer.removeAll()
    }

    /// Sendet einen Befehl an bridge.py und wartet auf die zugehörige Antwort.
    @discardableResult
    func send(command: String, payload: [String: Any] = [:]) async throws -> [String: Any] {
        if process == nil {
            try await start()
        }
        guard let stdinHandle, let stdoutHandle else {
            throw terminationError()
        }

        let request: [String: Any] = ["command": command, "payload": payload]
        var requestData = try JSONSerialization.data(withJSONObject: request)
        requestData.append(0x0A) // Zeilenumbruch als Nachrichtengrenze
        try stdinHandle.write(contentsOf: requestData)

        let line = try readLine(from: stdoutHandle)
        guard
            let responseObject = try JSONSerialization.jsonObject(with: line) as? [String: Any],
            let ok = responseObject["ok"] as? Bool
        else {
            throw PythonBridgeError.invalidResponse(String(data: line, encoding: .utf8) ?? "<binär>")
        }

        if ok {
            return responseObject["result"] as? [String: Any] ?? [:]
        } else {
            throw PythonBridgeError.bridgeError(responseObject["error"] as? String ?? "Unbekannter Bridge-Fehler")
        }
    }

    /// Liest so lange Daten von `handle`, bis ein vollständiger Zeilenumbruch
    /// im internen Puffer steht, und gibt genau diese Zeile (ohne \n) zurück.
    private func readLine(from handle: FileHandle) throws -> Data {
        while true {
            if let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = stdoutBuffer[stdoutBuffer.startIndex..<newlineIndex]
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newlineIndex)
                return Data(line)
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                throw terminationError()
            }
            stdoutBuffer.append(chunk)
        }
    }

    /// Baut eine aussagekräftige Fehlermeldung, wenn der Subprocess unerwartet
    /// beendet wurde: liest verbleibendes stderr und den Exit-Status aus.
    private func terminationError() -> PythonBridgeError {
        let stderrData = stderrHandle?.readDataToEndOfFile() ?? Data()
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        let status = process?.terminationStatus ?? -1
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        return .processTerminated(status: status, stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
