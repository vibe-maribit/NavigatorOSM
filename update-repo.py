#!/usr/bin/env python3
"""
update-repo.py: Genera gli indici APT per Cydia (Packages, Packages.bz2, Packages.gz, Release)
Supporta sia la struttura flat (root) che partitioned (dists/stable/main/binary-iphoneos-arm/)
risolvendo il problema del repository vuoto su Cydia (Issue #2).
"""

import os
import sys
import shutil
import hashlib
import bz2
import gzip
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

        # Assicurati che Filename inizi con ./ per i repository flat Cydia
        pkg_entry = control + "\n"
        pkg_entry += f"Filename: ./debs/{deb}\n"
        pkg_entry += f"Size: {size}\n"
        pkg_entry += f"MD5sum: {md5}\n"
        pkg_entry += f"SHA1: {sha1}\n"
        pkg_entry += f"SHA256: {sha256}\n"

        packages_content.append(pkg_entry)

    packages_str = "\n".join(packages_content) + ("\n" if packages_content else "")
    packages_bytes = packages_str.encode("utf-8")

    # 1. Genera Packages (non compresso)
    packages_path = os.path.join(REPO_DIR, "Packages")
    with open(packages_path, "wb") as f:
        f.write(packages_bytes)
    print(f"[+] Generato: {packages_path}")

    # 2. Genera Packages.bz2 (bzip2) - formato preferito da Cydia
    packages_bz2_path = os.path.join(REPO_DIR, "Packages.bz2")
    with open(packages_bz2_path, "wb") as f:
        f.write(bz2.compress(packages_bytes))
    print(f"[+] Generato: {packages_bz2_path}")

    # 3. Genera Packages.gz (gzip) - fallback universale APT
    packages_gz_path = os.path.join(REPO_DIR, "Packages.gz")
    with open(packages_gz_path, "wb") as f:
        f.write(gzip.compress(packages_bytes))
    print(f"[+] Generato: {packages_gz_path}")

    # 4. Genera Release (senza checksum inline per evitare conflitti hash su repo non firmati GPG)
    release_str = """Origin: NavigatoreOSM Repo
Label: NavigatoreOSM
Suite: stable
Version: 1.2
Codename: ios
Architectures: iphoneos-arm
Components: main
Description: Repository Cydia Ufficiale per NavigatoreOSM (iPad Mini iOS 9.3.5)
"""
    release_path = os.path.join(REPO_DIR, "Release")
    with open(release_path, "w", encoding="utf-8") as f:
        f.write(release_str)
    print(f"[+] Generato: {release_path}")

    # 5. Genera anche la struttura partitioned standard (dists/stable/main/binary-iphoneos-arm)
    # per compatibilità con client APT che interpretano 'stable main' invece di flat repo
    dists_binary_dir = os.path.join(REPO_DIR, "dists", "stable", "main", "binary-iphoneos-arm")
    os.makedirs(dists_binary_dir, exist_ok=True)

    # In dists, i percorsi sono relativi alla root del repository (quindi debs/ o pool/main/)
    shutil.copy2(packages_path, os.path.join(dists_binary_dir, "Packages"))
    shutil.copy2(packages_bz2_path, os.path.join(dists_binary_dir, "Packages.bz2"))
    shutil.copy2(packages_gz_path, os.path.join(dists_binary_dir, "Packages.gz"))

    dists_release_dir = os.path.join(REPO_DIR, "dists", "stable")
    shutil.copy2(release_path, os.path.join(dists_release_dir, "Release"))
    print(f"[+] Struttura dists/ generata con successo in {dists_binary_dir}")

    # Pool per dists
    pool_dir = os.path.join(REPO_DIR, "pool", "main")
    os.makedirs(pool_dir, exist_ok=True)
    for deb in deb_files:
        shutil.copy2(os.path.join(DEBS_DIR, deb), os.path.join(pool_dir, deb))
    print(f"[+] Copiati {len(deb_files)} pacchetti in {pool_dir}")

    print("[✓] Aggiornamento repository Cydia completato con successo!")

if __name__ == "__main__":
    main()
