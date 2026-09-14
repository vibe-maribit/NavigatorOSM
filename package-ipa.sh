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

# 2.1 Genera la struttura _CodeSignature/CodeResources necessaria a installd
echo "Generazione _CodeSignature/CodeResources..."
python3 - << 'EOF'
import os, hashlib, plistlib

app_dir = "build_ipa/Payload/NavigatoreOSM.app"
cs_dir = os.path.join(app_dir, "_CodeSignature")
os.makedirs(cs_dir, exist_ok=True)

files = {}
files2 = {}
for root, dirs, filenames in os.walk(app_dir):
    if "_CodeSignature" in root:
        continue
    for f in filenames:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, app_dir)
        with open(full, "rb") as fp:
            data = fp.read()
        h1 = hashlib.sha1(data).digest()
        h2 = hashlib.sha256(data).digest()
        files[rel] = h1
        files2[rel] = {"hash": h1, "hash2": h2}

plist_data = {
    "files": files,
    "files2": files2,
    "rules": {
        "^.*": True,
        "^.*\\.lproj/": {"optional": True, "weight": 1000},
        "^version\\.plist$": True
    },
    "rules2": {
        "^.*": True,
        ".*\\.dSYM($|/)": {"weight": 11},
        "^(.*/)?\\.DS_Store$": {"omit": True, "weight": 2000},
        "^.*\\.lproj/": {"optional": True, "weight": 1000},
        "^version\\.plist$": {"weight": 20}
    }
}

out_path = os.path.join(cs_dir, "CodeResources")
with open(out_path, "wb") as fp:
    plistlib.dump(plist_data, fp)
print(f"  [+] CodeResources generato con successo ({len(files)} file indicizzati)")
EOF

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
echo "  ./install-usb.sh"
echo "========================================================="
