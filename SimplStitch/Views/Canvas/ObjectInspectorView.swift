//
//  ObjectInspectorView.swift
//  SimplStitch
//
//  Phase 8d: der "echte" Settings-Inspector, den StitchDevPanelView (Phase 6e)
//  immer schon als provisorisch angekündigt hat — ersetzt es vollständig
//  (inkl. der dort noch fehlenden Unterlage-Auswahl).
//
//  Verzerren (Issue #9): skewXDegrees/skewYDegrees haben jetzt sowohl einen interaktiven Griff
//  (⌥+Drag auf einem Kanten-Griff, CanvasStore.beginSkewDrag) als auch Rendering
//  (DesignObjectPath.visualTransform) — die früher bewusst fehlenden Eingabefelder sind daher
//  nachgeholt (zwei Slider, analog zur Rotation).
//
//  Farbe (Issue #13): kein freier ColorPicker mehr — gestickt werden kann nur, was als Garn in
//  einer Garnliste vorhanden ist. Setzt wie das bestehende Drag&Drop (`CanvasStore.assignColor`,
//  Phase 8e) direkt aus RGB-Werten statt über SwiftUI `Color`/Hex zu gehen.
//
//  Farbe (Issue #20): ein einziger flacher Picker über die Farben der EINEN projektweiten
//  Standard-Garnliste (`CanvasStore.defaultThreadPaletteID`, im Projekt-Eigenschaften-Tab gewählt)
//  ohne eigenes @State — die Auswahl wird direkt aus `object.threadColor` abgeleitet.
//
//  Issue #23 (Überarbeitung): mehrere User-Feedback-Punkte nach Live-Test behoben:
//  - "Füllung" (Farbe + hasFill-Toggle + Sticheinstellungen) zu EINER Sektion zusammengelegt,
//    analog zur bereits selbsttragenden "Rand"-Sektion — vorher sass der hasFill-Toggle unter
//    "Sticheinstellungen", getrennt von der "Farbe"-Sektion darüber, was die Reihenfolge/Gruppierung
//    unlogisch machte. Nebeneffekt: die aktuelle-Farbe-Anzeige ist jetzt korrekt hinter `hasFill`
//    gated (vorher wurde die Füllfarbe immer angezeigt, auch wenn "Füllung" deaktiviert war).
//  - Grösse/Position zeigen jetzt Achsen-Labels (vorher `.labelsHidden()` versteckte "X"/"Y"/"B"/"H").
//  - Rotation/Verzerren/Dichte/Winkel haben jetzt zusätzlich zum Slider ein editierbares Zahlenfeld.
//  - Garnfarben-Picker zeigt echte farbige Kreise (SF-Symbol + `.foregroundStyle` wurde von macOS'
//    Menü-Picker-Rendering ignoriert — "nur weisse Kreise" — ein `Circle()`-Shape wird respektiert).
//  - Position/Grösse/Randdicke reagieren jetzt auf `AppSettings.preferredMeasurementUnit`
//    (mm/Zoll) — vorher hart auf "(mm)" verdrahtet, obwohl die Einstellung längst existierte.
//    Bewusst NICHT umgerechnet: Stichdichte/-winkel — technische InkStitch-Parameter, die
//    unabhängig von der Anzeige-Einheit immer in mm/Grad bleiben.
//  - Sektionsüberschriften grösser/fetter (`.headline` statt Form-Standard).
//

import AppKit
import SwiftData
import SwiftUI

struct ObjectInspectorView: View {
    let object: DesignObject
    let store: CanvasStore

    @Query(sort: \ThreadPalette.name) private var palettes: [ThreadPalette]
    @Query private var appSettingsList: [AppSettings]

    private var unit: MeasurementUnit {
        appSettingsList.first?.preferredMeasurementUnit ?? .millimeters
    }

