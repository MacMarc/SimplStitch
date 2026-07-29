//
//  Color+Hex.swift
//  SimplStitch
//
//  `Color(hex:)` fürs read-only Farb-Swatch im Objekt-Inspektor (`fillColorHex`, siehe
//  DesignObject) — dieselbe Hex-Konvention wie überall sonst in der App (`CGColor.fromHex`,
//  PreviewImageRenderer.swift). Keine Rückrichtung (`Color` → Hex) mehr: die ursprüngliche
//  `hexString`-Extension wurde mit Issue #13 entfernt, zusammen mit dem freien `ColorPicker`, den
//  sie versorgt hat — Füllfarben kommen jetzt ausschliesslich aus Garnlisten-`ThreadColor`s
//  (`CanvasStore.assignColor`, direkt aus RGB-Ints), nie mehr aus einer SwiftUI-`Color`.
//

import SwiftUI

extension Color {
    init?(hex: String) {
        guard let cgColor = CGColor.fromHex(hex) else { return nil }
        self.init(cgColor)
    }
}
