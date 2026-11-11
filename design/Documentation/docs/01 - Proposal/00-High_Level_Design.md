# {{DISPLAY_NAME}} — High Level Design

**Status:** draft — <date>.

<!-- The HLD says what the app is and the decisions that shape it. LLDs in
     03 - Low Level Design/ say how each piece gets built, and cite this doc by
     section (HLD §4.2). Never renumber sections: add to the end or use
     sub-sections. Record the owner's decisions with a date:
     "(owner's decision, 2026-11-10)". -->

## 1. Purpose

What the app is for, who it's for, and the one thing it must do well.

## 2. Platforms and requirements

- iOS / iPadOS {{IOS_DEPLOYMENT_TARGET}} and later. iPhone Duo: <supported / not yet>.
- Swift 6 with strict concurrency, SwiftUI.
- Accessibility: VoiceOver, Dynamic Type, Reduce Motion from the first build.
- Privacy: what the app collects (ideally nothing), and where data lives.

## 3. Experience

The main screens and flows, and what the user sees first.

## 4. Architecture

- `{{APP_NAME}}/` — the app target: SwiftUI views and their view models.
- `Packages/{{MODULE_NAME}}Core/` — Foundation-only domain logic, tested with `swift test`.
- Data: storage, sync, networking, and the boundaries between them.

## 5. Key decisions

| # | Decision | Why | Date |
|---|---|---|---|
| D1 | XcodeGen, with the project not committed | No pbxproj merge conflicts; one source of truth (`docs/xcodegen-regen-defenses.md`) | |
| D2 | Domain logic in a Foundation-only package | Fast, deterministic tests anywhere | |

## 6. Testing

Unit tests for domain logic in the core package; view-model tests in the app
target; UI tests nightly, off the merge gate. The owner checks UI by eye on a device.

## 7. Release

TestFlight from `pre-prod` via `testflight-<N>` refs (`docs/release.md`); the
App Store from `main`, tagged `appstore-<version>`.

## 8. Milestones

| Milestone | Scope | Exit criteria |
|---|---|---|
| M0 | Skeleton builds, tests and ships to TestFlight | First TestFlight build installed on a device |
| M1 | | |
