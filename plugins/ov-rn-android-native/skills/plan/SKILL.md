---
description: Plan a React Native Android bridge feature or change before writing code. Produces architecture decisions (TurboModule vs legacy, Fabric vs legacy ViewManager, threading, codegen spec), simplify pressure-test, security threat-model, testing strategy, and rollout plan. Invoke before starting any non-trivial RN Android native / bridge work.
---

# /ov-rn-android-native-plan

Produce an implementation plan for React Native Android bridge work (Kotlin / Java) **before any code is written**.

## Input

`$ARGUMENTS` — feature or change description. If empty, ask the user what to plan.

## Preconditions

The RN Android native rules (`rules/rn-android-native.md`) should be loaded via the project's CLAUDE.md. If `@.claude/rn-android-native-rules.md` is not imported, suggest the user run `/ov-rn-android-native-init` first, then stop. If the project has pure Android code, `/ov-android-init` should also be run — these rule sets are additive.

## Output sections (produce all five)

### 1. Architecture decisions

Apply the Architecture and New Architecture sections from the rules. Decide:

- **TurboModule or legacy NativeModule?** Default: TurboModule for new work on projects shipping New Architecture. Legacy only if New Arch isn't available.
- **Fabric `ViewManagerDelegate` or legacy `ViewManager`?** Default: Fabric + `ViewManagerDelegate` for new UI components under New Arch.
- **Sync or async method signatures?** Sync blocks the JS thread — only for trivial getters well under 16 ms. Anything disk / network / compute is async.
- **Thread.** Methods run on the NativeModules queue by default. Work that touches UI (View, Activity, Dialog) must hop via `UIManagerModule.addUIBlock` or `reactContext.runOnUiQueueThread`. Document the hop.
- **Module registration.** `ReactPackage` implementation that provides the module via `createNativeModules()`. Registered in `MainApplication.getPackages()` if manual, or picked up by autolinking for published libraries.
- **Codegen spec.** Required for TurboModule / Fabric. Define the TS/Flow spec before the Kotlin implementation; sibling `/ov-rn-typescript-plan` owns the JS-side spec.
- **MainActivity / MainApplication changes.** Any new `Intent` filter, deep-link handler, `onNewIntent` logic, or manifest permission must be flagged — they require AndroidManifest.xml + permission-review updates.

### 2. Simplify pressure-test

Before finalizing, ask:

- Am I creating a new bridge module for something that could live entirely on the JS side? Inline it in JS.
- Am I exposing Kotlin APIs that JS doesn't actually need? Keep the bridge surface minimal.
- Am I writing a legacy `NativeModule` when TurboModule would work? Choose TurboModule.
- Am I wrapping an Android framework that a maintained community library wraps correctly? Use the community library.
- Three similar JS→native calls is fine — no helper module yet.

### 3. Security threat-model

Apply the Security section from the rules (bridge-specific) plus the sibling `rules/android.md` Security section (general Android). Identify:

- Sensitive data crossing the bridge (tokens, biometrics, PII, health, location)
- Native-side storage — secrets go to Keystore / EncryptedSharedPreferences (covered in `android.md`); modules must not leak secrets into `SharedPreferences` / `DataStore` / module BuildConfig
- Native-side network: certificate pinning via OkHttp `CertificatePinner` if the module makes requests; verify `usesCleartextTraffic = false` remains
- Input surface: `Intent` extras, deep-link URIs from `onNewIntent`, action strings — validate every field before forwarding via `RCTDeviceEventEmitter`
- `PendingIntent` creation from modules must set `FLAG_IMMUTABLE` on API 31+

### 4. Testing strategy

Apply the Testing section from the rules. Decide:

- JVM unit tests for native module logic — mock `ReactContext`, use a `TestPromise` helper that captures `resolve` / `reject` calls
- Robolectric only when the module uses Android framework types that a JVM test can't satisfy
- Instrumented tests for real Fabric rendering, `ViewManagerDelegate` property routing, and real JSI marshaling
- Contract tests for the codegen spec — a dummy consumer that compiles against the generated Kotlin interface catches drift
- Inject `TestDispatcher` for coroutine-backed module scopes; assert on `promise.reject` code, not localized message

### 5. Rollout

- Feature flag: same calculus as the JS side — default no unless there's a reason.
- Migration: existing JS callers of a legacy `NativeModule` need updates if switching to TurboModule (import path, possibly different type signatures).
- **Native code changes ship in a rebuild of the app binary — not via OTA (CodePush / EAS Update).** Call this out explicitly in the plan.
- Telemetry: `Log.i` with redacted fields on the native side (Timber in debug only); JS-side event logging for business metrics.
- Rollback: Play Store rollback is slow; the practical kill switch is a JS-side feature flag that skips the native call.

## Output format

A single markdown document with the 5 sections. Flag any section where you had to assume — do not silently default.

## Done when

User reviews and approves the plan. On approval, implementation proceeds. The rules files govern code-level decisions automatically (they are imported in CLAUDE.md).
