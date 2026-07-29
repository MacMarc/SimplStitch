//
//  SimplStitchCommands.swift
//  SimplStitch
//
//  Phase 8b: die eigentliche Menüleiste. `DocumentGroup` liefert Ablage
//  (Neu/Öffnen/Zuletzt benutzt/Schliessen/Sichern/Sichern unter/Duplizieren/…)
//  und die Grundgerüste für Bearbeiten (Rückgängig/Wiederholen/Ausschneiden/
//  Kopieren/Einfügen/Alles auswählen) sowie Fenster/Hilfe bereits automatisch
//  mit — hier kommen nur die SimplStitch-eigenen Funktionen dazu, jeweils über
//  `CommandGroup(after:)` in eine bestehende Standardgruppe eingehängt oder als
//  eigenes `CommandMenu`. Zugriff auf den `CanvasStore` des aktiven Fensters
//  läuft über `@FocusedValue` (FocusedValues+Canvas.swift), da `.commands` auf
//  Scene-Ebene deklariert ist, nicht auf View-Ebene.
//
//  Scope-Hinweis: "Rückgängig/Wiederholen" bleibt das von DocumentGroup/
//  AppKit automatisch bereitgestellte Grundgerüst — es gibt noch keine echte
//  Undo-Registrierung für Canvas-Mutationen (Verschieben, Skalieren, Farbe
//  ändern, …). Das wäre ein eigenständiges, nicht-triviales Feature (jede
//  DesignObject-Mutation müsste eine UndoManager-Registrierung bekommen) und
//  ist bewusst nicht Teil von Phase 8b.
//

import SwiftUI

struct SimplStitchCommands: Commands {
    @FocusedValue(\.canvasStore) private var canvasStore
    @FocusedValue(\.isExportDialogPresented) private var isExportDialogPresented
    @FocusedValue(\.isInspectorPresented) private var isInspectorPresented
    @FocusedValue(\.zoomToFitAction) private var zoomToFitAction

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button {
                isExportDialogPresented?.wrappedValue = true
            } label: {
                Text("menu.file.export")
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(isExportDialogPresented == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button {
                canvasStore?.deleteSelectedObject()
            } label: {
                Text("menu.edit.delete")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(canvasStore?.selectedObject == nil)
        }

        CommandMenu("menu.tool.title") {
            ForEach(CanvasTool.allCases) { tool in
                Button {
                    canvasStore?.selectTool(tool)
                } label: {
                    Text(tool.displayName)
                }
                .disabled(canvasStore == nil)
            }
        }

        CommandMenu("menu.object.title") {
            Button {
                if let id = canvasStore?.selectedObjectID {
                    canvasStore?.moveObject(id, .toFront)
                }
            } label: {
                Text("layers.moveToFront")
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(canvasStore?.selectedObject == nil)

            Button {
                if let id = canvasStore?.selectedObjectID {
                    canvasStore?.moveObject(id, .forward)
                }
            } label: {
                Text("layers.moveForward")
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(canvasStore?.selectedObject == nil)

            Button {
                if let id = canvasStore?.selectedObjectID {
                    canvasStore?.moveObject(id, .backward)
                }
            } label: {
                Text("layers.moveBackward")
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(canvasStore?.selectedObject == nil)

            Button {
                if let id = canvasStore?.selectedObjectID {
                    canvasStore?.moveObject(id, .toBack)
                }
            } label: {
                Text("layers.moveToBack")
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(canvasStore?.selectedObject == nil)

            Divider()

            Button {
                if let id = canvasStore?.selectedObjectID {
                    canvasStore?.toggleVisibility(of: id)
                }
            } label: {
                Text(canvasStore?.selectedObject?.isVisible == false ? "layers.show" : "layers.hide")
            }
            .disabled(canvasStore?.selectedObject == nil)

            Button {
                if let id = canvasStore?.selectedObjectID {
                    canvasStore?.toggleLock(of: id)
                }
            } label: {
                Text(canvasStore?.selectedObject?.isLocked == true ? "layers.unlock" : "layers.lock")
            }
            .disabled(canvasStore?.selectedObject == nil)
        }

        CommandGroup(after: .toolbar) {
            Button {
                canvasStore?.zoom(by: 1.25)
            } label: {
                Text("menu.view.zoomIn")
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(canvasStore == nil)

            Button {
                canvasStore?.zoom(by: 0.8)
            } label: {
                Text("menu.view.zoomOut")
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(canvasStore == nil)

            Button {
                canvasStore?.setZoomScale(1)
            } label: {
                Text("menu.view.resetZoom")
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(canvasStore == nil)

            Button {
                zoomToFitAction?()
            } label: {
                Text("menu.view.zoomToFit")
            }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(zoomToFitAction == nil)

            Divider()

            Button {
                isInspectorPresented?.wrappedValue.toggle()
            } label: {
                Text("inspector.toggle")
            }
            .disabled(isInspectorPresented == nil)
        }
    }
}
