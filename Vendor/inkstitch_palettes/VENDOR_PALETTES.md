# Vendor-Paletten

`palettes/` enthält die 73 mitgelieferten `.gpl`-Garnlisten (GIMP Palette, mehrerer
Garnhersteller — Anchor, Isacord, Robison-Anton, Sulky, Madeira u.v.m.) aus
[inkstitch/inkstitch](https://github.com/inkstitch/inkstitch) (`Contents/Resources/palettes/`
im gebauten Inkscape-Erweiterungs-Bundle, InkStitch v3.2.2) — unverändert übernommen, exakt
dieselbe Quelle wie der bereits vendorte `lib/`-Code (`Vendor/inkstitch_lib/`).

## Nutzung

`Scripts/bundle_python.sh` kopiert `palettes/` bei jedem Build zusätzlich zur InkStitch-
Bibliothek nach `Contents/Resources/thread_palettes/` (Geschwisterordner von `python/` und
`inkstitch_lib/`, aus demselben Grund ausserhalb von `SimplStitch/` gehalten — siehe
`Vendor/inkstitch_lib/VENDOR_PATCHES.md`). `BuiltInThreadPaletteBootstrapper.swift`
(`SimplStitch/Services/`) importiert daraus beim ersten App-Start alle Paletten als
`ThreadPalette` (`isBuiltIn = true`) über den bestehenden `GPLPaletteImporter` (Phase 7) — reines
Swift, kein Python-Bezug beim Import selbst, nur beim Bundling der Dateien in die App.

## Lizenz

InkStitch ist GPL-3.0, `LICENSE` liegt unverändert in diesem Verzeichnis. SimplStitch selbst ist
ebenfalls GPL-3.0 — keine Lizenzinkompatibilität.
