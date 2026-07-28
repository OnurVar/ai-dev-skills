---
description: Comprehensive review of pending React Native iOS bridge changes (Swift / Obj-C / Obj-C++). Runs bridge-specific pre-check, /pr-review-toolkit:review-pr, /security-review, /simplify, and /code-review:code-review (adapted for local diff when no PR). Filters out style, nits, linter-catchable issues, and findings below 80% confidence. Invoke when reviewing RN iOS native / bridge changes. For a lightweight one-pass review of a GitHub PR instead, use /ov-pr-review-quick.
---

# /ov-rn-ios-native-review-deep

Full review pipeline over the current pending changes to React Native iOS bridge code (TurboModules, legacy NativeModules, Fabric components, legacy ViewManagers, AppDelegate bridge setup, Podfile).

## Preconditions

`rules/rn-ios-native.md` should be imported via the project's CLAUDE.md (run `/ov-rn-ios-native-init` if not). If the repo also has pure iOS code, the `ios` plugin's rules should be imported via `/ov-ios-init` as well — this plugin's rules are additive, not a replacement.

## Pipeline

Run every step. Aggregate and filter at the end. If a companion tool is not installed, note it in the Status block and continue.

### 1. RN iOS bridge-specific pre-check (inline)

Scan `git diff` for bridge-specific concerns:

- **Double-resolve / double-reject** of `RCTPromiseResolveBlock` or `RCTPromiseRejectBlock` — crashes with `Callback was already invoked`. Branching code paths that can both succeed and error must guard with a `__block BOOL done` flag (Obj-C) or equivalent in Swift.
- **Primitive Obj-C types in `RCT_EXPORT_METHOD` signatures** (`BOOL`, `NSInteger`, `double`). JS can pass `null` → bridge passes `nil` → crash on a primitive. Use `NSNumber *`.
- **TurboModule / Fabric Swift class missing `@objc(ModuleName)`** or missing `NSObject` inheritance; Obj-C module missing `RCT_EXPORT_MODULE()`. Module won't be discoverable at runtime.
- **`methodQueue` overridden to `dispatch_get_main_queue()` for a module that doesn't touch UIKit** — unnecessary main-thread work and blocks the UI.
- **`dispatch_async(DispatchQueue.global(), ...)` inside an async TurboModule method** — already on the native-modules serial queue; the hop adds latency without benefit.
- **Callback / Promise blocks strong-capture `self`** in long-lived modules or `RCTEventEmitter` subclasses — retain cycles. Use `[weak self]` / `__weak typeof(self) weakSelf`.
- **`RCTEventEmitter.supportedEvents` returning an empty array** or missing override — `sendEventWithName:` drops silently.
- **Calling `sendEventWithName:` without a `hasListeners` guard** — warns on every call when no JS listener is attached; usually indicates the design should be Promise/Callback instead of Event.
- **Deep-link / universal-link handling in `AppDelegate` forwarding raw URLs to JS** without scheme + host + path validation — treat incoming URLs as untrusted.
- **Codegen spec drift** — Swift / Obj-C method signature changed without a corresponding change to the TS / Flow codegen spec.
- **Swift actors crossing the Obj-C bridge boundary** without a documented isolation plan — actor-isolated state accessed from `@objc` methods is a data race.
- **TurboModule `invalidate()` not implemented** on modules that hold native resources (timers, observers, file handles, background tasks) — leaks across bridge reloads.
- **Secrets in module source, Info.plist entries added in the diff, or build settings** — always Critical.

### 2. `/pr-review-toolkit:review-pr`

Invoke via the Skill tool with no extra args (it picks sub-agents per file type). Its `code-reviewer` agent reads the project CLAUDE.md, which imports our RN iOS native rules and the review-behavior filter.

If `pr-review-toolkit` is not installed, note that in the Status block and skip.

### 3. `/security-review`

Invoke the built-in `/security-review` skill via the Skill tool.

### 4. `/simplify`

Invoke the built-in `/simplify` skill via the Skill tool.

### 5. `/code-review:code-review` (adapts to PR / local)

Check for an open PR on the current branch: `gh pr view --json url 2>/dev/null`.

- **PR exists:** invoke `/code-review:code-review` via the Skill tool as-designed. It runs the eligibility check, the 5 parallel Sonnet agents, confidence scoring, and posts a filtered comment to the PR. Capture findings for the aggregator.

- **No PR:** invoke `/code-review:code-review` via the Skill tool with explicit local-mode adaptation:
  - Skip step 1 (PR eligibility check)
  - Skip step 7 (eligibility re-check)
  - Skip step 8 (`gh pr comment`)
  - Run steps 2–6: the 5 parallel Sonnet agents on local `git diff`, confidence scoring, filter below 80
  - Return filtered findings to the aggregator

If `code-review` is not installed, note that in the Status block and skip.

### 6. Aggregate + noise filter

Combine findings from steps 1–5. Apply the filter from `rules/rn-ios-native.md § Review behavior` one more time as a safety net (belt-and-suspenders): drop style, linter-catchable, pedantic, out-of-stack (pure iOS app / JS / Android), pre-existing-unchanged-lines, and <80% confidence findings; keep correctness, security, bridge-specific concerns, rule violations.

De-duplicate across steps. If multiple steps flagged the same issue, keep the highest-confidence version and note the sources.

## Output

A single markdown document:

```
# React Native iOS bridge review

## Critical (N)
- [source] issue description (file:line)
  → suggested fix

## Important (N)
- ...

## Suggestions (N)
- ...

## Strengths
- what's well done

## Status
- pre-check: ran
- pr-review-toolkit: ran / skipped (not installed)
- security-review: ran
- simplify: ran
- code-review: posted to PR #123 / ran locally (no PR) / skipped (not installed)
```

## Done when

One consolidated document, noise-filtered, de-duplicated, categorized. If all steps returned empty after filtering, say so plainly — do not invent findings.
