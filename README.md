# QwenWhisper

A macOS menu bar app for dictation and live translation. Speech is recognized by Whisper, the text is cleaned up by a small Qwen model, and everything runs on your Mac.

Press the hotkey, talk, press it again. The text is pasted into whatever field is active.

Live translation works the same way, from the microphone or from system audio, and shows the result in the menu bar popover.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- About 1 GB of disk for the default models (downloaded on first use)

## Install

```bash
brew install --cask hukopo/tap/qwenwhisper
```

Or grab the DMG from [Releases](https://github.com/hukopo/qwenwishper/releases/latest) and run `Install QwenWhisper.command` inside it.

The app is not signed. If you copied it by hand and macOS says it is damaged, run:

```bash
xattr -cr /Applications/QwenWhisper.app
```

## Permissions

- **Microphone**: for dictation.
- **Accessibility**: to paste text. After every update macOS drops this permission. Remove QwenWhisper in System Settings > Privacy & Security > Accessibility and grant it again from the app settings.
- **Screen Recording**: only for live translation from system audio.

## Usage

- `⌘⇧Space` starts and stops recording. You can change it in Settings.
- Live translation is started from the menu bar icon.
- The popover shows the raw Whisper text, the Qwen result and recent logs.

## Models

| Model | Size | Notes |
|-------|------|-------|
| Whisper Base | ~75 MB | fastest, weaker on Russian |
| Whisper Small (default) | ~240 MB | good balance |
| Qwen3.5 0.8B (default) | ~620 MB | fast cleanup and translation |
| Qwen3.5 2B | ~1.7 GB | better quality, slower |

Any other WhisperKit or MLX model can be set via "Custom" in Settings. Qwen can be turned off entirely if you only want raw Whisper output.

## Troubleshooting

- **Nothing gets pasted**: re-grant Accessibility (see above), or raise the paste delay in Settings.
- **No text transcribed**: check the microphone permission and the logs in the popover.
- **System audio translation won't start**: grant Screen Recording and restart the app.
- **First run is slow**: models are downloading. Later runs load from cache.

## Build

```bash
swift build -c release --target QwenWhisperApp
swift run QwenWhisperApp
swift test                                  # needs full Xcode
./scripts/package_release.sh 0.4.0          # app, zip and dmg in dist/
```

Signing and notarization: [docs/releasing.md](docs/releasing.md).

## License

MIT
