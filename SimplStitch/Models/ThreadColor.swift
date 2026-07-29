//
//  ThreadColor.swift
//  SimplStitch
//
//  Garnfarbe mit RGB + Herstellerinfo, gehört zu genau einer ThreadPalette.
//

import Foundation
import SwiftData

@Model
final class ThreadColor {
    var name: String = ""
    var red: Int = 0   // 0...255
    var green: Int = 0
    var blue: Int = 0
    var manufacturerName: String?
    var catalogNumber: String?

    var palette: ThreadPalette?

    init(
        name: String,
        red: Int,
        green: Int,
        blue: Int,
        manufacturerName: String? = nil,
        catalogNumber: String? = nil
    ) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
        self.manufacturerName = manufacturerName
        self.catalogNumber = catalogNumber
    }
}
