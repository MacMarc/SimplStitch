//
//  StitchPreviewStyle.swift
//  SimplStitch
//
//  Farben der Live-Stichvorschau passend zur Garnfarbe darunter. Vorher immer schwarz — auf
//  dunklen Garnen (Schwarz, Marineblau, Dunkelrot …) war die Stichreihenfolge kaum zu erkennen.
//  Jetzt: helle Linie auf dunklem Garn, dunkle auf hellem, jeweils mit einem schmalen Saum in
//  der Gegenfarbe, damit sie auch über Farbwechseln und dem Hintergrund lesbar bleibt.
//

import Foundation

nonisolated enum StitchPreviewStyle {
    /// Relative Helligkeit (sRGB-Gewichtung wie bei der Farbreduktion, 0…1). `nil` bei ungültigem Hex.
    static func luminance(ofHex hex: String) -> Double? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return 0.299 * red + 0.587 * green + 0.114 * blue
    }

    /// `true` → helle Stichlinie (auf dunklem Garn). Unbekannte Farbe → dunkle Linie wie bisher.
    static func usesLightStitches(onHex hex: String?) -> Bool {
        guard let hex, let luminance = luminance(ofHex: hex) else { return false }
        return luminance < 0.5
    }
}
