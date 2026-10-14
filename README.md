<p align="center">
  <img src="assets/logo.png" alt="Audio Splitter Logo" width="160" />
</p>

<h1 align="center">Audio Splitter for macOS</h1>

<p align="center">
  A modern, lightweight, and blazingly fast macOS utility to slice and segment audio files using Apple's native <b>AVFoundation</b> framework.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2012.0+-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20(arm64)-black" alt="Architecture" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---

## 🌟 Key Features

- ⚡ **Native AVFoundation Engine**: Powered by Apple's AVFoundation for ultra-fast, lossless audio trimming with minimal CPU and battery usage.
- 🎯 **Dual Splitting Modes**:
  - **Equal Parts**: Automatically divides the audio track into *N* evenly sized segments.
  - **Fixed Duration**: Splits the audio file into custom intervals (e.g., every 5 minutes, 10 minutes).
- 🔁 **Smart Overlap Support**: Add an optional overlap duration (in seconds) between adjacent segments so sentences or musical phrases don't get abruptly cut off.
- 📂 **Drag & Drop & Batch Processing**: Effortlessly drag and drop multiple `.m4a` files directly into the window.
- 📁 **Custom Output Directory**: Choose where your processed audio segments are saved.
- 📊 **Real-time Progress Indicator**: Track the status and progress percentage while splitting.

---

## 📥 Download & Installation

### 1. Download
Head over to the [**Releases**](../../releases) tab on GitHub and download the latest installer:
```
Audio_Splitter_Installer.dmg
```

### 2. Installation
1. Double-click to open `Audio_Splitter_Installer.dmg`.
2. Drag the **Audio Splitter** icon into your **Applications** folder.

---

### ⚠️ First-Time Launch (macOS Gatekeeper)

Because this app is distributed directly via GitHub rather than the Mac App Store, macOS Gatekeeper may show a warning on first launch:
> *"Audio Splitter can't be opened because Apple cannot check it for malicious software"*

**How to open (one-time step):**
1. Open your **Applications** folder in Finder.
2. **Right-click (or Control + Click)** on **Audio Splitter**.
3. Select **Open** from the context menu.
4. Click **Open** in the confirmation dialog.

> *Alternatively, go to **System Settings** > **Privacy & Security**, scroll down to the Security section, and click **"Open Anyway"**.*

---

## 🚀 How to Use

1. **Add Audio Files**: Drag & drop `.m4a` files onto the application window, or click the browse button to select files.
2. **Configure Split Settings**:
   - Select either **Equal Parts** or **Fixed Duration**.
   - (Optional) Set the **Overlap Duration** in seconds.
3. **Select Output Destination**: Pick your target folder for the exported clips.
4. **Click Split Audio**: Sit back and let the app process your files in seconds!

---

## 🛠️ For Developers

### Prerequisites
- macOS 12+ with Xcode installed
- Flutter SDK (or [FVM](https://fvm.app/))

### Run Locally
```bash
# Clone the repository
git clone https://github.com/your-username/audio-splitter.git
cd audio-splitter

# Fetch Flutter dependencies
flutter pub get

# Run on macOS desktop
flutter run -d macos
```

### Package DMG Installer
A convenient build script [create_installer.sh](create_installer.sh) is included to compile and package the release application into a clean `.dmg` installer:

```bash
# Build release and generate DMG installer
./create_installer.sh --build
```
The installer will be generated at `Audio_Splitter_Installer.dmg`.

---

## 📄 License
This project is open-source and released under the [MIT License](LICENSE).
