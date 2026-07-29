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
