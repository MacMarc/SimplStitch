//
//  FocusedValues+Canvas.swift
//  SimplStitch
//
//  Phase 8b: Die Menüleiste (`.commands` in SimplStitchApp) wird auf Scene-
//  Ebene deklariert, hat also keinen direkten Zugriff auf den `canvasStore`,
//  der pro Fenster/Dokument in ContentView lebt. `FocusedValues` ist der von
//  Apple vorgesehene Weg dafür: ContentView published seinen Zustand über
//  `.focusedSceneValue(...)`, die Commands lesen ihn über `@FocusedValue`.
//

import SwiftUI

private struct CanvasStoreFocusedValueKey: FocusedValueKey {
    typealias Value = CanvasStore
}

private struct ExportDialogPresentedFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ImportDialogPresentedFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct InspectorPresentedFocusedValueKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

/// "Ganze Seite einpassen" braucht die aktuelle Viewport-Grösse (`GeometryReader`), die nur
/// `CanvasView` kennt — `CanvasStore.zoomToFit(viewportSize:)` selbst nimmt keine Geometrie
/// entgegen, die man ohne View-Kontext ermitteln könnte.
private struct ZoomToFitActionFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var canvasStore: CanvasStore? {
        get { self[CanvasStoreFocusedValueKey.self] }
        set { self[CanvasStoreFocusedValueKey.self] = newValue }
    }

    var isExportDialogPresented: Binding<Bool>? {
        get { self[ExportDialogPresentedFocusedValueKey.self] }
        set { self[ExportDialogPresentedFocusedValueKey.self] = newValue }
    }

    var isImportDialogPresented: Binding<Bool>? {
        get { self[ImportDialogPresentedFocusedValueKey.self] }
        set { self[ImportDialogPresentedFocusedValueKey.self] = newValue }
    }

    var isInspectorPresented: Binding<Bool>? {
        get { self[InspectorPresentedFocusedValueKey.self] }
        set { self[InspectorPresentedFocusedValueKey.self] = newValue }
    }

    var zoomToFitAction: (() -> Void)? {
        get { self[ZoomToFitActionFocusedValueKey.self] }
        set { self[ZoomToFitActionFocusedValueKey.self] = newValue }
    }
}
