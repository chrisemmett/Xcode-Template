# NNN — Title in a few words

<!-- Copy to todo/NNN-Title_In_Words.md with the next free number (look in both
     todo/ and done/). Delete these comments. When it ships: update Status, then
     `git mv todo/NNN-... done/` (never a copy: CI fails on a number in both). -->

**Status:** todo — nothing landed yet.
<!-- Later: "todo — landed: §1, §2 (2026-11-12). Left: §3, and the device check in §5."
     Finally: "done — shipped 2026-11-20. Deferred: <what, and where it went (LLD NNN)>." -->
**Source:** <what this answers to: the HLD section (HLD §5.6), an earlier LLD (LLD 004 §3), playtest or review feedback with its date, an owner's request with its date>.
**Scope:** <what changes>. Out of scope: <what doesn't, and where that lives>.

---

## 1. The change

<What the user sees or what the system does differently, and why. A table works
well for several parts: Part | What happens | Why.>

## 2. <The detail>

<Numbers go in a table with their reasoning: Value | Number | Notes. If the
project keeps tuning numbers in a data file, say which keys.>

Rules:

- <Edge cases, accessibility (Reduce Motion, VoiceOver, Dynamic Type), what
  happens on pause, resume, rotation, a second window, iPhone Duo's fold.>

## 3. Code

- `Path/File.swift`: <the type and what it owns>. <Pure logic is called out as
  such, because it's what gets unit tests.>

## 4. Tests

- `SomethingTests`:
  - <one bullet per behaviour, phrased as the behaviour, not the method>.

Device checks (they keep this LLD in `todo/` until done):

- <What the owner looks at on a device, and what "right" looks like.>

## 5. Risks

- <What could go wrong, and what would show it.>
