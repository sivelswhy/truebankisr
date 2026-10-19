#!/bin/sh
# Builds an unsigned IPA like CI does and puts it in ../dist/TrueBalance.ipa.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ -f Local.xcconfig ] || cp Local.xcconfig.example Local.xcconfig
xcodegen generate --quiet
xcodebuild -project TrueBalance.xcodeproj -scheme TrueBalance -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build -quiet \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
rm -rf Payload && mkdir Payload
cp -R build/Build/Products/Release-iphoneos/TrueBalance.app Payload/
mkdir -p ../dist && rm -f ../dist/TrueBalance.ipa
zip -qry ../dist/TrueBalance.ipa Payload && rm -rf Payload
echo "IPA: $(cd ../dist && pwd)/TrueBalance.ipa"
