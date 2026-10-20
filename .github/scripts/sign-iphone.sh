#!/bin/bash
# Run only on an ephemeral macOS build runner. Never enable shell tracing.
set -euo pipefail
: "${APPLE_CERTIFICATE_P12_BASE64:?Add the Apple Development certificate as a repository secret.}"
: "${APPLE_CERTIFICATE_PASSWORD:?Add the certificate password as a repository secret.}"
: "${APPLE_APP_PROFILE_BASE64:?Add the app development provisioning profile.}"
: "${APPLE_HELPER_PROFILE_BASE64:?Add the helper development provisioning profile.}"
archive=$(cd "$1" && pwd)
mkdir -p "$2"
output=$(cd "$2" && pwd)
work=$(mktemp -d)
keychain="$work/signing.keychain-db"
keychain_password=$(openssl rand -hex 32)
profiles="$HOME/Library/MobileDevice/Provisioning Profiles"
app_uuid=
helper_uuid=
cleanup() {
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    [[ -z "$app_uuid" ]] || rm -f "$profiles/$app_uuid.mobileprovision"
    [[ -z "$helper_uuid" ]] || rm -f "$profiles/$helper_uuid.mobileprovision"
    rm -rf "$work"
}
trap cleanup EXIT
printf '%s' "$APPLE_CERTIFICATE_P12_BASE64" | base64 -D > "$work/certificate.p12"
printf '%s' "$APPLE_APP_PROFILE_BASE64" | base64 -D > "$work/app.mobileprovision"
printf '%s' "$APPLE_HELPER_PROFILE_BASE64" | base64 -D > "$work/helper.mobileprovision"
security cms -D -i "$work/app.mobileprovision" > "$work/app.plist"
security cms -D -i "$work/helper.mobileprovision" > "$work/helper.plist"
buddy=/usr/libexec/PlistBuddy
app_uuid=$($buddy -c 'Print :UUID' "$work/app.plist")
helper_uuid=$($buddy -c 'Print :UUID' "$work/helper.plist")
team=$($buddy -c 'Print :TeamIdentifier:0' "$work/app.plist")
[[ "$team" =~ ^[A-Z0-9]{10}$ && "$app_uuid" =~ ^[A-Fa-f0-9-]{36}$ && "$helper_uuid" =~ ^[A-Fa-f0-9-]{36}$ ]]
[[ "$($buddy -c 'Print :TeamIdentifier:0' "$work/helper.plist")" == "$team" ]]
bundle='dev.tcballard.iphomarchy.UTM'
for role in app helper; do
    expected="$bundle"
    [[ "$role" == app ]] || expected="$bundle.iOSHelper"
    [[ "$($buddy -c 'Print :Entitlements:application-identifier' "$work/$role.plist")" == "$team.$expected" ]]
    [[ "$($buddy -c 'Print :Entitlements:get-task-allow' "$work/$role.plist")" == true ]]
    $buddy -c 'Print :ProvisionedDevices:0' "$work/$role.plist" >/dev/null
done
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/certificate.p12" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" login.keychain-db
identity=$(security find-identity -v -p codesigning "$keychain" | awk '/"Apple Development:/ {print $2; exit}')
[[ "$identity" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'No valid Apple Development signing identity was found.' >&2; exit 1; }
mkdir -p "$profiles"
cp "$work/app.mobileprovision" "$profiles/$app_uuid.mobileprovision"
cp "$work/helper.mobileprovision" "$profiles/$helper_uuid.mobileprovision"
options="$work/export.plist"
$buddy -c 'Clear dict' "$options" >/dev/null
$buddy -c 'Add :method string development' "$options"
$buddy -c 'Add :signingStyle string manual' "$options"
$buddy -c "Add :teamID string $team" "$options"
$buddy -c "Add :signingCertificate string $identity" "$options"
$buddy -c 'Add :provisioningProfiles dict' "$options"
$buddy -c "Add :provisioningProfiles:$bundle string $app_uuid" "$options"
$buddy -c "Add :provisioningProfiles:$bundle.iOSHelper string $helper_uuid" "$options"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" -exportPath "$work/export"
ipas=("$work/export/"*.ipa)
[[ ${#ipas[@]} -eq 1 && -f "${ipas[0]}" ]] || { echo 'Expected one exported IPA.' >&2; exit 1; }
cp "${ipas[0]}" "$output/iPhomarchy-development.ipa"
echo 'Signed development IPA created. Install only on a device included in the profiles.'
