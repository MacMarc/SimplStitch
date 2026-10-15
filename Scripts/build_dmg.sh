#!/usr/bin/env bash
# Baut aus einer exportierten SimplStitch.app ein signiertes, notarisiertes DMG. Ablauf und
# einmalige Einrichtung: docs/RELEASE.md.
#
#   Scripts/build_dmg.sh <Pfad/zu/SimplStitch.app> [Ausgabeordner]
#
# - Ist die App schon notarisiert und gestapelt (Organizer → Direct Distribution), wird sie
#   unverändert ins DMG gepackt.
# - Sonst (Organizer → Export ohne Notarisierung) signiert das Skript die eingebetteten
#   Python-Binärdateien, versiegelt die App neu, notarisiert und stapelt sie zuerst.
# - Danach: DMG bauen, signieren, notarisieren, stapeln, mit Gatekeeper prüfen.
#
# Optionale Umgebungsvariablen:
#   SIGNING_IDENTITY  Developer-ID-Identität; sonst wird sie im Schlüsselbund gesucht
#   TEAM_ID           grenzt die Suche im Schlüsselbund auf ein Team ein
#   NOTARY_PROFILE    Name des notarytool-Schlüsselbundprofils (Standard: SimplStitch-Notary)
set -euo pipefail

if [ $# -lt 1 ] || [ ! -d "$1" ]; then
	echo "Aufruf: $0 <Pfad/zu/SimplStitch.app> [Ausgabeordner]" >&2
	exit 64
fi

APP="$(cd "$1" && pwd)"
OUT_DIR="${2:-$(pwd)/dist}"
NOTARY_PROFILE="${NOTARY_PROFILE:-SimplStitch-Notary}"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/signing_common.sh"

IDENTITY="$(resolve_developer_id)"
if [ -z "${IDENTITY}" ]; then
	echo "build_dmg.sh: keine eindeutige \"Developer ID Application\"-Identität im Schlüsselbund." >&2
	echo "Mit SIGNING_IDENTITY=\"Developer ID Application: Name (TEAMID)\" oder TEAM_ID=… angeben." >&2
	exit 1
fi

if ! xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
	echo "build_dmg.sh: notarytool-Profil \"${NOTARY_PROFILE}\" fehlt oder ist ungültig." >&2
	echo "Einmalig anlegen (siehe docs/RELEASE.md):" >&2
	echo "  xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <Apple-ID> --team-id <TEAMID>" >&2
	exit 1
fi

notarize() {
	local artifact="$1" result status id
	echo "build_dmg.sh: reiche $(basename "${artifact}") zur Notarisierung ein (kann dauern) ..."
	result="$(xcrun notarytool submit "${artifact}" --keychain-profile "${NOTARY_PROFILE}" \
		--wait --timeout "${NOTARY_TIMEOUT:-3h}" --output-format json)"
	status="$(plutil -extract status raw -o - - <<<"${result}" 2>/dev/null || true)"
	id="$(plutil -extract id raw -o - - <<<"${result}" 2>/dev/null || true)"
	if [ "${status}" != "Accepted" ]; then
		echo "build_dmg.sh: Notarisierung fehlgeschlagen (${status:-unbekannt}). Apples Protokoll:" >&2
		[ -n "${id}" ] && xcrun notarytool log "${id}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
		exit 1
	fi
	echo "build_dmg.sh: notarisiert (${id})"
}

if xcrun stapler validate "${APP}" >/dev/null 2>&1; then
	echo "build_dmg.sh: App ist bereits notarisiert und gestapelt, packe sie unverändert"
else
	# Eine Debug-/Development-Signatur (z.B. App direkt aus DerivedData) trägt get-task-allow; das
	# lehnt Apple immer ab. Nur aus einem Archiv exportierte Apps sind brauchbar.
	if codesign -d --entitlements - --xml "${APP}" 2>/dev/null | grep -q "get-task-allow"; then
		echo "build_dmg.sh: Die App trägt das Debug-Entitlement get-task-allow. Bitte über" >&2
		echo "Product → Archive und den Organizer exportieren, nicht aus DerivedData nehmen." >&2
		exit 1
	fi
	echo "build_dmg.sh: App ist noch nicht notarisiert, signiere und notarisiere sie zuerst"
	sign_embedded_binaries "${APP}/Contents/Resources" "${IDENTITY}"
	codesign --force --timestamp --options runtime --sign "${IDENTITY}" \
		--preserve-metadata=entitlements,requirements,flags "${APP}"
	codesign --verify --strict --verbose=2 "${APP}"
	WORK_DIR="$(mktemp -d)"
	ditto -c -k --keepParent "${APP}" "${WORK_DIR}/SimplStitch.zip"
	notarize "${WORK_DIR}/SimplStitch.zip"
	xcrun stapler staple "${APP}"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
DMG="${OUT_DIR}/SimplStitch-${VERSION}.dmg"
mkdir -p "${OUT_DIR}"

echo "build_dmg.sh: baue ${DMG} ..."
DMG_ROOT="$(mktemp -d)"
ditto "${APP}" "${DMG_ROOT}/SimplStitch.app"
ln -s /Applications "${DMG_ROOT}/Applications"
rm -f "${DMG}"
hdiutil create -volname "SimplStitch ${VERSION}" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${DMG}"
codesign --force --timestamp --sign "${IDENTITY}" "${DMG}"
notarize "${DMG}"
xcrun stapler staple "${DMG}"

spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
echo "build_dmg.sh: fertig: ${DMG}"
