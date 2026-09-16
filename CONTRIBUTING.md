# Contributing to NavigatorOSM

Thank you for your interest in contributing to **NavigatorOSM**!  
Our mission is to breathe new life into obsolete Apple iPads (iPad Mini 1, iPad 2/3/4 running iOS 9.3.5) by transforming them into high-performance, fluid in-car GPS navigators.

---

## 🌟 Ways to Contribute

There are many ways you can contribute to NavigatorOSM:
1. **Report Bugs**: Help us find issues, crashes, or rendering glitches on legacy iOS hardware.
2. **Suggest Features**: Propose UX or navigation improvements tailored for in-car dashboard use.
3. **Add Translations**: Help make NavigatorOSM accessible in more languages.
4. **Submit Code**: Improve routing logic, UI components, Android GPS tethering, or performance.

---

## 🌐 Adding New Languages & Translations

NavigatorOSM is designed from the ground up for lightweight, community-driven localization. All strings are centralized in [`NavigatoreOSM/Services/LocalizationManager.m`](NavigatoreOSM/Services/LocalizationManager.m).

To add a new language (e.g. Spanish, German, French):
1. In `LocalizationManager.h`, add the new language code to `AppLanguage` enum (e.g. `AppLanguageSpanish`).
2. In `LocalizationManager.m`, add the language mapping in `+ (instancetype)sharedManager`.
3. In `tableForLanguage:`, add the dictionary containing translations for the keys.
4. Add the language option to the segmented control in [`SettingsViewController.m`](NavigatoreOSM/Controllers/SettingsViewController.m).
5. Open a Pull Request!

---

## 🛠️ Development & Build Setup

NavigatorOSM targets **iOS 9.3.5** on **32-bit armv7** hardware with an Apple A5/A6 chip.

Because modern macOS / Xcode no longer ships the 32-bit `armv7` toolchain or iOS 9 SDK, we build using a Dockerized **Theos** environment:

```bash
# 1. Clone repository
git clone https://github.com/vibe-maribit/NavigatorOSM.git
cd NavigatorOSM

# 2. Build .deb package via Docker
docker run --rm -v "$PWD:/project" -w /project cauan/theos make package DEBUG=0 messages=no

# 3. Or build the signed .ipa directly
./package-ipa.sh

# 4. Install over USB to a connected jailbroken iPad
./install-usb.sh
```

For full details, read [docs/04_BUILD_AND_DEVELOPMENT_GUIDE.md](docs/04_BUILD_AND_DEVELOPMENT_GUIDE.md).

---

## 📜 Coding Guidelines

Please adhere to the following principles when contributing code:

- **Strict iOS 9.3 Compatibility**: Do not use APIs introduced in iOS 10 or later without runtime checks (`respondsToSelector:`, `@available`, or `NSClassFromString`).
- **Memory Footprint (< 25 MB RAM)**: iPad Mini 1 only has 512 MB of total system RAM. Avoid heavy background allocations, memory leaks, and retain cycles.
- **Pure Native Objective-C**: Keep the app 100% native with MapKit, CoreLocation, and UIKit. No WebKit wrappers.
- **60 FPS GPU Rendering**: Heavy calculations should be dispatched to background queues (`dispatch_async`) to keep the main UI thread buttery smooth.

---

## 🔀 Pull Request Process

1. **Fork** the repository and create your branch from `develop` (`git checkout -b feature/my-cool-feature`).
2. **Commit** your changes using clear, conventional commit messages:
   - `feat: ...` for new features
   - `fix: ...` for bug fixes
   - `docs: ...` for documentation updates
   - `i18n: ...` for localization updates
3. **Verify** that the app compiles cleanly with Docker Theos (`./package-ipa.sh`).
4. **Push** to your fork and submit a **Pull Request** targeting the `develop` branch.
5. Provide a clear summary in your PR description explaining what changed and how it was tested.

---

## 💬 Community & Questions

- Have a question or idea? Open a [GitHub Discussion](https://github.com/vibe-maribit/NavigatorOSM/discussions) or submit an [Issue](https://github.com/vibe-maribit/NavigatorOSM/issues).
- Please ensure all interactions follow our [Code of Conduct](CODE_OF_CONDUCT.md).
