//
//  StitchProject.swift
//  SimplStitch
//
//  Wrapper für ein `.stitchdesign` Document Package. Die eigentliche
//  Quelle der Wahrheit für den Inhalt ist content.svg (Phase 4); `objects`
//  ist der in SwiftData gehaltene Arbeitsstand, aus dem SVG geschrieben
//  bzw. mit dem SVG befüllt wird.
//
//  fileBookmarkData statt einer reinen URL, weil ENABLE_USER_SELECTED_FILES
//  gesetzt ist (App Sandbox) — Security-Scoped-Bookmarks überleben Neustarts
//  zuverlässiger als gespeicherte Pfade.
//

import Foundation
import SwiftData

@Model
final class StitchProject {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var fileBookmarkData: Data?
    var lastKnownPath: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var lastOpenedAt: Date?
    var canvasWidthMillimeters: Double = 100
    var canvasHeightMillimeters: Double = 100

    /// Dateiname (nicht Pfad) des Hintergrundbilds unter assets/ im Document Package, falls gesetzt.
    var backgroundImageFileName: String?

    @Relationship(deleteRule: .cascade, inverse: \DesignObject.project)
    var objects: [DesignObject] = []

    init(
        name: String,
        lastKnownPath: String,
        canvasWidthMillimeters: Double = 100,
        canvasHeightMillimeters: Double = 100
    ) {
        self.id = UUID()
        self.name = name
        self.lastKnownPath = lastKnownPath
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.canvasWidthMillimeters = canvasWidthMillimeters
        self.canvasHeightMillimeters = canvasHeightMillimeters
    }
}
