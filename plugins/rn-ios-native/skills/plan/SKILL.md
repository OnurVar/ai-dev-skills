---
description: Plan a React Native iOS bridge feature or change before writing code. Produces architecture decisions (TurboModule vs legacy, Fabric vs legacy ViewManager, threading, codegen spec), simplify pressure-test, security threat-model, testing strategy, and rollout plan. Invoke before starting any non-trivial RN iOS native / bridge work.
---

# /rn-ios-native:plan

Produce an implementation plan for React Native iOS bridge work (Swift / Obj-C / Obj-C++) **before any code is written**.

## Input

`$ARGUMENTS` — feature or change description. If empty, ask the user what to plan.

## Preconditions

The RN iOS native rules (`rules/rn-ios-native.md`) should be loaded via the project's CLAUDE.md. If `@.claude/rn-ios-native-rules.md` is not imported, suggest the user run `/rn-ios-native:init` first, then stop. If the project has pure iOS code, `/ios:init` should also be run — these rule sets are additive.

## Output sections (produce all five)

### 1. Architecture decisions

Apply the Architecture and New Architecture sections from the rules. Decide:

- **TurboModule or legacy NativeModule?** Default: TurboModule for new work on projects shipping New Architecture. Legacy only if New Arch isn't available in the project.
- **Fabric ComponentView or legacy ViewManager?** Default: Fabric for new UI components under New Arch.
- **Sync or async method signatures?** Sync blocks the JS thread — only for trivial getters well under 16 ms. Anything disk / network / compute is async.
- **Method queue.** Default: background serial (TurboModule default). Use `dispatch_get_main_queue()` only if the module touches UIKit; document why.
- **Module identity.** Register via `@objc(ModuleName)` (Swift) or `RCT_EXPORT_MODULE()` (Obj-C). JS-side invocation name must match.
- **Codegen spec.** Required for TurboModule / Fabric. Define the TS/Flow spec before the Swift/ObjC implementation; sibling `/rn-typescript:plan` owns the JS-side spec.
- **AppDelegate changes.** Any new deep-link handlers, URL schemes, universal links, background-mode capabilities, or entitlements must be flagged — they require Info.plist + provisioning updates and human review.

### 2. Simplify pressure-test

Before finalizing, ask:

- Am I creating a new bridge module for something that could live entirely on the JS side? Inline it in JS.
- Am I exposing Swift APIs that JS doesn't actually need? Keep the bridge surface minimal.
- Am I writing a legacy NativeModule when TurboModule would work? Choose TurboModule.
- Am I wrapping an iOS framework that an already-maintained community library wraps correctly? Use the community library.
- Three similar JS→native calls is fine — no helper module yet.

### 3. Security threat-model

Apply the Security section from the rules. Identify:

- Sensitive data crossing the bridge (tokens, biometrics, PII, health, location)
- Native-side storage (Keychain for secrets; UserDefaults is a leak)
- Native-side network (certificate pinning via `URLSessionDelegate` if the module makes requests; ATS must stay on)
- Input surface: URLs, deep links, universal links, intents — validate before forwarding to JS via the bridge
- Secret exposure: no API keys in Info.plist, Swift constants, or module bundles. Use runtime config or an ignored `.xcconfig`.

### 4. Testing strategy

Apply the Testing section from the rules. Decide:

- Unit tests for native module logic (Swift Testing / XCTest) — mock `RCTBridge`, assert behavior in isolation
- Contract tests: TurboModule spec ⇄ Swift/Obj-C conformance (codegen enforces types at compile time; add runtime tests for non-type invariants like event names, error codes)
- Integration (E2E): Detox / Maestro for cross-bridge correctness — JS calls module, asserts observable effect
- Snapshot baselines for Fabric `ComponentView` render output

### 5. Rollout

- Feature flag: same calculus as the JS side — default no unless there's a real reason.
- Migration: existing JS callers of a legacy `NativeModule` need updates if you're switching to TurboModule (import path, possibly different type signatures).
- **Native code changes ship in a rebuild of the app binary — not via OTA (CodePush / EAS Update).** Call this out explicitly in the plan.
- Telemetry: `os_log` with redacted fields on the native side; JS-side event logging for business metrics.
- Rollback: app store rollback is slow; the practical kill switch is a JS-side feature flag that skips the native call.

## Output format

A single markdown document with the 5 sections. Flag any section where you had to assume — do not silently default.

## Done when

User reviews and approves the plan. On approval, implementation proceeds. The rules files govern code-level decisions automatically (they are imported in CLAUDE.md).