    var body: some View {
        Form {
            Section {
                TextField("inspector.object.name", text: nameBinding)

                LabeledContent {
                    HStack {
                        AxisField("X", binding: positionXBinding)
                        AxisField("Y", binding: positionYBinding)
                    }
                } label: {
                    unitLabel("inspector.object.position")
                }
                LabeledContent {
                    HStack {
                        AxisField("inspector.object.size.width", binding: widthBinding)
                        AxisField("inspector.object.size.height", binding: heightBinding)
                    }
                } label: {
                    unitLabel("inspector.object.size")
                }
                degreeField("inspector.object.rotation", binding: rotationBinding, range: 0...360)
                degreeField("inspector.object.skewX", binding: skewXBinding, range: -CanvasStore.maxSkewDegrees...CanvasStore.maxSkewDegrees)
                degreeField("inspector.object.skewY", binding: skewYBinding, range: -CanvasStore.maxSkewDegrees...CanvasStore.maxSkewDegrees)
                if object.kind == .rectangle {
                    LabeledContent {
                        HStack {
                            Slider(value: cornerRadiusBinding, in: 0...max(unit.value(fromMillimeters: maxCornerRadius), 0.01))
                            numberField(cornerRadiusBinding)
                        }
                    } label: {
                        unitLabel("inspector.object.cornerRadius")
                    }
                }
                // Issue #29 (Punkt 9): Font-Picker nur bei Text-Objekten sichtbar — Backend
                // (Rendering, Persistenz, Glyphen-Stichgenerierung) liest object.fontName/fontSize
                // bereits überall, es fehlte nur diese Auswahl-UI.
                if object.kind == .text {
                    Picker("inspector.text.font", selection: fontNameBinding) {
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    LabeledContent {
                        HStack {
                            Slider(value: fontSizeBinding, in: max(unit.value(fromMillimeters: 2), 0.1)...unit.value(fromMillimeters: 100))
                            numberField(fontSizeBinding)
                        }
                    } label: {
                        unitLabel("inspector.text.fontSize")
                    }
                }
            } header: {
                SectionHeader("inspector.section.object")
            }

            // Issue #23: Füllung (Farbe + Sticheinstellungen) als eine Sektion, symmetrisch zur
            // "Rand"-Sektion unten — beide folgen jetzt demselben Aufbau (Toggle → Farbe →
            // Sticheinstellungen), statt Farbe/Füllung/Stich auf zwei getrennte, unzusammenhängend
            // wirkende Sektionen zu verteilen.
            Section {
                Toggle("inspector.fill.enabled", isOn: hasFillBinding)

                if object.hasFill {
                    currentColorRow(hex: object.fillColorHex, threadName: object.threadColor?.name)

                    if projectThreadColors.isEmpty {
                        Text("inspector.color.noProjectThreads")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("inspector.color.thread", selection: threadColorSelectionBinding) {
                            Text("inspector.color.pickPlaceholder").tag(UUID?.none)
                            ForEach(projectThreadColors) { color in
                                threadColorLabel(color).tag(Optional(color.id))
                            }
                        }
                    }

                    Picker("inspector.stitch.type", selection: stitchTypeBinding) {
                        Text("inspector.stitch.type.none").tag(StitchType?.none)
                        ForEach(StitchType.allCases, id: \.self) { type in
                            Text(displayName(for: type)).tag(StitchType?.some(type))
                        }
                    }

                    if let settings = object.stitchSettings {
                        degreeField("inspector.stitch.density", binding: densityBinding(settings), range: 0.1...2.0, suffix: "mm")
                        if settings.stitchType == .tatami {
                            degreeField("inspector.stitch.angle", binding: angleBinding(settings), range: 0...180)
                        }
                        Picker("inspector.stitch.underlay", selection: underlayBinding(settings)) {
                            ForEach(UnderlayType.allCases, id: \.self) { underlay in
                                Text(displayName(for: underlay)).tag(underlay)
                            }
                        }
                    }
                }
            } header: {
                SectionHeader("inspector.section.fill")
            }

            Section {
                Toggle("inspector.border.enabled", isOn: hasBorderBinding)

                if object.hasBorder {
                    LabeledContent {
                        HStack {
                            Slider(value: borderWidthBinding, in: 0.1...max(unit.value(fromMillimeters: 5), 0.2))
                            numberField(borderWidthBinding)
                        }
                    } label: {
                        unitLabel("inspector.border.width")
                    }

                    Picker("inspector.border.alignment", selection: borderAlignmentBinding) {
                        ForEach(BorderAlignment.allCases, id: \.self) { alignment in
                            Text(displayName(for: alignment)).tag(alignment)
                        }
                    }

                    currentColorRow(hex: object.borderColorHex ?? object.fillColorHex, threadName: object.borderThreadColor?.name)

                    if projectThreadColors.isEmpty {
                        Text("inspector.color.noProjectThreads")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else {
                        Picker("inspector.color.thread", selection: borderThreadColorSelectionBinding) {
                            Text("inspector.color.pickPlaceholder").tag(UUID?.none)
                            ForEach(projectThreadColors) { color in
                                threadColorLabel(color).tag(Optional(color.id))
                            }
                        }
                    }

                    Picker("inspector.stitch.type", selection: borderStitchTypeBinding) {
                        ForEach(StitchType.allCases, id: \.self) { type in
                            Text(displayName(for: type)).tag(type)
                        }
                    }
                    if let borderSettings = object.borderStitchSettings {
                        degreeField("inspector.stitch.density", binding: densityBinding(borderSettings), range: 0.1...2.0, suffix: "mm")
                        Picker("inspector.stitch.underlay", selection: underlayBinding(borderSettings)) {
                            ForEach(UnderlayType.allCases, id: \.self) { underlay in
                                Text(displayName(for: underlay)).tag(underlay)
                            }
                        }
                    }
                }
            } header: {
                SectionHeader("inspector.section.border")
            }
        }
        .inspectorForm()
    }

    // MARK: Gemeinsame Bausteine

    /// Sektions-/Feldtitel mit dynamisch angehängter Einheit (Issue #23: vorher war "(mm)" fest
    /// in den lokalisierten Strings verdrahtet, obwohl `AppSettings.preferredMeasurementUnit`
    /// längst existierte).
    private func unitLabel(_ key: LocalizedStringKey) -> some View {
        Text(key) + Text(" (\(unit.symbol))")
    }

    private func numberField(_ binding: Binding<Double>) -> some View {
        TextField("", value: binding, format: .number.precision(.fractionLength(0...2)))
            .labelsHidden()
            .frame(width: DesignSystem.numberFieldWidth)
    }

    /// Slider + editierbares Zahlenfeld nebeneinander (Issue #23: vorher nur Slider ohne
    /// sichtbaren/editierbaren Zahlenwert bei Rotation/Verzerren/Dichte/Winkel).
    private func degreeField(_ labelKey: LocalizedStringKey, binding: Binding<Double>, range: ClosedRange<Double>, suffix: String = "°") -> some View {
        LabeledContent {
            HStack {
                Slider(value: binding, in: range)
                numberField(binding)
                Text(suffix).font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Text(labelKey)
        }
    }

    @ViewBuilder
    private func currentColorRow(hex: String, threadName: String?) -> some View {
        LabeledContent("inspector.color.current") {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: hex) ?? .black)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(Color.secondary.opacity(0.3)))
                Text(threadName?.isEmpty == false ? threadName! : hex)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Objekt-Eigenschaften

    private var nameBinding: Binding<String> {
        Binding(get: { object.name }, set: { object.name = $0 })
    }

    private var positionXBinding: Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: object.positionX) },
            set: { object.positionX = unit.millimeters(from: $0); store.refreshStitchPreview() }
        )
    }

    private var positionYBinding: Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: object.positionY) },
            set: { object.positionY = unit.millimeters(from: $0); store.refreshStitchPreview() }
        )
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: object.width) },
            set: { object.width = max(unit.millimeters(from: $0), CanvasStore.minimumShapeSize); store.refreshStitchPreview() }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: object.height) },
            set: { object.height = max(unit.millimeters(from: $0), CanvasStore.minimumShapeSize); store.refreshStitchPreview() }
        )
    }

    private var rotationBinding: Binding<Double> {
        Binding(get: { object.rotationDegrees }, set: { object.rotationDegrees = $0; store.refreshStitchPreview() })
    }

    private var skewXBinding: Binding<Double> {
        Binding(get: { object.skewXDegrees }, set: { object.skewXDegrees = $0; store.refreshStitchPreview() })
    }

    private var skewYBinding: Binding<Double> {
        Binding(get: { object.skewYDegrees }, set: { object.skewYDegrees = $0; store.refreshStitchPreview() })
    }

    private var maxCornerRadius: Double {
        min(object.width, object.height) / 2
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: object.cornerRadius) },
            set: { object.cornerRadius = min(max(unit.millimeters(from: $0), 0), maxCornerRadius) }
        )
    }

    // MARK: Schrift (Issue #29, Punkt 9)

    /// Installierte Vektorfonts des Systems — dieselbe Quelle, die auch der native macOS-
    /// Schriftauswahl-Dialog nutzt. Sortiert für eine stabile, durchsuchbare Reihenfolge.
    private var fontFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.sorted()
    }

    private var fontNameBinding: Binding<String> {
        Binding(
            get: { object.fontName ?? "Helvetica" },
            set: { object.fontName = $0; store.refreshStitchPreview() }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: object.fontSize ?? CanvasStore.defaultTextFontSize) },
            set: { object.fontSize = max(unit.millimeters(from: $0), 1); store.refreshStitchPreview() }
        )
    }

    // MARK: Farbe

    /// Farben der EINEN projektweiten Standard-Garnliste (Issue #20, `CanvasStore.
    /// defaultThreadPaletteID`, im Projekt-Eigenschaften-Tab gewählt), nach Namen sortiert.
    private var projectThreadColors: [ThreadColor] {
        guard let paletteID = store.defaultThreadPaletteID,
              let palette = palettes.first(where: { $0.id == paletteID }) else {
            return []
        }
        return palette.colors.sorted { $0.name < $1.name }
    }

    private var threadColorSelectionBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let current = object.threadColor else { return nil }
                return projectThreadColors.first {
                    $0.red == current.red && $0.green == current.green && $0.blue == current.blue
                }?.id
            },
            set: { newID in
                guard let newID, let color = projectThreadColors.first(where: { $0.id == newID }) else { return }
                store.assignColor(
                    name: color.name,
                    red: color.red,
                    green: color.green,
                    blue: color.blue,
                    catalogNumber: color.catalogNumber,
                    to: object.id
                )
            }
        )
    }

    /// Issue #23: vorher `Label(_, systemImage: "circle.fill").foregroundStyle(farbe)` — macOS'
    /// Menü-Picker-Rendering ignoriert `.foregroundStyle` auf SF-Symbol-Icons innerhalb von
    /// Picker-Zeilen und zeigt stattdessen einheitlich weisse/unfärbige Kreise. Ein echtes
    /// `Circle()`-Shape als View wird korrekt eingefärbt dargestellt.
    private func threadColorLabel(_ color: ThreadColor) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255))
                .frame(width: 12, height: 12)
            Text(color.name.isEmpty ? "#\(color.red),\(color.green),\(color.blue)" : color.name)
        }
    }

    // MARK: Füllung/Rand (Issue #18)

    private var hasFillBinding: Binding<Bool> {
        Binding(
            get: { object.hasFill },
            set: { newValue in
                object.hasFill = newValue
                // Analog zu hasBorderBinding: Sticheinstellungen bleiben beim Deaktivieren erhalten;
                // beim ERSTEN Aktivieren ohne bestehende Einstellungen (Text-Objekte hatten bislang
                // nie welche, siehe CanvasStore.makeTextObject-Kommentar; ebenso importierte Objekte
                // ohne erkanntes inkstitch:*-Attribut) legen wir sinnvolle Defaults an, statt eine
                // stumme "Kein"-Stichtyp-Anzeige zurückzulassen.
                if newValue, object.stitchSettings == nil {
                    let stitchType: StitchType = object.kind == .text
                        ? .tatami
                        : StitchType.suggested(forShapeWidth: object.width, height: object.height)
                    let settings = StitchSettings(stitchType: stitchType, underlayType: UnderlayType.suggested(for: stitchType))
                    settings.designObject = object
                    object.stitchSettings = settings
                }
                store.refreshStitchPreview()
            }
        )
    }

    private var hasBorderBinding: Binding<Bool> {
        Binding(
            get: { object.hasBorder },
            set: { newValue in
                object.hasBorder = newValue
                // Randeinstellungen bleiben beim Deaktivieren erhalten (Datenverlust vermeiden) —
                // beim ERSTEN Aktivieren gibt es aber noch keine, die erzeugen wir hier vor.
                if newValue, object.borderStitchSettings == nil {
                    let settings = StitchSettings(stitchType: .straight, underlayType: UnderlayType.suggested(for: .straight))
                    settings.borderOwner = object
                    object.borderStitchSettings = settings
                }
                store.refreshStitchPreview()
            }
        )
    }

    private var borderWidthBinding: Binding<Double> {
        Binding(
            get: { unit.value(fromMillimeters: object.borderWidthMillimeters) },
            set: {
                object.borderWidthMillimeters = max(unit.millimeters(from: $0), 0.1)
                store.refreshStitchPreview()
            }
        )
    }

    /// Issue #30: Ausrichtung des Randes relativ zur Pfadkontur (zentriert/innen/aussen) —
    /// beeinflusst sowohl die Canvas-Vorschau (`CanvasView.drawObjects`) als auch die echte
    /// Stichgenerierung (`StitchGenerationService.generateBorderStitches` → `bridge.py`), daher
    /// wie `borderWidthBinding` mit `refreshStitchPreview()` nach jeder Änderung.
    private var borderAlignmentBinding: Binding<BorderAlignment> {
        Binding(
            get: { object.borderAlignment },
            set: { object.borderAlignment = $0; store.refreshStitchPreview() }
        )
    }

    private var borderThreadColorSelectionBinding: Binding<UUID?> {
        Binding(
            get: {
                guard let current = object.borderThreadColor else { return nil }
                return projectThreadColors.first {
                    $0.red == current.red && $0.green == current.green && $0.blue == current.blue
                }?.id
            },
            set: { newID in
                guard let newID, let color = projectThreadColors.first(where: { $0.id == newID }) else { return }
                store.assignBorderColor(
                    name: color.name,
                    red: color.red,
                    green: color.green,
                    blue: color.blue,
                    catalogNumber: color.catalogNumber,
                    to: object.id
                )
            }
        )
    }

    private var borderStitchTypeBinding: Binding<StitchType> {
        Binding(
            get: { object.borderStitchSettings?.stitchType ?? .straight },
            set: { newType in
                if let settings = object.borderStitchSettings {
                    settings.stitchType = newType
                } else {
                    let settings = StitchSettings(stitchType: newType)
                    settings.borderOwner = object
                    object.borderStitchSettings = settings
                }
                store.refreshStitchPreview()
            }
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

    private func displayName(for alignment: BorderAlignment) -> String {
        switch alignment {
        case .centered: return String(localized: "inspector.border.alignment.centered")
        case .inside: return String(localized: "inspector.border.alignment.inside")
        case .outside: return String(localized: "inspector.border.alignment.outside")
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
