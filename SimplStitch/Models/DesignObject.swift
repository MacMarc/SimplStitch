//
//  DesignObject.swift
//  SimplStitch
//
//  Repräsentiert jedes Canvas-Element (Form oder Text). Statt einer echten
//  Swift-Vererbungshierarchie nutzen wir eine einzige @Model-Klasse mit einem
//  `kind`-Discriminator — SwiftData-Relationships/@Query über Subklassen sind
//  in der Praxis noch fehleranfällig, ein flaches Modell ist robuster.
//

import Foundation
import SwiftData

enum DesignObjectKind: String, Codable, CaseIterable {
    case circle
    case rectangle
    case star
    case path
    /// Issue #18/#19: reine Kontur-Form (zwei Punkte, Start→Ende) — teilt sich Geometrie/Pfad-
    /// Maschinerie mit `.path` (dieselbe SVG-`<path>`-Repräsentation), hat aber per Definition nie
    /// eine Füllung (`hasFill = false`, `hasBorder = true`) und ein eigenes Werkzeug/Icon/Namen.
    case line
    case text
}

@Model
final class DesignObject {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var kind: DesignObjectKind = DesignObjectKind.rectangle
    var zIndex: Int = 0
    var isVisible: Bool = true
    var isLocked: Bool = false
    /// Objekte mit derselben (nicht-nil) `groupID` bilden eine Gruppe (Issue #16) — keine eigene
    /// Group-@Model-Klasse, um dem flachen `kind`-Discriminator-Ansatz dieser Klasse treu zu
    /// bleiben. Verschachtelte Gruppen (Gruppe einer Gruppe) sind bewusst nicht unterstützt: erneutes
    /// Gruppieren von bereits gruppierten Objekten löst sie aus ihrer alten Gruppe und weist die neue zu.
    var groupID: UUID?

    // Transform — dieselben Handles für alle Objekte (skalieren, drehen, verzerren, runden).
    var positionX: Double = 0
    var positionY: Double = 0
    var width: Double = 0
    var height: Double = 0
    var rotationDegrees: Double = 0
    var skewXDegrees: Double = 0
    var skewYDegrees: Double = 0
    var cornerRadius: Double = 0

    // Formspezifisch. `pathData` nutzt SVG-Pfad-Syntax, passend zum content.svg-Format (Phase 4).
    var pathData: String?
    var starPointCount: Int?

    // Textspezifisch — bleibt als editierbarer Text erhalten, keine Pfad-Konvertierung vor Export.
    var text: String?
    var fontName: String?
    var fontSize: Double?

    var fillColorHex: String = "#000000"

    @Relationship(deleteRule: .cascade, inverse: \StitchSettings.designObject)
    var stitchSettings: StitchSettings?

    var threadColor: ThreadColor?
    var project: StitchProject?

    // Rand/Kontur (Issue #18) — unabhängig von der Füllung: eine Form kann Füllung, Rand,
    // oder beides haben. `hasFill`/`hasBorder` bestimmen, was beim Export/in der Stichvorschau
    // tatsächlich gestickt wird; die zugehörigen `*StitchSettings` bleiben beim Deaktivieren
    // erhalten (kein Datenverlust beim Wieder-Einschalten).
    var hasFill: Bool = true
    var hasBorder: Bool = false
    var borderWidthMillimeters: Double = 0.3
    var borderColorHex: String?
    var borderThreadColor: ThreadColor?

    @Relationship(deleteRule: .cascade, inverse: \StitchSettings.borderOwner)
    var borderStitchSettings: StitchSettings?

    init(
        name: String,
        kind: DesignObjectKind,
        positionX: Double = 0,
        positionY: Double = 0,
        width: Double = 0,
        height: Double = 0
    ) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
    }
}
