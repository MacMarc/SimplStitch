---
name: run-and-screenshot
description: Use this skill to build, launch, and visually verify the SimplStitch macOS app via a real screenshot — e.g. "screenshot the app", "run SimplStitch and check the UI", "visuell verifizieren", "testbuild visuell überprüfen". Covers the Xcode build invocation, launching the .app from DerivedData, and the Space-switching fix needed before screencapture works.
---

# SimplStitch bauen, starten und visuell verifizieren

SimplStitch ist eine native macOS-SwiftUI-App (kein Web-/Electron-Frontend). Es gibt kein
`.xcworkspace`, nur `SimplStitch.xcodeproj` mit dem Scheme `SimplStitch`.

## 1. Bauen

```bash
cd "/Users/macmarc/Library/Mobile Documents/com~apple~CloudDocs/Xcode/SimplStitch"
xcodebuild -scheme SimplStitch -configuration Debug -destination 'platform=macOS' build
```

Erwartete Laufzeit: ~1-2 Minuten (inkl. Python-Runtime-Bundling-Script). Erfolg endet mit
`** BUILD SUCCEEDED **`. Das Produkt landet unter DerivedData, z.B.:

```
/Users/macmarc/Library/Developer/Xcode/DerivedData/SimplStitch-<hash>/Build/Products/Debug/SimplStitch.app
```

Den genauen Pfad nicht raten — nach dem Build mit `find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -iname "SimplStitch-*"` ermitteln, der Hash ändert sich zwischen Checkouts/Maschinen nicht, aber verlasse dich nicht darauf.

## 2. Starten

```bash
pkill -f "SimplStitch.app" 2>/dev/null
sleep 1
open "$APP"   # $APP = obiger .app-Pfad
sleep 3
```

## 3. Screenshot — der eigentliche Stolperstein

Ein einfaches `screencapture -x datei.png` reicht **nicht zuverlässig**, wenn das Terminal
(oder ein anderer Prozess, von dem aus `screencapture` läuft) im macOS-Vollbildmodus in einem
eigenen Space läuft. `screencapture` fängt dann nur den aktuell aktiven Space ein — also das
Vollbild-Terminal, nicht das SimplStitch-Fenster, selbst wenn `pgrep` zeigt, dass der Prozess
läuft und `System Events` ihn sogar als "frontmost" meldet.

**Fix:** SimplStitch vor dem Screenshot explizit aktivieren — das lässt macOS automatisch in
den Space mit dem SimplStitch-Fenster wechseln:

```bash
osascript -e 'tell application "SimplStitch" to activate'
sleep 1.5
screencapture -x "$SCRATCH/simplstitch.png"
```

Danach den Screenshot mit dem Read-Tool öffnen, um wirklich hinzuschauen (nicht nur die
Dateigrösse/den Dateityp prüfen — ein leeres oder falsches Bild hat auch eine plausible
Dateigrösse).

Voraussetzung: Bildschirmaufnahme-Berechtigung für den Prozess, der `screencapture` aufruft
(Terminal/iTerm/etc.), muss unter Systemeinstellungen → Datenschutz & Sicherheit →
Bildschirmaufnahme erteilt sein. Ohne diese Berechtigung liefert `screencapture` ein leeres
oder schwarzes Bild statt eines Fehlers — das lässt sich nur durch Anschauen des Ergebnisses
erkennen, nicht am Exit-Code.

## Bekannte Grenzen

- **Klick-Interaktion über AppleScript/System Events schlägt fehl:** Zugriffe wie
  `click button "Rechteck" of window 1` liefern Fehler -1728 ("kann nicht gelesen werden").
  SwiftUI-Buttons sind über die klassische Accessibility-Bridge nicht zuverlässig ansprechbar.
  Für reine visuelle Verifikation (Screenshot anschauen) reicht das obige Vorgehen. Für
  automatisierte Klick-Interaktion wäre ein anderes Tool nötig (z.B. `cliclick`, aktuell nicht
  installiert) oder ein UI-Test-Target (`SimplStitchUITests`) über `xcodebuild test`.
- **Kein Multi-Window/Multi-Space-Handling über die Fenstergeometrie hinaus getestet** — bei
  mehreren SimplStitch-Fenstern gleichzeitig ggf. zusätzlich per `System Events` das
  gewünschte Fenster in den Vordergrund holen.
