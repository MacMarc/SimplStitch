# Release erstellen

Ein Release entsteht automatisch über GitHub Actions (`.github/workflows/release.yml`), sobald ein Tag `v*` gepusht wird:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Der Workflow testet, archiviert, signiert die App samt Python-Runtime mit der Developer ID, lässt App und DMG von Apple notarisieren und legt einen **Entwurf** eines GitHub Releases mit dem DMG an. Den Entwurf prüfen, Höhepunkte in den Release-Notes ergänzen und veröffentlichen.

Alternativ lässt sich der Workflow unter *Actions → Release → Run workflow* für einen bereits existierenden Tag starten.

Die Notarisierung kann lange dauern (beim manuellen Testlauf über 2 Stunden). Der Job hat deshalb ein Zeitlimit von 4 Stunden.

## Einmalige Einrichtung: Repository-Secrets

Unter *Settings → Secrets and variables → Actions → New repository secret* diese fünf Secrets anlegen:

| Secret | Inhalt |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Das Developer-ID-Application-Zertifikat mit privatem Schlüssel als `.p12`, Base64-kodiert |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Das Passwort, das beim Export der `.p12` vergeben wurde |
| `NOTARY_API_KEY_P8_BASE64` | App-Store-Connect-API-Key (`.p8`), Base64-kodiert |
| `NOTARY_API_KEY_ID` | Key-ID dieses API-Keys |
| `NOTARY_API_ISSUER_ID` | Issuer-ID (steht über der Key-Liste in App Store Connect) |

### Zertifikat exportieren

1. *Schlüsselbundverwaltung* öffnen, unter *Meine Zertifikate* „Developer ID Application: …" suchen.
2. Rechtsklick → *Exportieren…* → Format `.p12`, Passwort vergeben.
3. Base64 in die Zwischenablage: `base64 -i Zertifikat.p12 | pbcopy`

### API-Key für die Notarisierung

1. [App Store Connect → Benutzer und Zugriff → Integrationen → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) öffnen.
2. Neuen Team-Key mit der Rolle *Developer* anlegen und die `.p8` herunterladen (geht nur einmal).
3. Base64 in die Zwischenablage: `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy`
4. Key-ID und Issuer-ID von derselben Seite übernehmen.

## Was das Signier-Skript zusätzlich macht

Xcode signiert beim Export nur die äussere App. Die gebündelte Python-Runtime (rund 67 Binärdateien unter `Contents/Resources/python`) würde Apple bei der Notarisierung ablehnen. `Scripts/sign_and_notarize.sh` signiert deshalb jede Binärdatei einzeln mit Hardened Runtime und Zeitstempel und versiegelt die App danach neu. Die Python-Programme selbst bekommen die Entitlements aus `Scripts/PythonHelper.entitlements`, damit sie die Sandbox der App erben.

Nach dem ersten Release lohnt sich ein kurzer Test des heruntergeladenen DMG auf einem Mac: App starten, eine Form zeichnen und die Stichvorschau prüfen. Erst dann ist sicher, dass die signierte Python-Runtime in der Sandbox läuft.
