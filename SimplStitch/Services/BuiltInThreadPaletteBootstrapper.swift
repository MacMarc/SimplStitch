//
//  BuiltInThreadPaletteBootstrapper.swift
//  SimplStitch
//
//  Issue #13: gestickt werden kann nur, was als Garn in einer Garnliste vorhanden ist — damit
//  die Palettenauswahl beim allerersten Start nicht leer ist, importiert dieser Bootstrapper
//  einmalig alle vendorten InkStitch-Garnlisten (`Vendor/inkstitch_palettes/`, siehe
//  VENDOR_PALETTES.md — von `Scripts/bundle_python.sh` nach `Contents/Resources/thread_palettes/`
//  kopiert) über den bestehenden `GPLPaletteImporter` (Phase 7), plus eine selbst erstellte
//  Grundfarben-Palette. Alle als `isBuiltIn = true` markiert (Feld existiert bereits seit Phase 3).
//
//  Läuft, bevor die erste View erscheint (`SimplStitchApp.sharedModelContainer`) — daher ein
//  eigener `ModelContext(container)` statt `container.mainContext` (der ist `@MainActor`-isoliert,
//  zu diesem Zeitpunkt ist noch nicht sichergestellt, dass wir auf dem Main Actor laufen).
//

import Foundation
import SwiftData

protocol BuiltInThreadPaletteBootstrapping {
    func bootstrapIfNeeded(context: ModelContext)
}

final class BuiltInThreadPaletteBootstrapper: BuiltInThreadPaletteBootstrapping {
    private let importer: GPLPaletteImporting
    private let paletteDirectory: URL?

    /// `paletteDirectory` statt eines `Bundle`-Parameters — direkt auf ein beliebiges Verzeichnis
    /// zeigbar (Tests legen dafür eigene Wegwerf-`.gpl`-Dateien in ein Temp-Verzeichnis), ohne eine
    /// künstliche `Bundle`-Struktur mit Info.plist bauen zu müssen.
    init(
        importer: GPLPaletteImporting = GPLPaletteImporter(),
        paletteDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("thread_palettes")
    ) {
        self.importer = importer
        self.paletteDirectory = paletteDirectory
    }

    /// Kein Import, wenn bereits mindestens eine eingebaute Palette existiert — sonst würde jeder
    /// App-Start (bzw. jeder erneute Aufruf) Duplikate anlegen. Nutzer-importierte Paletten
    /// (`isBuiltIn == false`) zählen bewusst nicht mit, ein leeres Nutzer-Setup soll trotzdem die
    /// Standard-Paletten bekommen.
    func bootstrapIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ThreadPalette>(predicate: #Predicate { $0.isBuiltIn })
        let alreadyBootstrapped = (try? context.fetchCount(descriptor)).map { $0 > 0 } ?? false
        guard !alreadyBootstrapped else { return }

        for url in vendoredPaletteURLs() {
            guard let palette = try? importer.importPalette(at: url) else { continue }
            palette.isBuiltIn = true
            context.insert(palette)
        }
        context.insert(Self.makeBasicColorsPalette())

        try? context.save()
    }

    private func vendoredPaletteURLs() -> [URL] {
        guard let directory = paletteDirectory,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .filter { $0.pathExtension.lowercased() == "gpl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Einfache Grundfarben-Palette (macOS-Basisfarben) als Fallback, unabhängig von den
    /// vendorten Hersteller-Garnlisten — reines Swift statt einer manuell erstellten `.gpl`-Datei,
    /// da die Farbwerte ohnehin fest im Code stehen müssten.
    static func makeBasicColorsPalette() -> ThreadPalette {
        let palette = ThreadPalette(name: "Grundfarben", isBuiltIn: true)
        palette.colors = basicColors.map { name, red, green, blue in
            let color = ThreadColor(name: name, red: red, green: green, blue: blue)
            color.palette = palette
            return color
        }
        return palette
    }

    private static let basicColors: [(name: String, red: Int, green: Int, blue: Int)] = [
        ("Schwarz", 0, 0, 0),
        ("Weiss", 255, 255, 255),
        ("Grau", 128, 128, 128),
        ("Rot", 255, 0, 0),
        ("Dunkelrot", 139, 0, 0),
        ("Orange", 255, 165, 0),
        ("Gelb", 255, 255, 0),
        ("Grün", 0, 128, 0),
        ("Hellgrün", 144, 238, 144),
        ("Türkis", 0, 128, 128),
        ("Cyan", 0, 255, 255),
        ("Blau", 0, 0, 255),
        ("Hellblau", 173, 216, 230),
        ("Marineblau", 0, 0, 128),
        ("Lila", 128, 0, 128),
        ("Pink", 255, 192, 203),
        ("Braun", 139, 69, 19),
    ]
}
