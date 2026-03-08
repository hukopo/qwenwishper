# QwenWhisper

QwenWhisper is a native macOS menu bar app for Russian диктовка:

- press a global hotkey
- speak
- get local speech-to-text with Whisper
- optionally clean the text with a small local Qwen model
- paste the result into the active app

Everything is designed around a local, Apple Silicon-first workflow.

## What It Does

QwenWhisper is built for one concrete job: fast push-to-talk dictation into any macOS text field.

The pipeline is:

1. Record microphone audio.
2. Transcribe it locally with Whisper.
3. Rewrite the transcript locally with Qwen.
4. Paste the final text into the currently focused app.

The app also exposes diagnostics so you can inspect:

- the raw text after Whisper
- the rewritten text after Qwen
- recent logs for each pipeline step

## Current Status

This project is usable, but `v0.0.1` should be treated as an early preview release.

What already works:

- menu bar app shell
- global push-to-talk flow
- local Whisper transcription
- diagnostics and copyable logs
- showing text after Whisper and after Qwen/fallback
- automatic paste into the active field

Current limitation:

- when the app is built only with Command Line Tools / `swift run`, MLX may not have the Metal runtime it expects
- in that environment, Qwen rewrite is disabled automatically and the app falls back to Whisper output instead of crashing
- to ship a full Whisper + Qwen build cleanly, the next step is a proper Xcode `.app` build with MLX Metal resources

## Requirements

- macOS 14 or newer
- Apple Silicon Mac
- microphone permission
- Accessibility permission for paste injection

## Default Behavior

- Hotkey: `Command + Shift + Space`
- Whisper model: `base`
- Qwen model: `mlx-community/Qwen3.5-0.8B-OptiQ-4bit`
- Language: Russian-first
- Rewrite style: conservative post-editing of ASR text

## How To Use

1. Launch QwenWhisper.
2. Grant Microphone and Accessibility access on first run.
3. Focus any text field in any app.
4. Press the hotkey once to start recording.
5. Speak.
6. Press the hotkey again to stop.
7. Wait for transcription and paste.

In the menu bar popover you can inspect:

- `After Whisper`
- `After Qwen`
- recent logs

All of these text blocks are selectable and copyable from the UI.

## Model and Cache Locations

QwenWhisper stores runtime data in your user cache directory:

- models: `~/Library/Caches/QwenWhisper/Models`
- recordings: `~/Library/Caches/QwenWhisper/Recordings`
- logs: `~/Library/Caches/QwenWhisper/app.log`

## Development

Build:

```bash
swift build
```

Run:

```bash
swift run QwenWhisperApp
```

Tests:

```bash
swift build --build-tests
```

## Install From GitHub

Download the latest macOS build from Releases:

- `.dmg`: recommended install path
- `.zip`: alternative raw bundle download

Current release page:

- [v0.0.1](https://github.com/hukopo/qwenwishper/releases/tag/v0.0.1)

Install steps:

1. Download `QwenWhisper-<version>-macos-arm64.dmg`.
2. Open the DMG.
3. Drag `QwenWhisper.app` into `Applications`.
4. Launch the app.
5. Grant Microphone and Accessibility permissions.

If macOS blocks the first launch, use `Right Click -> Open`.

## Release Packaging

To produce a local `.app` bundle and distributable archives:

```bash
./scripts/package_release.sh 0.0.1
```

This creates:

- `dist/QwenWhisper.app`
- `dist/QwenWhisper-0.0.1-macos-arm64.zip`
- `dist/QwenWhisper-0.0.1-macos-arm64.dmg`

For signing and notarization, see [docs/releasing.md](docs/releasing.md).

## Troubleshooting

### “No speech was detected”

Check:

- microphone permission is granted
- the menu bar app is actually recording
- the `After Whisper` field updates
- `~/Library/Caches/QwenWhisper/app.log` contains the latest run

### Qwen rewrite is unavailable

If the `Qwen` model shows failed or the logs mention missing MLX Metal shaders, the app is running in a Whisper-only fallback mode. That is expected for the current Command Line Tools-based environment.

## Notes

- `swift test` in this environment still requires a full Xcode installation. With Command Line Tools only, test targets build, but the runner cannot start correctly.
- launch-at-login is most reliable from a proper `.app` bundle.
- signed and notarized release automation is prepared in `.github/workflows/release.yml`, but real notarized releases still require your Apple Developer signing credentials in GitHub repository secrets.
