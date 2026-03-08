# QwenWhisper

Native macOS menu bar utility for push-to-talk dictation:

1. Hold the global hotkey.
2. Speak in Russian.
3. Release the hotkey.
4. The app transcribes with Whisper locally, rewrites with Qwen locally, and pastes the result into the active app.

## Stack

- SwiftUI/AppKit menu bar app
- AVAudioEngine for microphone capture
- WhisperKit for local speech-to-text
- MLX + MLX Swift LM for local Qwen inference

## Defaults

- Whisper model: `base`
- Qwen model: `mlx-community/Qwen3.5-0.8B-OptiQ-4bit`
- Default hotkey: `Command + Shift + Space`
- Output language: Russian-first
- Rewrite mode: aggressive but meaning-preserving

## Build

```bash
swift build
```

## Run

```bash
swift run QwenWhisperApp
```

On first launch, grant:

- Microphone access
- Accessibility access

The app downloads models into `~/Library/Caches/QwenWhisper/Models`.

## Notes

- `swift test` currently requires a full Xcode installation in this environment. With Command Line Tools only, test compilation succeeds but the runner cannot start because `xcrun --show-sdk-platform-path` fails.
- For launch-at-login registration, run the app from a proper `.app` bundle opened in Xcode or built from Xcode.
