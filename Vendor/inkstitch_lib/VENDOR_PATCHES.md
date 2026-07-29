# Vendor-Patches

`lib/` ist unverändert übernommen von [inkstitch/inkstitch](https://github.com/inkstitch/inkstitch),
Commit `e7108fdbb4a8b4175717678593d17dbd218284ed` (main, Stand des Vendorings) — mit **einer** Ausnahme:

## `lib/tartan/palette.py`

Original importiert `wx` (Inkscape-GUI-Toolkit) um Swatch-Dateien für den Tartan-Fill-Palette-Editor
zu laden/speichern. SimplStitch nutzt `fill_method=tartan_fill` nie — `Palette` wird zwar per Name in
`tartan/utils.py` und `elements/fill_stitch.py` importiert, aber in keinem von SimplStitch genutzten
Codepfad tatsächlich instanziiert.

Ersetzt durch einen 8-zeiligen wx-freien Stub, der bei Instanziierung `NotImplementedError` wirft
statt `wx` zu importieren — verhindert `import wx` beim Modul-Import, ohne die restliche `lib/`
anzufassen. Alle anderen `wx`/`flask`/`trimesh`-Importe im Baum liegen ausschliesslich in
`lib/gui/`, `lib/extensions/`, `lib/sew_stack/`, `lib/utils/icons.py` (nur von
`lib/extensions/sew_stack_editor.py` importiert) und `lib/utils/json.py` (nirgends innerhalb von
`lib/` importiert) — keiner davon liegt im Aufrufpfad von `FillStitch`/`Stroke`/`SatinColumn`.

`lib/stitches/contour_fill.py` importiert `trimesh` (für `contour_fill`, von SimplStitch nicht
genutzt) — unverändert gelassen, `trimesh` ist ein reines `pip install`-Paket ohne native Build-
Abhängigkeiten (nur `numpy`), daher kein zweiter Patch nötig, einfach mitinstalliert.

## Lizenz

InkStitch ist GPL-3.0, `LICENSE` liegt unverändert in diesem Verzeichnis. SimplStitch selbst ist
ebenfalls GPL-3.0 — keine Lizenzinkompatibilität.
