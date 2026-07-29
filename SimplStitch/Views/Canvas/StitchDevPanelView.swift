//
//  StitchDevPanelView.swift
//  SimplStitch
//
//  Phase 6e: minimaler Dev-Bedienbereich, um Sticheinstellungen am selektierten
//  Objekt zu setzen und die Live-Stichvorschau (CanvasStore.refreshStitchPreview)
//  zu demonstrieren — provisorisch wie der Werkzeug-Picker/Ebenen-Toggle in
//  ContentView, bis Phase 8 einen echten Settings-Inspector bringt. Bewusst
//  ohne Unterlage-Auswahl (nicht nötig, um den Phase-6-Checkpoint "Form →
//  Stichvorschau sichtbar" zu zeigen) — bleibt Aufgabe des künftigen
//  Inspectors.
//

import SwiftUI

struct StitchDevPanelView: View {
    let object: DesignObject
    let store: CanvasStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("stitch.dev.panel.title")
                .font(.headline)

            Picker("stitch.dev.type.label", selection: stitchTypeBinding) {
                Text("stitch.dev.type.none").tag(StitchType?.none)
                ForEach(StitchType.allCases, id: \.self) { type in
                    Text(displayName(for: type)).tag(StitchType?.some(type))
                }
            }

            if let settings = object.stitchSettings {
                LabeledContent("stitch.dev.density.label") {
                    Slider(value: densityBinding(settings), in: 0.1...2.0)
                }
                if settings.stitchType == .tatami {
                    LabeledContent("stitch.dev.angle.label") {
                        Slider(value: angleBinding(settings), in: 0...180)
                    }
                }
            }
        }
        .padding(8)
    }

    private func displayName(for type: StitchType) -> String {
        switch type {
        case .tatami: return String(localized: "stitch.dev.type.tatami")
        case .straight: return String(localized: "stitch.dev.type.straight")
        case .satin: return String(localized: "stitch.dev.type.satin")
        }
    }

    private var stitchTypeBinding: Binding<StitchType?> {
        Binding(
            get: { object.stitchSettings?.stitchType },
            set: { newType in
                if let newType {
                    if let settings = object.stitchSettings {
                        settings.stitchType = newType
                    } else {
                        let settings = StitchSettings(stitchType: newType)
                        settings.designObject = object
                        object.stitchSettings = settings
                    }
                } else {
                    object.stitchSettings = nil
                }
                store.refreshStitchPreview()
            }
        )
    }

    private func densityBinding(_ settings: StitchSettings) -> Binding<Double> {
        Binding(
            get: { settings.density },
            set: { settings.density = $0; store.refreshStitchPreview() }
        )
    }

    private func angleBinding(_ settings: StitchSettings) -> Binding<Double> {
        Binding(
            get: { settings.angleDegrees },
            set: { settings.angleDegrees = $0; store.refreshStitchPreview() }
        )
    }
}
