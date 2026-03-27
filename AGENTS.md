---
alwaysApply: true
---

## Definition

- The app's name is Openbird.

## Commit Discipline

- Commit after every discrete action. Each meaningful change, such as adding a feature, fixing a bug, refactoring, updating docs, or adding a test, must be committed individually before moving on.
- Commit messages must use the intent as the title and a concise summary of what was done as the description or body.
- Do not batch unrelated changes into a single commit.
- If a task involves multiple steps, commit after each step rather than at the end.

## Branching (Git Butler)

- Use Git Butler to manage branches so independent work can run concurrently.
- If the current branch is `main`, commit directly on `main`.
- If the current branch name is `gitbutler/workspace` or starts with `gitbutler/workspace`, use the `/commit-msg` skill to draft the commit message, create a GitButler virtual branch for the logical change, and push that virtual branch.
- Prefer one branch and PR per logical unit of work.
- If a change depends on another open change, use stacked branches and stacked PRs so the dependency order is explicit.
- Only split work into multiple PRs when dependency or review scope makes it necessary.

## Releases

- When asked to create a release, run `swift build -c release` and `swift test` first. Do not create a release if either command fails.
- Openbird releases are driven by `.github/workflows/release.yml`. Push a tag like `v0.1.0`, or run the workflow manually with the tag input, and let GitHub Actions build, sign, notarize, and upload the DMG.
- Releases must be published immediately. Do not use draft releases.
- Include release notes with concise, descriptive bullet points explaining the user-facing changes. Do not just list commit messages or internal implementation details.

## Comments

- By default, avoid writing comments at all.
- If you write one, it should explain why, not what.

## General

- Avoid creating unnecessary types, protocols, or helpers when the logic is only used in one place.
- Keep APIs small, explicit, and easy to inspect.
- Keep commits small and reviewable.
- Run `swift build` after Swift changes to verify the package still compiles.
- Run `swift test` before committing meaningful code changes.
- Fix warnings before committing.

## Swift

- Prefer Swift concurrency with `async` and `await` over callback-based code.
- Prefer value types such as `struct` and `enum` unless identity semantics are required.
- Avoid force-unwrapping and force-casting outside tests and previews.
- Keep SwiftUI views small. Extract subviews when a view body starts carrying too much state or layout logic.
- Prefer straightforward state flow over custom abstractions.
- Do not add Combine, coordinators, or extra indirection unless the problem actually requires it.

## SwiftUI

- Keep view code declarative and local.
- Prefer a small number of observable models with explicit responsibilities.
- Derive view state where possible instead of syncing duplicated state.
- Reuse shared styling only when there is a real repeated pattern. Do not build a design system for isolated screens.
