//
//  ThreadPalette.swift
//  SimplStitch
//
//  Garnlisten-Bibliothek, importierbar aus .gpl-Dateien (GIMP Palette).
//

import Foundation
import SwiftData

@Model
final class ThreadPalette {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var isBuiltIn: Bool = false
    var sourceFileName: String?

    @Relationship(deleteRule: .cascade, inverse: \ThreadColor.palette)
    var colors: [ThreadColor] = []

    init(name: String, isBuiltIn: Bool = false, sourceFileName: String? = nil) {
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.sourceFileName = sourceFileName
    }
}
