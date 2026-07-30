//
//  HoopSize.swift
//  SimplStitch
//
//  Issue #22: Canvas-Grösse anpassbar auf gängige Stickrahmen-Grössen. Bewusst KEINE Hersteller ->
//  Maschine -> Stickrahmen-Kaskade (eine der im Issue vorgeschlagenen Optionen) — dafür bräuchte es
//  eine verlässliche Datenbank realer Maschinen-/Rahmen-Kombinationen pro Hersteller, die nicht ohne
//  Weiteres beschaffbar/verifizierbar ist. Stattdessen die im Issue selbst genannte Alternative:
//  eine kuratierte Liste allgemein gängiger Standardgrössen (`builtIn`, herstellerunabhängig) plus
//  eigene, in den Einstellungen verwaltbare Grössen (`CustomHoopSize`, appweit persistiert).
//
//  Vereinfachung (im Issue selbst als Vorsicht angemahnt): die Werte hier sind die üblicherweise
//  als "Stickfläche"/Nutzfläche kommunizierten Maße (die gängige Namenskonvention, z.B. "100x100"),
//  NICHT die physische Aussenkante des Rahmens — reale Maschinen können davon leicht abweichen.
//

import Foundation
import SwiftData

struct HoopSize: Identifiable, Hashable {
    var name: String
    var widthMillimeters: Double
    var heightMillimeters: Double

    var id: String { name }

    /// Gängige, herstellerunabhängige Stickrahmen-Standardgrössen (Nutzfläche). Zoll-Werte in den
    /// Namen sind die verbreitete Marktbezeichnung (z.B. "4×4″"), nicht auf Zehntel exakt zur
    /// mm-Spalte — beide Angaben dienen nur der Wiedererkennung, nicht als Präzisionsmass.
    static let builtIn: [HoopSize] = [
        HoopSize(name: "100 × 100 mm (4″ × 4″)", widthMillimeters: 100, heightMillimeters: 100),
        HoopSize(name: "130 × 180 mm (5″ × 7″)", widthMillimeters: 130, heightMillimeters: 180),
        HoopSize(name: "140 × 140 mm (5.5″ × 5.5″)", widthMillimeters: 140, heightMillimeters: 140),
        HoopSize(name: "160 × 260 mm (6″ × 10″)", widthMillimeters: 160, heightMillimeters: 260),
        HoopSize(name: "200 × 200 mm (8″ × 8″)", widthMillimeters: 200, heightMillimeters: 200),
        HoopSize(name: "200 × 300 mm (8″ × 12″)", widthMillimeters: 200, heightMillimeters: 300),
    ]
}

/// Eigene, vom Nutzer angelegte Stickrahmen-Grössen (Issue #22: "…in den App-Einstellungen noch
/// eigene hinzufügen zu können") — appweit persistiert wie `ThreadPalette`, nicht projektgebunden,
/// da dieselben eigenen Rahmen üblicherweise projektübergreifend genutzt werden.
@Model
final class CustomHoopSize {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var widthMillimeters: Double = 100
    var heightMillimeters: Double = 100

    init(name: String, widthMillimeters: Double, heightMillimeters: Double) {
        self.id = UUID()
        self.name = name
        self.widthMillimeters = widthMillimeters
        self.heightMillimeters = heightMillimeters
    }

    var asHoopSize: HoopSize {
        HoopSize(name: name, widthMillimeters: widthMillimeters, heightMillimeters: heightMillimeters)
    }
}
