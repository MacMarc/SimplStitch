#!/usr/bin/env bash
# Issue #4: signiert die exportierte App inklusive der gebündelten Python-Runtime, notarisiert
# und stapelt sie, baut daraus ein DMG und notarisiert auch das.
#
#   Scripts/sign_and_notarize.sh <SimplStitch.app> <Ausgabe.dmg> <Volume-Name>
#
# Erwartete Umgebungsvariablen:
#   SIGNING_IDENTITY       z.B. "Developer ID Application: Name (TEAMID)"
#   NOTARY_KEY_PATH        Pfad zur App-Store-Connect-API-Key-Datei (.p8)
#   NOTARY_KEY_ID          Key-ID des API-Keys
#   NOTARY_ISSUER_ID       Issuer-ID des API-Keys
#
# Warum ein eigenes Skript (siehe Kommentar in Issue #4 zum manuellen Durchlauf):
# Xcode signiert beim Export nur die äussere App, nicht die ~67 Mach-O-Dateien der
# Python-Runtime unter Contents/Resources. Apple lehnt die Notarisierung sonst ab. Jede
# Binärdatei wird deshalb einzeln mit Hardened Runtime und Zeitstempel signiert (innen nach
# aussen), danach wird die App mit ihren bestehenden Entitlements neu versiegelt.
set -euo pipefail

APP="$1"
DMG="$2"
VOLUME_NAME="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER_ENTITLEMENTS="${SCRIPT_DIR}/PythonHelper.entitlements"
# Die Notarisierung dauerte beim manuellen Testlauf über 2 Stunden — grosszügig bemessen.
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-3h}"

: "${SIGNING_IDENTITY:?SIGNING_IDENTITY fehlt}"
: "${NOTARY_KEY_PATH:?NOTARY_KEY_PATH fehlt}"
: "${NOTARY_KEY_ID:?NOTARY_KEY_ID fehlt}"
: "${NOTARY_ISSUER_ID:?NOTARY_ISSUER_ID fehlt}"

sign() {
	codesign --force --timestamp --options runtime --sign "${SIGNING_IDENTITY}" "$@"
}

is_macho() {
	file -b "$1" | grep -q "Mach-O"
}

notarize() {
	local artifact="$1"
	local result
	echo "sign_and_notarize.sh: reiche $(basename "${artifact}") zur Notarisierung ein ..."
	result="$(xcrun notarytool submit "${artifact}" \
		--key "${NOTARY_KEY_PATH}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID}" \
		--wait --timeout "${NOTARY_TIMEOUT}" --output-format json)"
	echo "${result}"
	local status id
	status="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' <<<"${result}")"
	id="$(/usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' <<<"${result}")"
	if [ "${status}" != "Accepted" ]; then
		echo "sign_and_notarize.sh: Notarisierung fehlgeschlagen (${status}), Protokoll:" >&2
		[ -n "${id}" ] && xcrun notarytool log "${id}" \
			--key "${NOTARY_KEY_PATH}" --key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID}" >&2 || true
		exit 1
	fi
}

echo "sign_and_notarize.sh: signiere eingebettete Binärdateien ..."
signed_count=0
# Tiefste Pfade zuerst, damit nichts Äusseres vor seinem Inhalt versiegelt wird.
while IFS= read -r file; do
	is_macho "${file}" || continue
	if [[ "${file}" == */python/bin/* ]]; then
		sign --entitlements "${HELPER_ENTITLEMENTS}" "${file}"
	else
		sign "${file}"
	fi
	signed_count=$((signed_count + 1))
done < <(find "${APP}/Contents/Resources" -type f | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
echo "sign_and_notarize.sh: ${signed_count} Binärdateien signiert"

echo "sign_and_notarize.sh: versiegle App neu ..."
sign --preserve-metadata=entitlements,requirements,flags "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"

APP_ZIP="$(mktemp -d)/$(basename "${APP}" .app).zip"
ditto -c -k --keepParent "${APP}" "${APP_ZIP}"
notarize "${APP_ZIP}"
xcrun stapler staple "${APP}"

echo "sign_and_notarize.sh: baue DMG ..."
DMG_ROOT="$(mktemp -d)"
cp -R "${APP}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"
rm -f "${DMG}"
hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${DMG_ROOT}" -ov -format UDZO "${DMG}"
sign "${DMG}"
notarize "${DMG}"
xcrun stapler staple "${DMG}"

spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG}"
echo "sign_and_notarize.sh: fertig: ${DMG}"
