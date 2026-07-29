//
//  CanvasTool.swift
//  SimplStitch
//
//  Werkzeugauswahl für die Zeichenfläche: Auswahl-Werkzeug oder eines der
//  Formwerkzeuge, mit denen CanvasStore per Klick-Drag neue DesignObjects
//  erzeugt (siehe CanvasStore.beginDraft/updateDraft/commitDraft).
//

import Foundation

enum CanvasTool: String, CaseIterable, Identifiable {
    case select
    case rectangle
    case circle
    case star
    case path
    case text

    var id: String { rawValue }

    /// DesignObject-Art, die dieses Werkzeug per Klick-Drag erzeugt — nil beim Auswahl-Werkzeug.
    var shapeKind: DesignObjectKind? {
        switch self {
        case .select: return nil
        case .rectangle: return .rectangle
        case .circle: return .circle
        case .star: return .star
        case .path: return .path
        case .text: return .text
        }
    }

    var displayName: String {
        switch self {
        case .select: return String(localized: "canvas.tool.select")
        case .rectangle: return String(localized: "canvas.tool.rectangle")
        case .circle: return String(localized: "canvas.tool.circle")
        case .star: return String(localized: "canvas.tool.star")
        case .path: return String(localized: "canvas.tool.path")
        case .text: return String(localized: "canvas.tool.text")
        }
    }
}
