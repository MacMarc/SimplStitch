#!/usr/bin/env bash
# Xcode-Build-Phase "Sign Embedded Python": signiert beim Archivieren (Product → Archive) jede
# Binärdatei der gebündelten Python-Runtime mit Developer ID, Hardened Runtime und Zeitstempel.
# Xcode versiegelt die App danach in seinem eigenen CodeSign-Schritt, und "Distribute App →
# Direct Distribution" im Organizer kann sie direkt notarisieren.
#
# Bei normalen Builds (Run, Test, CI mit CODE_SIGNING_ALLOWED=NO) tut das Skript nichts, damit
# Debug-Builds schnell bleiben und ohne Zertifikat funktionieren.
#
# Identität: SIGNING_IDENTITY (falls in Xcodes Umgebung gesetzt), sonst die Developer-ID-
# Application-Identität des Teams DEVELOPMENT_TEAM aus dem Schlüsselbund.
set -euo pipefail

if [ "${ACTION:-}" != "install" ] || [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
	echo "sign_embedded_binaries.sh: kein Archiv-Build, überspringe Signierung"
	exit 0
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/signing_common.sh"

# TARGET_BUILD_DIR, nicht BUILT_PRODUCTS_DIR: beim Archivieren (DEPLOYMENT_LOCATION=YES) liegt die
# App, die ins Archiv kommt, unter TARGET_BUILD_DIR; BUILT_PRODUCTS_DIR zeigt dann woandershin.
RESOURCES="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
IDENTITY="$(resolve_developer_id)"

if [ -z "${IDENTITY}" ]; then
	# Ohne Developer ID lässt sich trotzdem archivieren (z.B. zum lokalen Testen), aber Apple wird
	# die Notarisierung ablehnen. Deshalb nur eine Warnung, die im Xcode-Build-Log gelb erscheint.
	IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
	echo "warning: Keine eindeutige \"Developer ID Application\"-Identität für Team ${DEVELOPMENT_TEAM:-?} im Schlüsselbund gefunden. Die Python-Runtime wird mit ${IDENTITY} signiert; die Notarisierung wird so fehlschlagen. Siehe docs/RELEASE.md."
fi

sign_embedded_binaries "${RESOURCES}" "${IDENTITY}"
