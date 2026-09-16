# 02 - Installation & Jailbreak Guide (iOS 9.3.5)

This guide walks you through preparing your **iPad Mini 1 (MD528TY/A / A1432 - iOS 9.3.5 Build 13G36)** and deploying **NavigatoreOSM** using three different installation approaches.

---

## 1. Hardware & System Requirements

- **Supported Devices**: 
  - iPad Mini 1st Gen (A1432 Wi-Fi / A1454 / A1455 Cellular)
  - iPad 2, iPad 3, iPad 4
  - iPhone 4S, iPhone 5, iPhone 5C, iPod Touch 5th Gen
- **Operating System**: iOS 9.3.5 (13G36) or iOS 9.3.6 (13G37).
- **USB Cable**: Standard Apple Lightning to USB data cable.
- **Host PC (for USB deployment)**: Linux (Ubuntu, Debian, Arch, Fedora) or macOS with `ideviceinstaller` and `libimobiledevice`.

---

## 2. Why Jailbreaking is Recommended for Retrofitting

On stock (unmodified) iOS devices:
- Sideloading with a free Apple Developer account enforces a strict **7-day certificate expiration**. After 7 days, the app crashes on launch until re-signed and re-installed.
- For a dedicated, dashboard-mounted car navigator, having to take the tablet out of the vehicle every week to re-sign apps is impractical.

**With Jailbreak and the AppSync Unified tweak:**
- iOS permanently accepts ad-hoc unsigned or self-signed `.ipa` and `.deb` binaries.
- The app remains installed **forever** with no expiration date.
- You can install and update the application Over-The-Air (OTA) directly from Cydia or in under 5 seconds over USB!

---

## 3. Jailbreak Procedure for iOS 9.3.5 (Takes ~3 Minutes)

Two mature semi-untethered jailbreaks exist for 32-bit A5 devices on iOS 9.3.5:
1. **kok3shi9** (Recommended for speed and stability, created by dora2ios).
2. **Phoenix** (Created by Siguza and tihmstar).

### Step-by-Step Jailbreak:
1. Download the `.ipa` for **kok3shi9** or **Phoenix** from their respective official repositories.
2. Sideload the IPA onto your iPad using [Sideloadly](https://sideloadly.io) (available for macOS and Windows) or via [Legacy iOS Kit](https://github.com/LukeZGD/Legacy-iOS-Kit) on Linux.
3. Open the jailbreak app on your iPad, tap **"Jailbreak"** (or "Kickstart Jailbreak"), and wait for the SpringBoard to restart (*respring*).
4. The brown **Cydia** icon will now appear on your iPad Home screen.

> [!NOTE]
> Semi-untethered jailbreaks need to be re-activated if the tablet completely powers off. Simply reopen the jailbreak app and tap **"Kickstart Jailbreak"**. All apps and tweaks remain intact.

---

## 4. Crucial Prerequisite: Modern SSL Root Certificates (Fixing HTTPS on iOS 9)

In September 2021, the original *DST Root CA X3* certificate expired. Because iOS 9 stopped receiving updates in 2016, modern HTTPS connections (including GitHub Pages and Cydia repos) will fail with SSL handshake errors unless you install the modern root certificate:

1. On your iPad Mini, open Safari and navigate to:
   ```
   https://vibe-maribit.github.io/NavigatorOSM/isrgrootx1.crt
   ```
   *(Or download the certificate profile directly from [cydia.invoxiplaygames.uk/certificates](http://cydia.invoxiplaygames.uk/certificates/))*.
2. Tap **Install** in the Settings prompt to install the **ISRG Root X1** CA certificate.
3. Your legacy iPad can now securely communicate with modern HTTPS endpoints and GitHub Pages!

---

## 5. Installation Method 1: OTA via Cydia Repository (Easiest)

Once your iPad is jailbroken and has Cydia:

1. Launch **Cydia** on your iPad.
2. Tap **Sources** at the bottom navigation bar.
3. Tap **Edit** (top right) and then **Add** (top left).
4. Enter the official GitHub Pages repository URL:
   ```
   https://vibe-maribit.github.io/NavigatorOSM/
   ```
   *(If deploying from a local development computer on the same Wi-Fi, you can also use `http://<YOUR_COMPUTER_IP>:8088/`)*.
5. Tap **Add Source** and wait for Cydia to refresh its package catalog.
6. Tap the new **NavigatorOSM Repository** source, select **Navigation**, and tap **NavigatorOSM**.
7. Tap **Install** (top right) -> **Confirm**.
8. Cydia will download the Debian package, unpack it into `/Applications/NavigatoreOSM.app`, and automatically register the icon with SpringBoard.

---

## 6. Installation Method 2: 1-Command USB Sideload (Linux & macOS)

If you have a Linux or Mac workstation and want to flash the IPA over a Lightning cable:

1. Ensure **AppSync Unified** is installed from Cydia:
   - Add `https://cydia.akemi.ai/` to your Cydia sources.
   - Install **AppSync Unified** and respring.
2. Connect the iPad Mini to your computer via USB.
3. If prompted with *"Trust this computer?"* on the iPad screen, tap **Trust** and enter your device passcode.
4. Run the automated installer script:
   ```bash
   git clone https://github.com/vibe-maribit/NavigatorOSM.git
   cd NavigatorOSM
   ./install-usb.sh
   ```

### What `install-usb.sh` Does Under the Hood:
- Automatically detects Linux vs macOS (`Darwin`).
- Detects the correct CLI syntax (`ideviceinstaller install` vs `ideviceinstaller -i`).
- Verifies communication with the device via `usbmuxd` and `ideviceinfo`.
- Flashes `NavigatoreOSM.ipa` directly into the iOS sandbox in under 5 seconds.

---

## 7. Installation Method 3: Non-Jailbroken Devices (Stock iOS)

If you prefer not to jailbreak your iPad:
1. Download **Sideloadly** from [sideloadly.io](https://sideloadly.io).
2. Download `NavigatoreOSM.ipa` from [GitHub Releases](https://github.com/vibe-maribit/NavigatorOSM/releases).
3. Connect the iPad via USB, drag `NavigatoreOSM.ipa` into Sideloadly, enter your Apple ID, and click **Start**.
4. On the iPad, go to *Settings > General > Device Management*, trust your developer certificate, and launch the app.
5. *(Note: Must be re-signed every 7 days unless using a paid developer account).*

---

## 8. Troubleshooting & Common Issues

### Issue: `ERROR: No device found!`
1. Ensure the Lightning cable supports data transfer (some cheap cables are charge-only).
2. Connect directly to a motherboard USB port, bypassing unpowered USB hubs.
3. On Linux, restart the usbmux daemon:
   ```bash
   sudo systemctl restart usbmuxd
   ```
4. Verify device detection with `ideviceinfo`.

### Issue: `Device is locked with a passcode`
Unlock your iPad screen before executing `./install-usb.sh`.

### Issue: `ApplicationVerificationFailed (0xe800801c / 0xe8008015)`
The iOS installation daemon (`installd`) rejected the package signature:
1. **Jailbroken iPad**: Verify that **AppSync Unified** is installed. If the device was rebooted, re-run **kok3shi9** or **Phoenix** to re-enable the jailbreak environment.
2. **Stock iPad**: You cannot install ad-hoc unsigned IPAs over USB on stock iOS. Use **Sideloadly** (Method 3) to sign the app with your Apple ID.

### Issue: Cydia Fails with SSL Handshake or "Cannot Connect to Repository"
Ensure the **ISRG Root X1** root certificate is installed as explained in Section 4.
