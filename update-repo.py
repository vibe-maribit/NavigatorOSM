#!/usr/bin/env python3
"""
update-repo.py: Genera i file indice APT per Cydia (Packages, Packages.bz2, Release)
a partire dai pacchetti .deb presenti nella cartella debs/
"""

import os
import sys
import hashlib
import bz2
import subprocess

REPO_DIR = os.path.dirname(os.path.abspath(__file__))
DEBS_DIR = os.path.join(REPO_DIR, "debs")
os.makedirs(DEBS_DIR, exist_ok=True)

def hash_file(filepath):
    md5 = hashlib.md5()
    sha1 = hashlib.sha1()
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            md5.update(chunk)
            sha1.update(chunk)
            sha256.update(chunk)
    return md5.hexdigest(), sha1.hexdigest(), sha256.hexdigest()

def extract_control_info(deb_path):
    try:
        cmd = ["dpkg-deb", "-f", deb_path]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        return result.stdout.strip()
    except Exception as e:
        print(f"Errore dpkg-deb su {deb_path}: {e}")
        return None

def main():
    deb_files = [f for f in os.listdir(DEBS_DIR) if f.endswith(".deb")]
    print(f"[+] Trovati {len(deb_files)} pacchetti in {DEBS_DIR}")

    packages_content = []

    for deb in sorted(deb_files):
        deb_path = os.path.join(DEBS_DIR, deb)
        control = extract_control_info(deb_path)
        if not control:
            continue

        size = os.path.getsize(deb_path)
        md5, sha1, sha256 = hash_file(deb_path)

        pkg_entry = control + "\n"
        pkg_entry += f"Filename: debs/{deb}\n"
        pkg_entry += f"Size: {size}\n"
        pkg_entry += f"MD5sum: {md5}\n"
        pkg_entry += f"SHA1: {sha1}\n"
        pkg_entry += f"SHA256: {sha256}\n"

        packages_content.append(pkg_entry)

    packages_str = "\n".join(packages_content) + ("\n" if packages_content else "")
    packages_path = os.path.join(REPO_DIR, "Packages")
    with open(packages_path, "w", encoding="utf-8") as f:
        f.write(packages_str)
    print(f"[+] Generato: {packages_path}")

    # Genera Packages.bz2
    packages_bz2_path = os.path.join(REPO_DIR, "Packages.bz2")
    with open(packages_bz2_path, "wb") as f:
        f.write(bz2.compress(packages_str.encode("utf-8")))
    print(f"[+] Generato: {packages_bz2_path}")

    # Genera Release
    pkg_md5, pkg_sha1, pkg_sha256 = hash_file(packages_path)
    pkg_size = os.path.getsize(packages_path)

    bz2_md5, bz2_sha1, bz2_sha256 = hash_file(packages_bz2_path)
    bz2_size = os.path.getsize(packages_bz2_path)

    release_str = f"""Origin: NavigatoreOSM Repo
Label: NavigatoreOSM
Suite: stable
Version: 1.1
Codename: ios
Architectures: iphoneos-arm
Components: main
Description: Repository Cydia Ufficiale per NavigatoreOSM (iPad Mini iOS 9.3.5)
MD5Sum:
 {pkg_md5} {pkg_size} Packages
 {bz2_md5} {bz2_size} Packages.bz2
SHA1:
 {pkg_sha1} {pkg_size} Packages
 {bz2_sha1} {bz2_size} Packages.bz2
SHA256:
 {pkg_sha256} {pkg_size} Packages
 {bz2_sha256} {bz2_size} Packages.bz2
"""
    release_path = os.path.join(REPO_DIR, "Release")
    with open(release_path, "w", encoding="utf-8") as f:
        f.write(release_str)
    print(f"[+] Generato: {release_path}")

if __name__ == "__main__":
    main()
