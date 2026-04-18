---
description: Comprehensive review of pending React Native Android bridge changes (Kotlin / Java). Runs bridge-specific pre-check, /pr-review-toolkit:review-pr, /security-review, /simplify, and /code-review:code-review (adapted for local diff when no PR). Filters out style, nits, linter-catchable issues, and findings below 80% confidence. Invoke when reviewing RN Android native / bridge changes.
---

# /rn-android-native:review

Full review pipeline over the current pending changes to React Native Android bridge code (TurboModules, legacy NativeModules, Fabric ViewManagers, legacy ViewManagers, MainActivity / MainApplication bridge setup, Gradle changes affecting the RN layer).

## Preconditions

`rules/rn-android-native.md` should be imported via the project's CLAUDE.md (run `/rn-android-native:init` if not). If the repo also has pure Android code, the `android` plugin's rules should be imported via `/android:init` as well — this plugin's rules are additive, not a replacement.

## Pipeline

Run every step. Aggregate and filter at the end. If a companion tool is not installed, note it in the Status block and continue.

### 1. RN Android bridge-specific pre-check (inline)

Scan `git diff` for bridge-specific concerns:

- **Double-resolve / double-reject of `Promise`** — crashes with `ObjectAlreadyConsumedException`. Branching `@ReactMethod` code paths that can both succeed and error must guard with an `AtomicBoolean` or equivalent single-call gate.
- **Primitive parameters in `@ReactMethod`** (`Boolean` as Kotlin primitive, `Int`, `Double` that aren't nullable). JS can pass `null`; primitive params crash on unbox. Use `Double?`, `Int?`, `Boolean?` with nullable annotations, or accept `ReadableMap` / `ReadableArray`.
- **`Activity` cached at module construction** — use `reactApplicationContext.currentActivity` per call. A cached Activity reference goes stale on configuration change and leaks the old Activity across bridge reloads.
- **`WritableMap` / `WritableArray` reused after consumed** — after `promise.resolve(map)`, the map is in an undefined state. Build a fresh `Arguments.createMap()` / `Arguments.createArray()` for each call.
- **Static `ReactContext` field in a module** — leaks the entire RN runtime. `ReactContext` reference must live on the module instance, not in a companion object or static field.
- **Module coroutine scope not cancelled in `invalidate()`** — outlives the module, leaks `Promise` / `ReactContext` / captured state. Store a `val moduleScope = CoroutineScope(SupervisorJob() + dispatcher)` and call `moduleScope.cancel()` in `invalidate()` / `onCatalystInstanceDestroy()`.
- **`GlobalScope.launch` / `runBlocking` in a bridge method** — `GlobalScope` escapes module lifetime; `runBlocking` blocks the NativeModules thread and can deadlock with a main-thread wait.
- **Event emission without `hasActiveReactInstance()` guard** — `reactContext.getJSModule(RCTDeviceEventEmitter::class.java).emit(...)` on a torn-down context crashes.
- **Missing `addListener` / `removeListeners` overrides** in a TurboModule event emitter — codegen-generated spec requires them; without, listener-count tracking warns on every subscribe.
- **`@ReactModule` missing on a TurboModule class** — codegen + module registration relies on the annotation's `name` field matching the JS-side spec name.
- **Fabric `ViewManagerDelegate` prop routing** — `@ReactProp` handlers must match the codegen-generated `Props` field names exactly; a typo silently no-ops.
- **Legacy `ViewManager` AND Fabric `ViewManagerDelegate` registered for the same component** — collision; delete the legacy path in the same commit as the Fabric one.
- **Deep-link handling in `MainActivity.onNewIntent` forwarding raw URIs to JS** without scheme + host + path validation — treat incoming `Intent` data as untrusted.
- **`PendingIntent` created in a bridge module without `FLAG_IMMUTABLE`** on API 31+ — `SecurityException` at runtime; always Critical.
- **Codegen spec drift** — Kotlin `@ReactMethod` / ViewManager prop signature changed without a corresponding change to the TS / Flow codegen spec.
- **Secrets in `BuildConfig`, module resources, or Gradle properties committed to VCS** — always Critical.

### 2. `/pr-review-toolkit:review-pr`

Invoke via the Skill tool with no extra args (it picks sub-agents per file type). Its `code-reviewer` agent reads the project CLAUDE.md, which imports our RN Android bridge rules and the review-behavior filter.

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

Combine findings from steps 1–5. Apply the filter from `rules/rn-android-native.md § Review behavior` one more time as a safety net (belt-and-suspenders): drop style, linter-catchable, pedantic, out-of-stack (pure Android app / JS / iOS), pre-existing-unchanged-lines, and <80% confidence findings; keep correctness, security, bridge-specific concerns, rule violations.

De-duplicate across steps. If multiple steps flagged the same issue, keep the highest-confidence version and note the sources.

## Output

A single markdown document:

```
# React Native Android bridge review

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
