#!/bin/bash
# Build SogenIOS unsigned, re-sign app + JITHelper + TunnelExtension with a Developer p12/profile zip,
# and install to a paired device. Usage: tools/resign_install.sh <cert.zip> [device-udid]
# The p12 password is read from the zip's "Password = N.txt" name convention (default 1).
set -e
ZIP="${1:?cert zip}"
DEV="${2:-00008140-001064D40233001C}"
PASS="${P12_PASSWORD:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/SogenIOS-*/Build/Products/Debug-iphoneos/SogenIOS.app | head -1)"
KC=/tmp/certx.keychain
W=/tmp/certx
OUT=/tmp/signx
rm -rf "$W" "$OUT" && mkdir -p "$W" "$OUT"

cd "$ROOT"
xcodebuild -scheme SogenIOS -project SogenIOS.xcodeproj -destination "generic/platform=iOS" -configuration Debug \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
DD="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/SogenIOS-*/Build/Products/Debug-iphoneos/SogenIOS.app | head -1)"

cd "$W" && unzip -o -q "$ZIP"
P12="$(ls Developer/*.p12 | head -1)"
PROFILE="$(ls Developer/*.mobileprovision | head -1)"
openssl pkcs12 -in "$P12" -passin pass:"$PASS" -nodes -out all.pem 2>/dev/null
openssl pkcs12 -export -in all.pem -out c.p12 -passout pass:"$PASS" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p tmp123 "$KC" && security unlock-keychain -p tmp123 "$KC"
security import c.p12 -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k tmp123 "$KC" >/dev/null 2>&1
security list-keychains -d user -s "$KC" "$HOME/Library/Keychains/login.keychain-db"
ID="$(security find-identity -v -p codesigning "$KC" | awk '/[0-9A-F]{40}/{print $2; exit}')"
security cms -D -i "$PROFILE" > prof.plist 2>/dev/null
APPID="$(plutil -extract Entitlements.application-identifier raw prof.plist)"
TEAM="$(plutil -extract TeamIdentifier.0 raw prof.plist)"

cp -R "$DD" "$OUT/SogenIOS.app"
cd "$OUT/SogenIOS.app"
cp "$W/$PROFILE" embedded.mobileprovision
cp embedded.mobileprovision Extensions/JITHelper.appex/embedded.mobileprovision
[ -d PlugIns/TunnelExtension.appex ] && cp embedded.mobileprovision PlugIns/TunnelExtension.appex/embedded.mobileprovision

mk() {
cat > "$1" <<E
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$APPID</string>
<key>com.apple.developer.team-identifier</key><string>$TEAM</string>
<key>get-task-allow</key><true/>
$2
</dict></plist>
E
}
NE='<key>com.apple.developer.networking.networkextension</key><array><string>packet-tunnel-provider</string></array>'
mk "$OUT/ent_jit.plist" ""
mk "$OUT/ent_ne.plist" "$NE"
mk "$OUT/ent_app.plist" "$NE<key>com.apple.developer.kernel.extended-virtual-addressing</key><true/><key>com.apple.developer.kernel.increased-memory-limit</key><true/>"
S="codesign --force --sign $ID --keychain $KC"

pushd Extensions/JITHelper.appex >/dev/null
for f in Frameworks/StikJIT.framework JITHelper.debug.dylib __preview.dylib; do [ -e "$f" ] && $S "$f" 2>/dev/null; done
$S --entitlements "$OUT/ent_jit.plist" --generate-entitlement-der . 2>/dev/null
popd >/dev/null
if [ -d PlugIns/TunnelExtension.appex ]; then
  pushd PlugIns/TunnelExtension.appex >/dev/null
  for f in TunnelExtension.debug.dylib __preview.dylib; do [ -e "$f" ] && $S "$f" 2>/dev/null; done
  $S --entitlements "$OUT/ent_ne.plist" --generate-entitlement-der . 2>/dev/null
  popd >/dev/null
fi
$S --entitlements "$OUT/ent_app.plist" --generate-entitlement-der . 2>/dev/null
codesign -vv --deep --strict . 2>&1 | tail -1

xcrun devicectl device install app --device "$DEV" "$OUT/SogenIOS.app" 2>&1 | grep -E "bundleID|rror|Unable|Reason"
security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db"
security delete-keychain "$KC"
rm -rf "$W" "$OUT"/ent_*.plist
echo DONE
