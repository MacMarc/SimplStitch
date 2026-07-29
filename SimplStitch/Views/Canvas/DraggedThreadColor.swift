//
//  DraggedThreadColor.swift
//  SimplStitch
//
//  Phase 8e: Drag-Payload fürs Ziehen einer Garnfarbe aus dem Garnlisten-Panel
//  auf ein Canvas-Objekt. Bewusst reine Werte (kein `ThreadColor`-Objektbezug)
//  — der Drop-Handler in CanvasView erzeugt daraus ein neues, unabhängiges
//  `ThreadColor` fürs Zielobjekt, statt eine SwiftData-Relationship über den
//  Drag-Vorgang hinweg aufzulösen (bräuchte einen ModelContext am Drop-Ort).
//  `.json` als Content-Type reicht für rein appinternen Transfer, ohne einen
//  eigenen UTType deklarieren zu müssen (anders als `.stitchDesign`, das auch
//  für Finder/Launch Services sichtbar sein muss).
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct DraggedThreadColor: Codable, Transferable {
    var name: String
    var red: Int
    var green: Int
    var blue: Int
    var catalogNumber: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
