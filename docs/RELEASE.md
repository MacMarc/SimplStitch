# Release erstellen (von Hand, mit Xcode)

SimplStitch wird von Hand gebaut, notarisiert und als DMG auf GitHub veröffentlicht. Es gibt bewusst keine CI-Automatisierung dafür; der GitHub-Workflow `build.yml` baut und testet nur.

## Warum es ein Zusatzskript braucht

Xcode signiert nur die App selbst, nicht die rund 67 Binärdateien der gebündelten Python-Runtime unter `Contents/Resources/python` (`python3.12`, `libpython`, die `.so`-Module von numpy, lxml, Pillow …). Apple lehnt die Notarisierung dann ab, z.B. mit:

> Hardened Runtime is Not Enabled — "python3.12" must be rebuilt with support for the Hardened Runtime.

Hardened Runtime ist für die App selbst schon eingeschaltet (*Signing & Capabilities → Hardened Runtime*). Für die Python-Dateien erledigt das die Build-Phase **Sign Embedded Python** (`Scripts/sign_embedded_binaries.sh`): Beim Archivieren signiert sie jede dieser Dateien mit der Developer ID, Hardened Runtime (`--options runtime`) und Zeitstempel (`--timestamp`). Bei normalen Builds (Run, Test) tut sie nichts.

## Einmalige Einrichtung

1. **Developer-ID-Zertifikat:** In *Xcode → Settings → Accounts → Manage Certificates* muss ein „Developer ID Application"-Zertifikat für das Team vorhanden sein (sonst mit „+" anlegen). Die Build-Phase sucht es automatisch im Schlüsselbund. Gibt es mehrere, kann man eines über die Umgebungsvariable `SIGNING_IDENTITY` festlegen.
2. **Zugangsdaten für die Notarisierung** (nur für das DMG-Skript nötig). Unter [account.apple.com](https://account.apple.com) → *Anmelden und Sicherheit → App-spezifische Passwörter* ein Passwort erzeugen, dann im Terminal:

   ```bash
   xcrun notarytool store-credentials SimplStitch-Notary \
     --apple-id DEINE-APPLE-ID --team-id 6B76PB9TQW
   ```

   notarytool fragt nach dem app-spezifischen Passwort und legt es im Schlüsselbund ab. Ein anderer Profilname geht auch, dann beim Skript `NOTARY_PROFILE=…` setzen.

## Ablauf pro Release

1. **Version setzen:** Target *SimplStitch → General → Identity*: *Version* (z.B. `0.1.0`) und *Build* (hochzählen).
2. **Archivieren:** Oben als Ziel *Any Mac* wählen, dann *Product → Archive*. Im Build-Log (Report-Navigator) sollte bei „Sign Embedded Python" etwa „67 eingebettete Binärdateien mit Hardened Runtime signiert" stehen. Erscheint dort eine gelbe Warnung „Keine eindeutige Developer ID Application-Identität", fehlt das Zertifikat aus der Einrichtung.
3. **Notarisieren lassen:** Im Organizer das Archiv wählen → *Distribute App* → *Direct Distribution* → *Distribute*. Xcode lädt die App zu Apple hoch und wartet auf die Notarisierung (meist Minuten, ausnahmsweise Stunden). Danach *Export* und die App z.B. in einen Ordner `~/Desktop/SimplStitch-Export` legen.
4. **DMG bauen:** Im Terminal im Repo-Ordner:

   ```bash
   Scripts/build_dmg.sh ~/Desktop/SimplStitch-Export/SimplStitch.app
   ```

   Das Skript packt die App in `dist/SimplStitch-<Version>.dmg`, signiert und notarisiert auch das DMG, stapelt das Ticket und prüft das Ergebnis mit Gatekeeper. Am Ende sollte `accepted` und `source=Notarized Developer ID` stehen.
5. **Kurz testen:** DMG auf einem Mac öffnen, App in *Programme* ziehen, starten, eine Form zeichnen und die Stichvorschau prüfen. Erst dann ist sicher, dass die signierte Python-Runtime in der Sandbox läuft.
6. **Veröffentlichen:** Auf GitHub *Releases → Draft a new release*, Tag `v<Version>` anlegen, das DMG anhängen. Als Text eignet sich `.github/release-notes-template.md` (`{{VERSION}}` ersetzen, Höhepunkte ergänzen).

## Wenn etwas schiefgeht

- **Notarisierung abgelehnt:** Im Organizer unter *Show Status Log* bzw. in der Ausgabe von `build_dmg.sh` steht Apples Protokoll mit der betroffenen Datei. Meist fehlte beim Archivieren das Developer-ID-Zertifikat (Schritt 2 im Ablauf).
- **Ohne Xcodes Notarisierung:** Im Organizer stattdessen *Distribute App → Custom → Direct Distribution → Export* wählen. `build_dmg.sh` erkennt die nicht notarisierte App, signiert die Python-Binärdateien selbst nach, versiegelt die App neu und notarisiert sie, bevor es das DMG baut.
- **App aus DerivedData:** Eine mit *Product → Build* gebaute App trägt das Debug-Entitlement `get-task-allow`, das Apple immer ablehnt. Das Skript bricht dann mit einem Hinweis ab; immer über *Product → Archive* gehen.
