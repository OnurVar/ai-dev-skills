---
description: Plan an iOS feature or change before writing code. Produces architecture decisions, simplify pressure-test, security threat-model, testing strategy, and rollout plan. Invoke before starting any non-trivial iOS work.
---

# /ov-ios-plan

Produce an implementation plan for native iOS work **before any code is written**.

## Input

`$ARGUMENTS` — the feature or change description. If empty, ask the user what to plan.

## Preconditions

The iOS rules (`rules/ios.md` from this plugin) should be loaded via the project's CLAUDE.md. If `@.claude/ios-rules.md` is not imported in CLAUDE.md, suggest the user run `/ov-ios-init` first, then stop.

## Output sections (produce all five)

### 1. Architecture decisions

Apply the Architecture and language sections from the iOS rules. Decide:

- SwiftUI vs UIKit for this surface (justify if UIKit is chosen)
- State ownership and location (View → `@State` / `@Binding` / `@Observable` / `@Environment`; ViewModel; Store; Service)
- Module placement (app / feature / core / shared)
- Dependency injection approach
- Public API surface — what callers actually need, nothing more

### 2. Simplify pressure-test

Before finalizing, ask:

- Am I introducing abstraction with only one use site? Inline it.
- Am I adding a config option or flag for a hypothetical future? Drop it.
- Is there already a pattern in the codebase that does this? Reuse it.
- Am I adding fallback / retry / catch logic for scenarios that cannot happen? Remove it.
- Three similar call sites is fine — no helper yet.

### 3. Security threat-model

Apply the Security section from the iOS rules. Identify:

- Sensitive data touched (PII, credentials, tokens, biometrics, health, location)
- Storage surface (Keychain / UserDefaults / files / iCloud / CoreData)
- Network surface (endpoints, auth method, TLS, pinning)
- Input surface (deep links, URL schemes, universal links, pasteboard, intent / share extensions)
- Logging surface (avoid leaking via `%s` and friends)

### 4. Testing strategy

Apply the Testing section from the iOS rules. Decide:

- Behaviors to cover with Swift Testing / XCTest (list specific cases)
- Async / concurrency test coverage
- Snapshot test targets (if UI); pin device + OS
- Mock boundaries (mock at protocol interfaces, not at Apple frameworks)
- Manual device matrix and test plan

### 5. Rollout

- Feature flag? Default is **no** unless there is a real reason (A/B test, risky migration, staged rollout). Justify either way.
- Migration plan for existing users / data
- Telemetry events to add (names, properties)
- Rollback story

## Output format

A single markdown document with the 5 sections. Flag any section where you had to assume — do not silently default.

## Done when

User reviews and approves the plan. On approval, implementation proceeds. The `rules/ios.md` conventions govern code-level decisions automatically (they are imported in CLAUDE.md), so the plan does not need to re-state every standing rule.
