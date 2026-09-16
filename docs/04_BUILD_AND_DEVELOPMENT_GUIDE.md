# 04 - Build & Development Guide (Linux & Docker)

This guide explains how the build environment is architected to compile native 32-bit `armv7` Objective-C code for iOS 9.3.5 entirely on Linux or macOS using Docker, with zero reliance on legacy Mac hardware.

---

## 1. Cross-Compilation Toolchain Overview

Apple deprecated and removed 32-bit `armv7` compilation targets starting with Xcode 14, making it impossible to compile software for Apple A5 devices (iPad Mini 1, iPad 2/3, iPhone 4S) on modern macOS installations or GitHub-hosted macOS runners.

To solve this, our pipeline leverages the containerized **Theos** toolchain (`cauan/theos`):
- **Cross-Compiler**: `armv7-apple-darwin11-clang` (LLVM Clang targeting Mach-O armv7 Darwin).
- **Target SDK**: `iPhoneOS9.3.sdk` (providing all native header definitions for `UIKit`, `MapKit`, `CoreLocation`, `AVFoundation`, and `AudioToolbox`).
- **Linker & Ad-Hoc Signer**: `armv7-apple-darwin11-ld` and `ldid` for ad-hoc pseudo-signing without needing a paid Apple Developer certificate.
- **Symbol Stripping**: `strip -x` to minimize the binary footprint to just a few hundred kilobytes.

---

## 2. Building the Project

### 2.1 Compiling the `.ipa` Package
To compile all Objective-C source files and package `NavigatoreOSM.ipa`, run:

```bash
cd /path/to/NavigatoreOSM
./package-ipa.sh
```

#### What `package-ipa.sh` Executes:
1. Mounts the project root inside the Docker container:
   ```bash
   docker run --rm -v "$PWD:/project" -w /project cauan/theos make clean all DEBUG=0 messages=no
   ```
2. Compiles every `.m` translation unit with `-O2` compiler optimizations and `-arch armv7`.
3. Creates the standard iOS payload bundle directory: `Payload/NavigatoreOSM.app`.
4. Copies the compiled Mach-O binary, asset icons, and `Info.plist`.
5. Embeds the code signatures in `_CodeSignature/CodeResources` and zips the bundle into `NavigatoreOSM.ipa`.

### 2.2 Compiling the Cydia `.deb` Package
To generate the Debian package for Cydia installation:

```bash
docker run --rm -v "$PWD:/project" -w /project cauan/theos make package DEBUG=0 messages=no
```
The output `.deb` will be placed in the `packages/` directory (e.g., `packages/com.maribit.navigatoreosm_1.2.2_iphoneos-arm.deb`).

---

## 3. Cydia Repository Management

The `cydia_repo/` directory contains all files required to host an APT/Cydia repository over HTTP/HTTPS or GitHub Pages:

```
cydia_repo/
├── CydiaIcon.png        # 58x58 repository icon displayed in Cydia
├── debs/                # Debian package archives (.deb)
│   └── com.maribit.navigatoreosm_1.2.2_iphoneos-arm.deb
├── Packages             # APT metadata index with byte sizes and checksums
├── Packages.bz2         # Bzip2-compressed index (required by Cydia)
├── Packages.gz          # Gzip-compressed index
├── Release              # Repository metadata (Origin, Label, Suite, Architecture)
├── index.html           # Web showcase & 1-tap Cydia add button
├── isrgrootx1.crt       # Root CA certificate profile for iOS 9 Safari
└── update-repo.py       # Automated repository index generator
```

### Updating Repository Indices
Whenever a new `.deb` package is added or updated:
```bash
python3 cydia_repo/update-repo.py
```
This script automatically parses package `control` fields, computes SHA256/SHA1/MD5 checksums, builds `Packages`, and generates `Packages.bz2` and `Release` files.

### Testing Locally Over LAN
You can spin up an instant local HTTP server for Cydia testing on your local network:
```bash
cd cydia_repo
python3 -m http.server 8088
```
Then add `http://<YOUR_LAN_IP>:8088/` as a Cydia source on your iPad.

---

## 4. Codebase Structure & Adding New Classes

All native iOS source files are organized cleanly in `NavigatoreOSM/`:

```
NavigatoreOSM/
├── main.m
├── AppDelegate.h / .m
├── Controllers/
│   ├── NavigationViewController.h / .m   # Main navigation coordinator & map delegate
│   └── SettingsModalViewController.h / .m # Non-blocking settings modal
├── Models/
│   ├── RouteInfo.h / .m                  # Route data & step representations
│   └── POIItem.h / .m                    # POI entity model
├── Overlays/
│   ├── OSMTileOverlay.h / .m             # OSM & Esri Dark raster map overlays
│   └── TrafficTileOverlay.h / .m         # Real-time traffic flow overlay
├── Services/
│   ├── RoutingService.h / .m             # OSRM driving engine integration
│   ├── VoiceGuidanceService.h / .m       # AVSpeechSynthesizer audio guidance
│   ├── NetworkGPSReceiver.h / .m         # Asynchronous UDP 8888 GPS listener
│   └── OverpassService.h / .m            # Overpass API POIs & dynamic speed limits
└── Views/
    ├── ManeuverHUDView.h / .m            # Turn-by-turn Emerald card + subcard
    ├── ModernTripBarView.h / .m          # Floating bottom trip bar
    ├── SpeedometerView.h / .m            # Circular gauge + dynamic speed limits
    └── RouteSelectorView.h / .m          # Bottom multi-route alternative drawer
```

### Adding New Source Files
When adding a new `.m` file to the project, register it in the `NavigatoreOSM_FILES` variable within [`Makefile`](file:///home/nicola/Devel/retrofit/iOS/NavigatoreOSM/Makefile):

```makefile
NavigatoreOSM_FILES = NavigatoreOSM/main.m \
                      NavigatoreOSM/AppDelegate.m \
                      NavigatoreOSM/Controllers/NavigationViewController.m \
                      NavigatoreOSM/Views/YourNewView.m
```

---

## 5. Automated CI/CD Workflows

### 5.1 Build & Release Workflow (`.github/workflows/build-ipa.yml`)
Triggers on every tagged release (`v*`) or push to `develop`:
- Spins up an Ubuntu runner with Docker.
- Runs `cauan/theos` to build the `armv7` binary.
- Packages `NavigatoreOSM.ipa` and the `.deb` archive.
- Attaches the binaries directly to the GitHub Release.

### 5.2 GitHub Pages Deployment Workflow
Whenever changes are pushed to `cydia_repo/`, the updated catalog is served directly via GitHub Pages at:
```
https://vibe-maribit.github.io/NavigatorOSM/
```
Deploying to `gh-pages` is executed via:
```bash
git subtree split --prefix cydia_repo -b gh-pages-split
git push origin gh-pages-split:gh-pages --force
git branch -D gh-pages-split
```
