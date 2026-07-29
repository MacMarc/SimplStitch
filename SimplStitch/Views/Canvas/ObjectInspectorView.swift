//
//  ObjectInspectorView.swift
//  SimplStitch
//
//  Phase 8d: der "echte" Settings-Inspector, den StitchDevPanelView (Phase 6e)
//  immer schon als provisorisch angekündigt hat — ersetzt es vollständig
//  (inkl. der dort noch fehlenden Unterlage-Auswahl). Drei Sektionen:
//  Objekt-Eigenschaften (Transform), Farbe, Sticheinstellungen.
//
//  Vereinfachung: Verzerren (Skew) hat trotz vorhandener Modellfelder
//  (skewXDegrees/skewYDegrees) bewusst kein Eingabefeld — es gibt weiterhin
//  keinen interaktiven Griff dafür und auch das Rendering wendet es nicht an
//  (Scope-Hinweis seit 5c), ein Zahlenfeld ohne sichtbare Wirkung wäre
//  irreführend.
//

import SwiftUI

struct ObjectInspectorView: View {
    let object: DesignObject
    let store: CanvasStore

    var body: some View {
        Form {
            Section("inspector.section.object") {
                TextField("inspector.object.name", text: nameBinding)

                LabeledContent("inspector.object.position") {
                    HStack {
                        TextField("X", value: positionXBinding, format: .number)
                            .labelsHidden()
                        TextField("Y", value: positionYBinding, format: .number)
                            .labelsHidden()
                    }
                }
                LabeledContent("inspector.object.size") {
                    HStack {
                        TextField("W", value: widthBinding, format: .number)
                            .labelsHidden()
                        TextField("H", value: heightBinding, format: .number)
                            .labelsHidden()
                    }
                }
                LabeledContent("inspector.object.rotation") {
                    Slider(value: rotationBinding, in: 0...360)
                }
                if object.kind == .rectangle {
                    LabeledContent("inspector.object.cornerRadius") {
                        Slider(value: cornerRadiusBinding, in: 0...maxCornerRadius)
                    }
                }
            }

            Section("inspector.section.color") {
                ColorPicker("inspector.color.fill", selection: colorBinding)
            }

            Section("inspector.section.stitch") {
                Picker("inspector.stitch.type", selection: stitchTypeBinding) {
                    Text("inspector.stitch.type.none").tag(StitchType?.none)
                    ForEach(StitchType.allCases, id: \.self) { type in
                        Text(displayName(for: type)).tag(StitchType?.some(type))
                    }
                }

                if let settings = object.stitchSettings {
                    LabeledContent("inspector.stitch.density") {
                        Slider(value: densityBinding(settings), in: 0.1...2.0)
                    }
                    if settings.stitchType == .tatami {
                        LabeledContent("inspector.stitch.angle") {
                            Slider(value: angleBinding(settings), in: 0...180)
                        }
                    }
                    Picker("inspector.stitch.underlay", selection: underlayBinding(settings)) {
                        ForEach(UnderlayType.allCases, id: \.self) { underlay in
                            Text(displayName(for: underlay)).tag(underlay)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Objekt-Eigenschaften

    private var nameBinding: Binding<String> {
        Binding(get: { object.name }, set: { object.name = $0 })
    }

    private var positionXBinding: Binding<Double> {
        Binding(get: { object.positionX }, set: { object.positionX = $0; store.refreshStitchPreview() })
    }

    private var positionYBinding: Binding<Double> {
        Binding(get: { object.positionY }, set: { object.positionY = $0; store.refreshStitchPreview() })
    }

    private var widthBinding: Binding<Double> {
        Binding(get: { object.width }, set: { object.width = max($0, CanvasStore.minimumShapeSize); store.refreshStitchPreview() })
    }

    private var heightBinding: Binding<Double> {
        Binding(get: { object.height }, set: { object.height = max($0, CanvasStore.minimumShapeSize); store.refreshStitchPreview() })
    }

    private var rotationBinding: Binding<Double> {
        Binding(get: { object.rotationDegrees }, set: { object.rotationDegrees = $0; store.refreshStitchPreview() })
    }

    private var maxCornerRadius: Double {
        min(object.width, object.height) / 2
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(get: { object.cornerRadius }, set: { object.cornerRadius = min(max($0, 0), maxCornerRadius) })
    }

    // MARK: Farbe

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: object.fillColorHex) ?? .black },
            set: { object.fillColorHex = $0.hexString }
        )
    }

    // MARK: Sticheinstellungen

    private func displayName(for type: StitchType) -> String {
        switch type {
        case .tatami: return String(localized: "inspector.stitch.type.tatami")
        case .straight: return String(localized: "inspector.stitch.type.straight")
        case .satin: return String(localized: "inspector.stitch.type.satin")
        }
    }

    private func displayName(for underlay: UnderlayType) -> String {
        switch underlay {
        case .none: return String(localized: "inspector.underlay.none")
        case .centerWalk: return String(localized: "inspector.underlay.centerWalk")
        case .edgeWalk: return String(localized: "inspector.underlay.edgeWalk")
        case .zigzagNet: return String(localized: "inspector.underlay.zigzagNet")
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

    private func underlayBinding(_ settings: StitchSettings) -> Binding<UnderlayType> {
        Binding(
            get: { settings.underlayType },
            set: { settings.underlayType = $0; store.refreshStitchPreview() }
        )
    }
}
