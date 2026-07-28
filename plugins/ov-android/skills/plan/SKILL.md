---
description: Plan an Android feature or change before writing code. Produces architecture decisions, simplify pressure-test, security threat-model, testing strategy, and rollout plan. Invoke before starting any non-trivial Android work.
---

# /ov-android-plan

Produce an implementation plan for native Android work **before any code is written**.

## Input

`$ARGUMENTS` — the feature or change description. If empty, ask the user what to plan.

## Preconditions

The Android rules (`rules/android.md` from this plugin) should be loaded via the project's CLAUDE.md. If `@.claude/android-rules.md` is not imported in CLAUDE.md, suggest the user run `/ov-android-init` first, then stop.

## Output sections (produce all five)

### 1. Architecture decisions

Apply the Architecture and language sections from the Android rules. Decide:

- Compose vs View system for this surface (justify if View system is chosen)
- UDF state shape — `StateFlow` exposed from ViewModel, collected via `collectAsStateWithLifecycle()`
- ViewModel scope and lifecycle ownership (`viewModelScope`, `SavedStateHandle` for process-death survival)
- Module placement (app / feature:api / feature:impl / core / data)
- DI wiring (Hilt module placement; assisted injection for Worker / ViewModel that need runtime args)
- Navigation shape (destinations, nav keys in `:api` module, deep-link entry points)

### 2. Simplify pressure-test

Before finalizing, ask:

- Am I introducing abstraction with only one use site? Inline it.
- Am I adding a config option or flag for a hypothetical future? Drop it.
- Is there already a pattern in the codebase that does this? Reuse it.
- Am I adding fallback / retry / catch logic for scenarios that cannot happen? Remove it.
- Three similar call sites is fine — no helper yet.

### 3. Security threat-model

Apply the Security section from the Android rules. Identify:

- Sensitive data touched (PII, credentials, tokens, biometrics, location, health)
- Storage surface (Keystore / EncryptedSharedPreferences / DataStore / Room / external storage)
- Network surface (endpoints, auth method, TLS, certificate pinning via `CertificatePinner` / `NetworkSecurityConfig`)
- Input surface (deep links, `IntentFilter` entry points, `PendingIntent` usage, share targets, `FileProvider` URIs)
- Permission surface (new runtime permissions, `POST_NOTIFICATIONS` on API 33+, `READ_MEDIA_*` on API 33+)

### 4. Testing strategy

Apply the Testing section from the Android rules. Decide:

- Behaviors to cover with JVM unit tests (models, use cases, ViewModels with `MainDispatcherRule`)
- Flow collection tests via Turbine
- Compose UI tests (interaction + preview-based snapshot)
- Instrumented tests only when JVM cannot cover (Keystore, real Intent resolution, WorkManager)
- Test dispatcher / MainDispatcherRule setup
- Test doubles — fakes at narrow repository interfaces; MockK only where a fake is impractical

### 5. Rollout

- Feature flag? Default is **no** unless there's a real reason (A/B test, risky migration, staged rollout). Justify either way.
- Migration plan for existing users / data / persisted preferences / Room schema (`Migration` classes, destructive-migration-free path)
- Telemetry events to add (names, properties)
- Rollback story
- `minSdk` / `targetSdk` impact — any new API used requires a guard or a baseline bump

## Output format

A single markdown document with the 5 sections. Flag any section where you had to assume — do not silently default.

## Done when

User reviews and approves the plan. On approval, implementation proceeds. The `rules/android.md` conventions govern code-level decisions automatically (they are imported in CLAUDE.md), so the plan does not need to re-state every standing rule.
