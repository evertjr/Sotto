<p align="center">
  <img src="icon.png" width="128" height="128" alt="Sotto">
</p>

<h1 align="center">Sotto</h1>
<p align="center">The simplest voice dictation for macOS.</p>

---

Sotto is a local-first voice dictation app for macOS. Press a shortcut, speak, and the transcribed text is typed wherever your cursor is. No account, no cloud, no subscription. Everything runs on your Mac.

## How it works

1. Set a global keyboard shortcut
2. Hold the shortcut and speak
3. Release to transcribe and insert the text

Sotto lives in your menu bar and stays out of your way. A floating waveform pill appears while recording so you know it's listening.

## Features

- **Two transcription engines** built in: [WhisperKit](https://github.com/argmaxinc/WhisperKit) (99+ languages) and [Parakeet](https://github.com/FluidInference/FluidAudio) (fast, 25 languages)
- **Fully local** processing using CoreML on Apple Silicon
- **Apple Intelligence integration** to optionally polish transcriptions (fix grammar, format lists) or translate to another language using the on-device language model
- **Live waveform** with aurora-style animated visualization during recording
- **Customizable** with 7 waveform color presets, configurable shortcuts, and input device selection
- **Lightweight** menu bar app with no dock icon and launch-at-login support
- **Localized** in English, German, Spanish, French, Japanese, Portuguese (BR), and Simplified Chinese

## Requirements

- macOS 26 or later
- Apple Silicon Mac
- Microphone and Accessibility permissions
- Apple Intelligence enabled (optional, for polish and translate features)

## Models

| Model | Engine | Size | Speed | Languages |
|-------|--------|------|-------|-----------|
| Whisper Tiny | WhisperKit | ~39 MB | Very fast | 99+ |
| Whisper Base | WhisperKit | ~74 MB | Fast | 99+ |
| Whisper Small | WhisperKit | ~244 MB | Moderate | 99+ |
| Whisper Large Turbo | WhisperKit | ~800 MB | Slower | 99+ |
| Whisper Large v3 | WhisperKit | ~1.5 GB | Slowest | 99+ |
| Parakeet v2 | FluidAudio | ~600 MB | Very fast | English |
| Parakeet v3 | FluidAudio | ~600 MB | Very fast | 25 European |

Models are downloaded on first use and stored locally. The app recommends a model based on your hardware during onboarding.

## Building from source

1. Clone the repo
2. Open `Sotto.xcodeproj` in Xcode 26+
3. Xcode will resolve the Swift Package dependencies (WhisperKit, FluidAudio, Sparkle)
4. Build and run

The app requires hardened runtime with the `com.apple.security.device.audio-input` entitlement. Sandbox is disabled because global hotkeys and accessibility-based text insertion are not possible in sandboxed apps.

## Contributing

Issues and pull requests are welcome. If you find a bug or have a feature idea, open an issue first so we can discuss it before you invest time on a PR.

To contribute code:

1. Fork the repo
2. Create a branch from `main`
3. Make your changes and test locally
4. Open a pull request with a clear description of what changed and why

## License

MIT
