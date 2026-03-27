# Openbird

Openbird is a local-first macOS activity journal.

It watches your current work context through the Accessibility API, stores that context on your Mac, and turns it into a daily review and follow-up chat.

It exists because software with this much visibility into your day should not be a black box.

No account is required. No backend is required.

## Why This Exists

If an app can see what you are doing across your computer, you should be able to inspect it, control it, pause it, and delete its data.

Openbird is built around a simple idea:

- your activity data should stay on your machine by default
- your model should be your choice
- the privacy boundary should be explicit
- software this sensitive should be open source

This is not "trust us" software. The point is that you do not have to.

## What Openbird Does

Openbird captures the frontmost app and window, builds a local timeline of your day, and uses that log to generate:

- a daily review with time blocks, highlights, and a short narrative
- follow-up chat scoped to your local activity data
- citations back to the underlying apps, windows, URLs, and timestamps

It is meant to answer questions like:

- What did I do today?
- What was I working on around 3pm?
- Which project took most of my attention?
- What tabs, apps, or docs was I using during that block?

## Privacy Boundary

Openbird is intentionally conservative.

Openbird captures:

- the frontmost app
- bundle ID and app name
- window title
- browser tab URL when available
- visible text from the active window's accessibility tree
- start and end timestamps

Openbird does not capture:

- raw key events
- clipboard contents
- passwords
- secure text fields
- hidden or minimized windows
- automatic screenshots

You can also:

- pause capture at any time
- exclude apps
- exclude domains
- inspect the raw log used for generation
- delete the last hour, the last day, or everything

All captured data is stored locally in:

`~/Library/Application Support/Openbird/openbird.sqlite`

## Bring Your Own Model

Openbird supports local-first BYOK out of the box.

- Ollama
- LM Studio
- other OpenAI-compatible endpoints

You can run fully offline if your model is local.

Default local endpoints:

- Ollama: `http://127.0.0.1:11434/v1`
- LM Studio: `http://127.0.0.1:1234/v1`

The app includes presets for both and lets you configure separate generation and embedding models.

## Install

Current release target:

- macOS 14+
- Apple Silicon

Download the latest release here:

[Latest Release](https://github.com/ComputelessComputer/openbird/releases/latest)

New releases are shipped as a signed macOS Apple Silicon DMG.

If you are downloading an older tag, you may still see the previous unsigned tarball format.

Open the DMG, drag `Openbird.app` into `Applications`, then launch it.

## Quick Start

1. Download and extract the latest release.
2. Launch `OpenbirdApp`.
3. Grant Accessibility permission when prompted.
4. In Settings, choose an Ollama or LM Studio preset.
5. Click `Check Connection`, then save the provider.
6. Go to `Today` and generate your first review.
7. Use `Chat` to ask questions about your day.

## What The App Looks Like

Openbird has four main surfaces:

- Onboarding: explains permissions and privacy
- Today: generates the daily review
- Chat: asks questions against your local activity log
- Settings: provider setup, exclusions, retention, pause, and delete controls

## Current State

Openbird is early, but the core loop works:

- local capture
- local storage
- exclusions
- raw-log inspection
- daily journal generation
- date-scoped chat over your activity history

The current scope is intentionally narrow. Openbird is focused on being a trustworthy personal activity journal first.

## Development

If you want to run from source:

```bash
swift build
swift run OpenbirdApp
```

The collector can also be started directly:

```bash
swift run OpenbirdCollector
```

Run tests with:

```bash
swift test
```

## Open Source

Open source is not a branding choice here. It is part of the product.

When software observes your work, transparency matters. You should be able to inspect how it captures data, where it stores it, what it excludes, and which model receives your prompts.

The codebase is open because trust is better when it is verifiable.
