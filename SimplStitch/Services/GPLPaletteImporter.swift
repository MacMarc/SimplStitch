//
//  GPLPaletteImporter.swift
//  SimplStitch
//
//  Parser für `.gpl` (GIMP Palette) — Garnlisten-Import ohne Python-Bridge,
//  reines Swift. Format: "GIMP Palette"-Kopfzeile, optionale "Name:"/
//  "Columns:"-Zeilen, "#"-Kommentare, danach pro Zeile "R G B Name" mit
//  beliebiger Whitespace-Trennung (kein garantiertes Tab-Trennzeichen).
//

import Foundation

enum GPLPaletteImportError: Error, LocalizedError {
    case invalidHeader
    case emptyPalette

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return String(localized: "gpl.error.invalidHeader")
        case .emptyPalette:
            return String(localized: "gpl.error.emptyPalette")
        }
    }
}

protocol GPLPaletteImporting {
    func importPalette(at url: URL) throws -> ThreadPalette
    func importPalette(contents: String, sourceFileName: String?) throws -> ThreadPalette
}

final class GPLPaletteImporter: GPLPaletteImporting {

    func importPalette(at url: URL) throws -> ThreadPalette {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try importPalette(contents: contents, sourceFileName: url.lastPathComponent)
    }

    func importPalette(contents: String, sourceFileName: String? = nil) throws -> ThreadPalette {
        var lines = contents.components(separatedBy: .newlines)
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "GIMP Palette" else {
            throw GPLPaletteImportError.invalidHeader
        }
        lines.removeFirst()

        var paletteName = sourceFileName.map { ($0 as NSString).deletingPathExtension } ?? String(localized: "gpl.defaultName")
        var colors: [ThreadColor] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("Name:") {
                paletteName = line.dropFirst("Name:".count).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line.hasPrefix("Columns:") { continue }

            guard let color = parseColorLine(line) else { continue }
            colors.append(color)
        }

        guard !colors.isEmpty else {
            throw GPLPaletteImportError.emptyPalette
        }

        let palette = ThreadPalette(name: paletteName, isBuiltIn: false, sourceFileName: sourceFileName)
        palette.colors = colors
        for color in colors {
            color.palette = palette
        }
        return palette
    }

    private func parseColorLine(_ line: String) -> ThreadColor? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard tokens.count >= 3,
              let red = Int(tokens[0]), let green = Int(tokens[1]), let blue = Int(tokens[2])
        else {
            return nil
        }
        let name = tokens.count > 3 ? tokens[3...].joined(separator: " ") : ""
        return ThreadColor(name: name, red: red, green: green, blue: blue)
    }
}
