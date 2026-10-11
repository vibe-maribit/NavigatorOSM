#!/usr/bin/env python3
"""
Script per il bump semantico unificato della versione di NavigatorOSM.
Aggiorna atomicamente:
1. control (pacchetto Cydia / Theos)
2. NavigatoreOSM/Info.plist (bundle iOS)
3. android/app/build.gradle (versionName e versionCode per companion GPSTether)
"""

import sys
import re
import argparse
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
CONTROL_FILE = BASE_DIR / "control"
PLIST_FILE = BASE_DIR / "NavigatoreOSM" / "Info.plist"
GRADLE_FILE = BASE_DIR / "android" / "app" / "build.gradle"

def get_current_version():
    if not CONTROL_FILE.exists():
        raise FileNotFoundError(f"File non trovato: {CONTROL_FILE}")
    content = CONTROL_FILE.read_text(encoding="utf-8")
    m = re.search(r"^Version:\s*([0-9]+(?:\.[0-9]+)+)", content, re.MULTILINE)
    if not m:
        raise ValueError("Impossibile trovare il campo 'Version:' in control")
    return m.group(1).strip()

def bump_version(current_ver: str, bump_type: str) -> str:
    parts = [int(p) for p in current_ver.split(".")]
    while len(parts) < 3:
        parts.append(0)
    major, minor, patch = parts[0], parts[1], parts[2]

    bump = bump_type.lower()
    if bump == "major":
        return f"{major + 1}.0.0"
    elif bump == "minor":
        return f"{major}.{minor + 1}.0"
    elif bump == "patch":
        return f"{major}.{minor}.{patch + 1}"
    else:
        raise ValueError(f"Tipo di bump non valido: '{bump_type}'. Usa 'patch', 'minor' o 'major'.")

def update_files(new_ver: str, dry_run: bool = False):
    # 1. Aggiorna control
    control_content = CONTROL_FILE.read_text(encoding="utf-8")
    new_control = re.sub(
        r"^(Version:\s*).*",
        rf"\g<1>{new_ver}",
        control_content,
        flags=re.MULTILINE
    )

    # 2. Aggiorna NavigatoreOSM/Info.plist
    plist_content = PLIST_FILE.read_text(encoding="utf-8")
    new_plist = re.sub(
        r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)",
        rf"\g<1>{new_ver}\g<2>",
        plist_content
    )
    new_plist = re.sub(
        r"(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)",
        rf"\g<1>{new_ver}\g<2>",
        new_plist
    )

    # 3. Aggiorna android/app/build.gradle
    gradle_content = GRADLE_FILE.read_text(encoding="utf-8")
    
    # Incrementa versionCode
    def inc_code(match):
        code = int(match.group(2))
        return f"{match.group(1)}{code + 1}"

    new_gradle = re.sub(
        r"(versionCode\s+)(\d+)",
        inc_code,
        gradle_content
    )
    # Aggiorna versionName
    new_gradle = re.sub(
        r'(versionName\s+")[^"]+(")',
        rf'\g<1>{new_ver}\g<2>',
        new_gradle
    )

    if not dry_run:
        CONTROL_FILE.write_text(new_control, encoding="utf-8")
        PLIST_FILE.write_text(new_plist, encoding="utf-8")
        GRADLE_FILE.write_text(new_gradle, encoding="utf-8")

def main():
    parser = argparse.ArgumentParser(description="Semantic Version Bump per NavigatorOSM")
    parser.add_argument("bump_type", nargs="?", default="patch", choices=["patch", "minor", "major"],
                        help="Tipo di incremento semantico (default: patch)")
    parser.add_argument("--current", action="store_true", help="Mostra solo la versione attuale")
    parser.add_argument("--dry-run", action="store_true", help="Simula il bump senza scrivere sui file")
    
    args = parser.parse_args()

    current_ver = get_current_version()
    if args.current:
        print(current_ver)
        return

    new_ver = bump_version(current_ver, args.bump_type)
    update_files(new_ver, dry_run=args.dry_run)
    print(new_ver)

if __name__ == "__main__":
    main()
