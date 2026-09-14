#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "========================================================="
echo "  Compilazione NavigatoreOSM per iPad Mini 1 (iOS 9.3.5)"
echo "  Target: 32-bit armv7 - SDK: iPhoneOS 9.3"
echo "========================================================="

# 1. Compila l'applicazione con Theos in ambiente Docker
docker run --rm -v "$DIR:/project" -w /project cauan/theos make clean all DEBUG=0 messages=no

# 2. Crea la struttura standard dell'IPA (Payload/NavigatoreOSM.app)
rm -rf build_ipa NavigatoreOSM.ipa
mkdir -p build_ipa/Payload
cp -r .theos/obj/NavigatoreOSM.app build_ipa/Payload/

# 3. Comprimi in formato .ipa standard
cd build_ipa
zip -q -r -9 ../NavigatoreOSM.ipa Payload/
cd ..
rm -rf build_ipa

echo ""
echo "========================================================="
echo "  SUCCESS: NavigatoreOSM.ipa generato con successo!"
echo "========================================================="
ls -lh NavigatoreOSM.ipa
file .theos/obj/NavigatoreOSM.app/NavigatoreOSM
echo ""
echo "Per installarlo sul tuo iPad Mini 1 collegato via USB:"
echo "  ideviceinstaller -i NavigatoreOSM.ipa"
echo "========================================================="
