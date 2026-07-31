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
import CoreGraphics

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

/// Issue #30: Ausrichtung des Randes relativ zur Pfadkontur — bislang lag der Rand immer
/// `centered` (hälftig nach innen/aussen, das native Verhalten von SwiftUI/CoreGraphics-`stroke`
/// UND von InkStitchs `stroke-width`). `inside`/`outside` versetzen die tatsächliche Stichgeometrie
/// (siehe `bridge.py`, `cmd_generate_stitches`/`_offset_node_geometry`) um die halbe Randdicke nach
/// innen bzw. aussen, statt nur die Canvas-Vorschau zu verschieben — Vorschau (`CanvasView`) und
/// echte Stickerei (`StitchGenerationService.generateBorderStitches`) nutzen dieselbe Randdicke,
/// bleiben also konsistent.
enum BorderAlignment: String, Codable, CaseIterable {
    case centered
    case inside
    case outside
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
    var borderAlignment: BorderAlignment = BorderAlignment.centered
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

extension DesignObject {
    /// Bringt den unrotierten/unverzerrten `designSpacePath()` (siehe `DesignObjectPath.swift`) auf
    /// die sichtbare Ausrichtung: erst Scherung (`skewXDegrees`/`skewYDegrees`, Issue #9), dann
    /// Rotation (`rotationDegrees`), beides um die Objektmitte — dieselbe Konvention wie
    /// `CanvasStore`s Hit-Testing/Handle-Platzierung. Bewusst hier im Model statt in der View-Schicht
    /// (`DesignObjectPath.swift`, die diese Property bis Issue #30 selbst definierte), da
    /// `SVGDesignSerializer` (Services-Schicht, kein SwiftUI-Import) sie für die Stichgenerierung
    /// ebenfalls braucht (Issue #30, Punkt 1: ein gedrehtes/verzerrtes Objekt sah zwar optisch korrekt
    /// aus, InkStitch bekam aber weiterhin die ungedrehte Rohgeometrie, weil `data-ss-rotation` kein
    /// echtes SVG-`transform` ist).
    var visualTransform: CGAffineTransform {
        guard rotationDegrees != 0 || skewXDegrees != 0 || skewYDegrees != 0 else { return .identity }
        let center = CGPoint(x: positionX + width / 2, y: positionY + height / 2)
        var transform = CGAffineTransform(translationX: -center.x, y: -center.y)
        if skewXDegrees != 0 || skewYDegrees != 0 {
            let tanX = tan(skewXDegrees * .pi / 180)
            let tanY = tan(skewYDegrees * .pi / 180)
            transform = transform.concatenating(CGAffineTransform(a: 1, b: tanY, c: tanX, d: 1, tx: 0, ty: 0))
        }
        if rotationDegrees != 0 {
            transform = transform.concatenating(CGAffineTransform(rotationAngle: rotationDegrees * .pi / 180))
        }
        return transform.concatenating(CGAffineTransform(translationX: center.x, y: center.y))
    }
}
