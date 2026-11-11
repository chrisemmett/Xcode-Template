# Why `xcodegen generate` keeps wiping your project — and how to stop it

A companion to the CI template, drawn from real apps that hit every one of
these. The examples use a made-up iPhone app, `MyApp`, with a watch app and a
complications extension. If your project uses
[xcodegen](https://github.com/yonaskolb/XcodeGen) as the source of truth
for `project.pbxproj`, this is the story of every setting that got
silently dropped on regen and how `project.yml` was rewritten to make
those values survive.

The short version: **xcodegen rewrites every file it owns from
`project.yml` on every run.** Anything that isn't expressed somewhere
xcodegen reads will not be expressed in the output. The fix is not to
edit the generated artefacts — it's to push the value back into a layer
that survives generation. There are four such layers, in order of
preference:

1. `project.yml` itself (the source of truth).
2. An xcconfig file referenced via `configFiles:` (wins over generated
   settings; never touched by xcodegen).
3. Xcode's `xcuserdata` (per-user state — survives regen because
   xcodegen doesn't own it).
4. The committed `project.pbxproj` (last resort — overwritten on the
   next regen, so this layer is effectively no defence at all).

The rest of this doc maps each class of "blank-out" symptom to the layer
that fixes it, with `MyApp`'s `project.yml` as the worked example.

---

## Symptom 1: Info.plist keys disappear after regen

**What broke.** Hand-edited keys in `MyApp/Info.plist`, `MyAppWatch/Info.plist`,
and `MyAppWatchComplications/Info.plist` vanished on every `xcodegen
generate`. The most visible failure was the watch complications
extension refusing to install with `extensionDictionary must be set`
because `NSExtension` only lived in the on-disk plist, not in
`project.yml`.

**Why.** xcodegen owns every file referenced by `info.path:`. On each
run it rewrites that plist from the `info.properties:` block in
`project.yml`. If a key isn't in `properties`, it's not in the output.

**Fix.** Move every runtime-relevant key into `info.properties:`.
For `MyApp` this meant `CFBundleDisplayName`, `LSApplicationCategoryType`,
`ITSAppUsesNonExemptEncryption`, the `NSHealth*UsageDescription`
strings, `UISupportedInterfaceOrientations`, `UILaunchScreen`, the
watch's `WKApplication` / `WKCompanionAppBundleIdentifier`, and the
complications' `NSExtension` dict.

```yaml
MyAppWatchComplications:
  info:
    path: MyAppWatchComplications/Info.plist
    properties:
      NSExtension:
        NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

**Tell.** If a key works after a manual edit but breaks the next time
someone regenerates, it belongs in `info.properties`.

---

## Symptom 2: Version strings reset to "1.0" / "1"

**What broke.** `CFBundleShortVersionString` and `CFBundleVersion` in
every Info.plist would silently reset to xcodegen's defaults
("1.0" / "1"), decoupling shipped builds from the
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` set elsewhere. The
watch complications appex installation failed outright when the
regenerated plist ended up with an empty `CFBundleVersion`.

**Why.** `info.properties` doesn't auto-bind these to the build
settings. If you don't supply them explicitly, xcodegen writes its
hardcoded literals.

**Fix.** Bind them to the build-setting macros in every target's
`info.properties`:

```yaml
properties:
  CFBundleShortVersionString: $(MARKETING_VERSION)
  CFBundleVersion: $(CURRENT_PROJECT_VERSION)
```

---

## Symptom 3: Signing & Capabilities pane goes blank

**What broke.** HealthKit, iCloud, and Push rows would disappear from
the app target's Signing & Capabilities pane after every regen, even
though `MyApp/MyApp.entitlements` on disk still listed all the right keys.

**Why.** Two independent xcodegen behaviours combined:

- xcodegen rewrites the file referenced by `entitlements.path:` on
  every run, merging `properties` on top of whatever's already there.
  When `properties` was omitted, the merge happened against an empty
  input — effectively wiping the file.
- The Signing & Capabilities pane doesn't read entitlements from disk;
  it reads from `TargetAttributes.SystemCapabilities` in the pbxproj.
  Without explicit `attributes.SystemCapabilities` entries in
  `project.yml`, that dictionary regenerates empty.

**Fix.** List every entitlements key under `entitlements.properties:`
(making `project.yml` the source of truth for the entitlements file
too), AND set the matching capability flags under `attributes:`:

```yaml
MyApp:
  attributes:
    DevelopmentTeam: ABCDE12345
    SystemCapabilities:
      com.apple.HealthKit:    { enabled: 1 }
      com.apple.iCloud:       { enabled: 1 }
      com.apple.Push:         { enabled: 1 }
  entitlements:
    path: MyApp/MyApp.entitlements
    properties:
      com.apple.developer.healthkit: true
      com.apple.developer.healthkit.background-delivery: true
      com.apple.developer.icloud-container-identifiers:
        - iCloud.com.example.myapp
      com.apple.developer.icloud-services:
        - CloudKit
      aps-environment: development
```

The committed entitlements file is then just the regenerated artefact —
kept in git so fresh clones can build without xcodegen installed, but
never the place to edit a key.

---

## Symptom 4: DEVELOPMENT_TEAM resets to empty, CloudKit traps at runtime

**What broke.** Earlier `project.yml` carried `DEVELOPMENT_TEAM: ""`.
That blank string survived regeneration intact — and got written into
the pbxproj, overwriting whatever team the developer had picked in the
Signing pane. The result: builds went out unsigned, `CKContainer.default()`
trapped at runtime, and signing had to be re-set by hand after every
regen.

**Why.** xcodegen treats empty-string values as values, not as
"unset". It writes them verbatim into the pbxproj.

**Fix — two layers.** Pin the team explicitly in `project.yml` so
fresh clones sign with no per-Mac setup:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: ABCDE12345
```

…and for projects that need a per-developer override (the original
motivation for leaving it blank), use the xcconfig escape hatch
described next instead of an empty string.

---

## Symptom 5: Per-developer overrides need to survive regen

**Use case.** Sometimes a value genuinely needs to vary per machine
(a developer's personal `DEVELOPMENT_TEAM`, a one-off version bump for
a release branch). Editing the pbxproj is useless — it gets wiped.
Editing `project.yml` is wrong — it leaks the value to every clone.

**Fix.** A gitignored `Local.xcconfig` referenced via `configFiles:`
on every target, with a tracked `Local.xcconfig.example` as a
copy-and-fill template.

```yaml
targets:
  MyApp:
    configFiles:
      Debug:   Local.xcconfig
      Release: Local.xcconfig
```

`.gitignore`:

```
Local.xcconfig
```

xcconfig values win over generated pbxproj settings, and the file is
never touched by xcodegen — so values placed there survive every regen.

**One subtlety.** xcconfig settings beat *project-base* xcodeproj
settings, but lose to *target-level* xcodeproj settings. So if a value
needs to differ between targets (e.g. the app ships at `2026.06` while the
watch app stays at `1.0.0`), the per-target value goes under that
target's `settings.base`, and only the shared default goes in
`project.yml`'s top-level `settings.base` or in `Local.xcconfig`.

---

## Symptom 6: Display Name and Category tab go blank

**What broke.** Xcode's General tab rendered an empty Display Name and
Category for the app target after every regen, even though the on-disk
Info.plist still had the right values.

**Why.** The General tab doesn't read those fields from the plist on
disk — it reads `INFOPLIST_KEY_CFBundleDisplayName` and
`INFOPLIST_KEY_LSApplicationCategoryType` from the build settings.
Without those, the tab shows blank.

**Fix.** Set both the plist keys (in `info.properties` so the value is
visible by reading the plist alone) AND the matching `INFOPLIST_KEY_*`
build settings:

```yaml
settings:
  base:
    INFOPLIST_KEY_CFBundleDisplayName: MyApp
    INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.healthcare-fitness
```

---

## Symptom 7: Destination picker re-adds iPad / Mac / visionOS

**What broke.** iPad, Mac Catalyst, Mac Designed for iPad, and
visionOS Designed for iPhone kept reappearing in the destination
picker after every regen even though the app is iPhone-only.

**Why.** xcodegen falls back to Xcode's modern defaults — which
include all those destinations — for any of the relevant flags that
isn't pinned.

**Fix.** Pin the full set explicitly under the target's `settings.base`:

```yaml
TARGETED_DEVICE_FAMILY: "1"
SUPPORTED_PLATFORMS: "iphoneos iphonesimulator"
SUPPORTS_MACCATALYST: NO
SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO
```

Drop any one of them and that destination is back on the next regen.

---

## Symptom 8: "Multiple commands produce .../Info.plist"

**What broke.** An app target listed its whole source folder,
which contains `Info.plist`. XcodeGen processed the plist through
`INFOPLIST_FILE` *and* copied it as a resource, and the build refused both.

**Fix.** Exclude the plist from `sources` (`excludes: [Info.plist]`), or use
`GENERATE_INFOPLIST_FILE: YES` with `INFOPLIST_KEY_*` settings and no plist at
all, which is what the template's `project.yml` does.

---

## Symptom 9: Merged pbxproj that Xcode refuses to open

**What broke.** Two branches each regenerated the committed pbxproj. Git
merged them line by line, "cleanly", and left `main` with a truncated group and
a duplicated root group. CI didn't notice because it regenerates the project
before building, so the broken committed file was never opened.

**Fixes, in order of preference.**

1. Don't commit the generated project: put
   `*.xcodeproj/` in `.gitignore` and generate it everywhere (`make generate`,
   the CI workflows, the fastlane lanes). The class of bug disappears, along
   with pbxproj merge conflicts and the "forgot to regenerate" commit. The
   template does this.
2. If the project must be committed (so a clone opens in Xcode without
   xcodegen), lint it in CI before regenerating:
   `plutil -lint <App>.xcodeproj/project.pbxproj`.

---

## The "regen wipe" checklist

When you find a setting that didn't survive `xcodegen generate`, ask:

1. **Which file did xcodegen overwrite?** `project.pbxproj`,
   `Info.plist`, `.entitlements`, or a workspace setting.
2. **What does xcodegen read for that file?** Find the matching key in
   `project.yml` — `settings.base`, `attributes`, `info.properties`,
   `entitlements.properties`, etc.
3. **If no key exists, add one** and put the value there. The setting
   now survives regen and is auditable in version control.
4. **If the value needs to differ per machine**, put it in
   `Local.xcconfig` instead (and add a line to `Local.xcconfig.example`
   documenting the override).
5. **Never edit the generated artefacts.** Any fix applied to the
   pbxproj, the entitlements file, or an Info.plist is one
   `xcodegen generate` away from being silently undone.

The template's `project.yml` applies every defence above, and each defensive
block has a comment saying which symptom drove it. Read those comments before
changing the surrounding setting.
