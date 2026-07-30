//
//  DesignSystem.swift
//  SimplStitch
//
//  Issue #26: zentrale Design-/Layout-Werte statt verstreuter Literale über mehrere View-Dateien
//  (Sektionsüberschriften, Formularstil, Zahlenfeld-Breiten, Auswahl-Farbe, Griff-Marker-Grösse,
//  Inspector-/Einstellungen-Spaltenbreiten, …). Neuer Code sollte gegen diese Tokens/Helfer
//  schreiben statt eigene Werte zu erfinden — siehe Analyse in Issue #26 für die konkret
//  gefundene Duplikation (ObjectInspectorView/ProjectInspectorView/GroupInspectorView/
//  MultiSelectionInspectorView/SettingsView/ExportDialogView).
//
//  Schritt 1 von Issue #26: nur das Fundament — bestehende Views werden erst in Schritt 6
//  (Zentralisierungs-Durchgang) auf diese Tokens umgestellt, um Bugfixes (Schritte 2-5) nicht
//  mit einem grossflächigen Refactor zu vermischen.
//

import SwiftUI

enum DesignSystem {
    // MARK: Abstände / Masse

    static let contentPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 8
    /// Einheitliche Zahlenfeld-Breite (ersetzt die bisher inkonsistenten 46/50/60pt über
    /// ObjectInspectorView/ProjectInspectorView/SettingsView).
    static let numberFieldWidth: CGFloat = 52
    static let inspectorColumnMinWidth: CGFloat = 240
    static let inspectorColumnIdealWidth: CGFloat = 280
    /// Feste Sidebar-Breite im Einstellungen-Fenster (Issue #26, Bug 3a) — bewusst nicht
    /// ausblendbar, siehe `SettingsView`.
    static let settingsSidebarWidth: CGFloat = 180
    /// Bildschirmgrösse der Canvas-Griff-Marker (Skalier-/Rotations-/Eckenradius-Griffe).
    static let handleMarkerSize: CGFloat = 7
    static let selectionCornerRadius: CGFloat = 8

    // MARK: Farben

    /// Sanft eingefärbte Auswahl-Fläche (z.B. aktives Werkzeug) statt einer harten Vollfarbe —
    /// näher am dezenten macOS-Standard-Selektionslook.
    static let selectionTint = Color.accentColor.opacity(0.15)
}

/// Sektionsüberschrift für Inspector-/Einstellungen-Formulare — einheitlich `.headline` statt
/// derselben `Text(key).font(.headline)`-Zeile, die bisher in vier verschiedenen Dateien
/// dupliziert war (ObjectInspectorView, ProjectInspectorView, GroupInspectorView,
/// MultiSelectionInspectorView, SettingsView, ExportDialogView).
struct SectionHeader: View {
    let titleKey: LocalizedStringKey

    init(_ titleKey: LocalizedStringKey) {
        self.titleKey = titleKey
    }

    var body: some View {
        Text(titleKey).font(.headline)
    }
}

extension View {
    /// Bündelt `.formStyle(.grouped)` mit Top-Alignment/Fill, damit kurzer Inhalt in einem
    /// grösseren Fenster nicht vertikal zentriert statt oben zu beginnen (Issue #26, Bug 3b —
    /// z.B. die Garnlisten-/Stickrahmen-Panes in den Einstellungen).
    func inspectorForm() -> some View {
        self
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Kurzes Achsen-Label ("X"/"Y"/"B"/"H") vor einem Zahlenfeld — dieselbe Struktur war in
/// `ObjectInspectorView` und `ProjectInspectorView` nahezu wortgleich dupliziert.
struct AxisField: View {
    let labelKey: LocalizedStringKey
    let binding: Binding<Double>

    init(_ labelKey: LocalizedStringKey, binding: Binding<Double>) {
        self.labelKey = labelKey
        self.binding = binding
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(labelKey).font(.caption2).foregroundStyle(.secondary)
            TextField("", value: binding, format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .frame(width: DesignSystem.numberFieldWidth)
        }
    }
}
