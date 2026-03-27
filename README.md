# Openbird

Openbird is a local-first macOS activity journal built in SwiftUI. It captures frontmost-window context via the Accessibility API, stores activity in local SQLite, and generates a daily review plus date-scoped chat using a BYOK provider.

## Targets

- `OpenbirdApp`: SwiftUI desktop app with onboarding, Today, Chat, Settings, and raw-log inspection.
- `OpenbirdCollector`: background collector process that samples the frontmost window, applies exclusions, and writes activity events into the shared database.
- `OpenbirdKit`: shared models, persistence, capture logic, provider adapters, and journal/chat services.

## Providers

- Ollama: native `/api/chat` and `/api/embed` support.
- LM Studio: supported through the OpenAI-compatible adapter with the default base URL `http://127.0.0.1:1234/v1`.
- Any OpenAI-compatible endpoint can be added by editing the provider settings.

## Run

```bash
swift build
swift run OpenbirdApp
```

The app will try to launch the collector as a sibling executable from the build output. You can also run the collector directly:

```bash
swift run OpenbirdCollector
```

## Privacy defaults

- Only the frontmost app/window is captured.
- Raw key events, clipboard contents, secure text fields, hidden windows, and automatic screenshots are excluded.
- Excluded apps and excluded domains are configurable in Settings.
- All data is stored locally in `~/Library/Application Support/Openbird/openbird.sqlite`.

## Test

```bash
swift test
```
