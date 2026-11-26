#!/usr/bin/env bash
# Installs Mesen2 (the Linux zip given as the first argument) in the directory given as the second argument, in
# portable mode with the settings that the headless tests need (Lua scripts may write files, zeroed RAM at power
# on, a standard controller in port 1). Used by the CI workflow; locally, any Mesen2 with these settings works.
set -eu
URL="$1"
DIR="$2"
mkdir -p "$DIR"
cd "$DIR"
curl -fL -o mesen.zip "$URL"
unzip -o -q mesen.zip
rm -f mesen.zip
# Some releases have the files in a subdirectory
if [ ! -e Mesen ]; then
    found="$(find . -name Mesen -type f | head -1)"
    [ -n "$found" ] && cp -r "$(dirname "$found")"/. . && rm -rf "$(dirname "$found")"
fi
chmod +x Mesen
cat > settings.json <<'JSON'
{
  "Snes": { "RamPowerOnState": "AllZeros", "Port1": { "Type": "SnesController" } },
  "Debug": { "ScriptWindow": { "AllowIoOsAccess": true, "ScriptTimeout": 600 } }
}
JSON
echo "Mesen installed in $DIR"
