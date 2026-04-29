# QwenWhisper

> Push-to-talk dictation for macOS — transcribed locally with Whisper, cleaned up with Qwen 3.5.

QwenWhisper is a lightweight macOS menu bar app that lets you dictate text into any app using a global hotkey. Audio is processed entirely **on-device** with Apple Silicon: no cloud, no subscription, no data leaving your Mac.

**Pipeline:**
1. Press hotkey → start recording
2. Press hotkey again → stop recording
3. [Whisper] transcribes audio locally
4. [Qwen 3.5] rewrites and cleans up the transcript
5. Result is pasted into the active text field automatically

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **Mac** | Apple Silicon (M1 or newer) |
| **macOS** | 14 Sonoma or newer |
| **RAM** | 4 GB minimum; 8 GB recommended for Qwen 3.5 2B |
| **Storage** | ~1–3 GB for models (downloaded on first use) |

---

## Installation

### Option A — Homebrew (recommended)

```bash
brew install --cask hukopo/tap/qwenwhisper
```

Homebrew handles the quarantine attribute automatically — no "damaged app" dialogs.

To update later:
```bash
brew upgrade --cask qwenwhisper
```

### Option B — DMG

1. Go to [**Releases**](https://github.com/hukopo/qwenwishper/releases/latest) and download `QwenWhisper-<version>-macos-arm64.dmg`
2. Open the DMG
3. Double-click **"Install QwenWhisper.command"** — Terminal opens, the app is copied to `/Applications` and the quarantine attribute is removed automatically
4. Launch `QwenWhisper` from Spotlight or Applications

> **Alternatively:** drag `QwenWhisper.app` into Applications manually, then if macOS says the app is "damaged", run this once in Terminal:
> ```bash
> xattr -cr /Applications/QwenWhisper.app
> ```

> The app is not code-signed. macOS 12+ shows a "damaged" error (not just "unidentified developer") for unsigned apps downloaded from the internet — `xattr -cr` removes the quarantine flag that causes this.

---

## Permissions

QwenWhisper needs three permissions to work. All processing stays local.

### 1. Microphone

Required to record your voice. macOS will prompt automatically on first recording.

### 2. Accessibility (Universal Access)

Required to paste text into the active app. macOS prompts on first launch.

Open **Settings → General → Request Accessibility** to prompt again.

> ⚠️ **After updating or reinstalling the app**, macOS invalidates the Accessibility permission and the app loses the ability to paste.
>
> **Fix:** Open **System Settings → Privacy & Security → Accessibility**, remove QwenWhisper from the list, then click **Request Accessibility** in the app settings again.

### 3. Files & Folders (Documents Access)

Required for model storage access. macOS may prompt automatically.

Open **Settings → General → Request Documents Access** to open the relevant Privacy pane.

---

## First Launch

On first launch the app will:

- Appear as an icon in the **menu bar**
- Ask whether to **launch at login** (recommended)
- Request **Microphone** access
- Request **Accessibility** access

When you first use a model, it is downloaded automatically:

| Model | Size | First-use download |
|-------|------|--------------------|
| Whisper Small | ~240 MB | Yes, once |
| Qwen 3.5 0.8B | ~450 MB | Yes, once |
| Qwen 3.5 2B | ~1.2 GB | Yes, once |

> **Slow the first time?** Qwen downloads the model on first use. Subsequent launches load from local cache in a few seconds.

---

## Usage

| Action | How |
|--------|-----|
| Start recording | Press **⌘⇧Space** (default hotkey) |
| Stop recording | Press hotkey again |
| View transcription | Click the menu bar icon → **Texts** section |
| Copy last result | Click the copy button in the Texts section |
| Open Settings | Click menu bar icon → **Settings** |

You can change the global hotkey to any supported key combination in **Settings → General**.

The menu bar popover shows:

- **After Whisper** — raw transcription
- **After Qwen** — cleaned-up final text (when Qwen is enabled)
- **Model status** — Whisper and Qwen load states
- **Recent logs** — last pipeline steps

---

## Settings

Open **Settings** from the menu bar popover.

### General

| Setting | Description |
|---------|-------------|
| **Hotkey** | Assign any global push-to-talk key combination |
| **Launch at login** | Start QwenWhisper automatically with macOS |
| **Enable Qwen rewriting** | Toggle Qwen post-processing; disable for Whisper-only mode |
| **Enable logging** | Write detailed logs for debugging |
| **Paste delay** | Delay (ms) before pasting — increase if the target app misses the paste |
| **Max recording** | Maximum recording duration in seconds |

### Models & Storage

Choose Whisper and Qwen model sizes. Larger models are slower but more accurate.

| Whisper | Size | Best for |
|---------|------|----------|
| Base | ~75 MB | Low-latency, quiet conditions |
| **Small** *(default)* | ~240 MB | Everyday dictation |
| Medium | ~750 MB | Maximum accuracy |

| Qwen | Size | Best for |
|------|------|----------|
| Qwen 3.5 0.8B | ~450 MB | Fast rewriting |
| **Qwen 3.5 2B** *(default)* | ~1.2 GB | Best balance |
| Qwen 3.5 4B | ~2.3 GB | Highest quality |

### Prompt

Manage multiple Qwen prompt presets, switch the active preset from a picker, and preview the rewrite result on sample text before dictating. The default preset is tuned for Russian dictation post-editing, and all changes are saved automatically.

---

## Troubleshooting

### "App is damaged and can't be opened" / "Приложение повреждено"

macOS 12+ shows this for unsigned apps downloaded from the internet. Right-click → Open does **not** work for this specific error.

**Recommended fix — use the installer in the DMG:**
Double-click **"Install QwenWhisper.command"** inside the DMG. It removes the quarantine flag automatically.

**Manual fix:**
```bash
xattr -cr /Applications/QwenWhisper.app
```

Run this once in Terminal after moving the app to Applications. The app will open normally afterwards.

---

### App can't paste text / Accessibility missing

**Fix:**
1. Open **System Settings → Privacy & Security → Accessibility**
2. If QwenWhisper is listed — remove it with **–**
3. In the app: **Settings → General → Request Accessibility**
4. Approve the system dialog

> This is always required after an app update or reinstall.

---

### Qwen is slow the first time

The model is downloaded (~0.5–1.2 GB) on first use. This is a one-time step. Subsequent loads take a few seconds from local cache.

If Qwen still reloads slowly on every recording, check the **Diagnostics** window for errors.

---

### "No text was transcribed"

- Check that **Microphone** permission is granted
- Check the **After Whisper** field in the menu bar popover
- Look at **Recent Logs** — it shows per-step timing and error messages
- Make sure you recorded for at least 0.5 seconds

---

### Files & Folders permission dialog keeps appearing

Open **Settings → General → Request Documents Access** to navigate directly to the relevant Privacy pane and grant access permanently.

---

## Building from Source

### Requirements

- macOS 14+
- Xcode 16+ **or** Swift 6 toolchain
- Apple Silicon Mac

### Clone and Build

```bash
git clone https://github.com/hukopo/qwenwishper.git
cd qwenwishper
swift build -c release --target QwenWhisperApp
```

### Run in Development

```bash
swift run QwenWhisperApp
```

### Tests

```bash
swift test
```

### Build a Release DMG

```bash
./scripts/package_release.sh 0.2.2
```

Produces:

```
dist/
  QwenWhisper.app
  QwenWhisper-0.2.2-macos-arm64.zip
  QwenWhisper-0.2.2-macos-arm64.dmg
```

For signed and notarized releases, see [docs/releasing.md](docs/releasing.md).

---

## Project Structure

```
Sources/
  QwenWhisperApp/        # Main SwiftUI app
    App/                 # AppController, entry point
    Models/              # AppSettings, ModelCatalog
    Services/            # Whisper, Qwen, audio, paste
    Views/               # SwiftUI views
  WhisperBridge/         # WhisperKit wrapper
  WhisperProbe/          # CLI diagnostic tool
scripts/
  package_release.sh     # Build + package DMG
  notarize_release.sh    # Notarization helper
docs/
  releasing.md           # Release process guide
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | On-device speech recognition |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | Apple Silicon ML framework |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | LLM inference (Qwen 3.5 support) |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | HuggingFace Hub model download |

---

## Contributing

Pull requests are welcome. For larger changes, please open an issue first to discuss the approach.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a Pull Request

---

## License

MIT License — see [LICENSE](LICENSE) for details.
