//
//  Color+Hex.swift
//  SimplStitch
//
//  Phase 8d: Farbe-Sektion im Objekt-Inspector braucht einen `ColorPicker`
//  (SwiftUI `Color`), das Modell speichert aber `fillColorHex` (String, siehe
//  DesignObject) — dieselbe Hex-Konvention wie überall sonst in der App
//  (`CGColor.fromHex`, PreviewImageRenderer.swift). Diese Erweiterung schliesst
//  die Lücke in beide Richtungen, ohne die Hex-Parsing-Logik zu duplizieren.
//

import SwiftUI

extension Color {
    init?(hex: String) {
        guard let cgColor = CGColor.fromHex(hex) else { return nil }
        self.init(cgColor)
    }

    /// `#RRGGBB` — nutzt `cgColor` (direkt vom System aufgelöst), nicht die rohen SwiftUI-
    /// Farbkomponenten, die je nach Farbraum/Umgebung variieren könnten.
    var hexString: String {
        guard let components = cgColor?.components, components.count >= 3 else { return "#000000" }
        let red = Int((components[0] * 255).rounded())
        let green = Int((components[1] * 255).rounded())
        let blue = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
