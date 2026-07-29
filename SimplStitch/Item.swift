//
//  Item.swift
//  SimplStitch
//
//  Created by Marc Brechbühl on 29.07.2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
