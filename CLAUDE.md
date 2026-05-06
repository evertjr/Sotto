# Sotto

Minimal voice dictation for macOS. Hold a hotkey, speak, release — text is inserted at the cursor. Runs entirely on-device.

## Project layout

```
Sotto/
├── App/              UserDefaultsKeys, AppConstants, app entry
├── Core/             DictationCoordinator, ModelManager, transcription engines, AIService
├── Indicator/        Floating pill + notch indicators (recording UI)
├── MenuBar/          Status item, menu
├── Resources/        Localizable.xcstrings, sounds, etc.
├── Services/         AudioCaptureService, TextInsertionService, HotkeyService, AudioDeviceService
└── Settings/         Settings window views (General, Model, Hotkey, AI, About)
```

`DictationCoordinator` is the `@Observable` orchestrator — the rest of the app reads state from it via `@Environment`.

## Transcription engines

Two backends behind the `TranscriptionEngine` protocol in `Core/ModelManager.swift`:

- **WhisperKitEngine** — `argmaxinc/WhisperKit`. Multilingual. Reads vocabulary keywords from `UserDefaults` and passes them as `promptTokens` on `DecodingOptions` for keyword biasing.
- **ParakeetEngine** — `FluidInference/FluidAudio` (`AsrManager`). Faster, English/EU. **No vocabulary biasing** — FluidAudio's CTC-based custom vocabulary path was tried and removed (see "Rejected: Parakeet vocabulary boosting" below).

`ModelManager` swaps the active engine based on the selected model. The coordinator/UI does not branch on engine type — engine-specific behavior belongs inside the engine. The protocol method `transcribe(samples:language:)` stays simple; engines pull their own per-feature config from services or UserDefaults directly.

### Rejected: Parakeet vocabulary boosting

We implemented FluidAudio's `CtcKeywordSpotter` + `VocabularyRescorer` flow (a separate ~97 MB English CTC encoder runs alongside the TDT decoder, then dynamic-programming rescoring substitutes keywords). The pipeline wired correctly and ran end-to-end, but real-world tests showed near-zero replacements: the English-only CTC encoder gives weak signals on Portuguese audio, and even on English audio the boost wasn't enough to fix names that the base model got wrong.

Net result: 97 MB download + extra runtime cost + extra UI surface for a feature that didn't measurably help users. We removed it and kept only the WhisperKit `promptTokens` path, which is free (no extra model, just a parameter) and works.

**Don't re-add this without a real evaluation showing meaningful improvement on a held-out audio set.** The README example in FluidAudio's docs (`asrManager.transcribe(audioSamples, customVocabulary: ...)`) suggests an easy path that doesn't actually exist on `AsrManager` — only on `SlidingWindowAsrManager`, which is streaming-oriented and wraps the same encoder + rescorer pieces.

## Localization

Strings are localized via `Sotto/Resources/Localizable.xcstrings` (Xcode String Catalog).

**Supported languages**: `de`, `es`, `fr`, `ja`, `pt-BR`, `zh-Hans` (plus `en` source). The list lives in `AppLanguage.supported` in `Settings/GeneralSettingsView.swift`.

**When you add or change a user-facing string**:

1. Wrap it in `Text(...)`, `LocalizedStringKey`, or any SwiftUI API that auto-extracts (most do — `Section`, `TextField` label, `Picker`, etc.).
2. Open `Localizable.xcstrings` and add an entry with translations for **all six** languages above. Match the existing format:
   ```json
   "Your new string" : {
     "localizations" : {
       "de" : { "stringUnit" : { "state" : "translated", "value" : "..." } },
       "es" : { ... },
       "fr" : { ... },
       "ja" : { ... },
       "pt-BR" : { ... },
       "zh-Hans" : { ... }
     }
   }
   ```
3. Insert the entry alphabetically (case-insensitive). Validate the file is still valid JSON.
4. Don't add `"extractionState" : "stale"` to new entries — that flag is set by Xcode for strings no longer found in code.

Some existing strings in the catalog only have an auto-generated comment with no translations — those fall back to English. Don't follow that pattern for new strings; translate them.

**User-visible strings**: prefer plain English in code. The catalog is the only place that holds translations.

## Conventions

- Swift, SwiftUI, `@Observable` (no `ObservableObject`/`@Published`).
- `@MainActor` on UI-touching types; engines and services are explicit about isolation.
- `UserDefaults` keys live in `App/UserDefaultsKeys.swift` — never inline string keys.
- Persisted properties on the coordinator follow the `didSet { UserDefaults.standard.set(...) }` pattern.
- New persisted settings need: a key in `UserDefaultsKeys`, a property on `DictationCoordinator` (loaded in `init`), and a UI binding via `@Bindable`.

## Don't

- Don't run build/test commands or start a dev process — the user does that.
- Don't add new top-level dependencies without checking with the user first.
- Don't introduce a per-engine branching path in coordinator/UI code; push engine differences into the engine.
