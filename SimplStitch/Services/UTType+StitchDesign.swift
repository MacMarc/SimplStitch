//
//  UTType+StitchDesign.swift
//  SimplStitch
//
//  Eigener UTType fürs `.stitchdesign` Document Package (Phase 8a) — conforms
//  to `.package`, damit Finder den Ordner als Datei darstellt (Doppelklick
//  öffnet SimplStitch statt den Ordner im Finder-Fenster zu zeigen). Muss
//  identisch mit dem `UTExportedTypeDeclarations`-Eintrag in Info.plist sein.
//

import UniformTypeIdentifiers

extension UTType {
    static var stitchDesign: UTType {
        UTType(exportedAs: "de.daslama.SimplStitch.stitchdesign", conformingTo: .package)
    }
}
