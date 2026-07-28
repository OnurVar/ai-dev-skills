---
description: Plan a React Native TypeScript feature or change before writing code. Produces architecture decisions, simplify pressure-test, security threat-model, testing strategy, and rollout plan. Invoke before starting any non-trivial RN TypeScript work.
---

# /ov-rn-typescript-plan

Produce an implementation plan for React Native TypeScript work **before any code is written**.

## Input

`$ARGUMENTS` — the feature or change description. If empty, ask the user what to plan.

## Preconditions

The RN TypeScript rules (`rules/rn-typescript.md` from this plugin) should be loaded via the project's CLAUDE.md. If `@.claude/rn-typescript-rules.md` is not imported in CLAUDE.md, suggest the user run `/ov-rn-typescript-init` first, then stop.

## Output sections (produce all five)

### 1. Architecture decisions

Apply the Architecture and React sections from the rules. Decide:

- Component shape — screen / container / leaf, where state lives
- State management approach (Context + hooks, Zustand, Jotai, Redux Toolkit, React Query for server state — pick one, justify)
- Navigation shape (Stack / Tab / Drawer; typed routes; deep-link entry points)
- TypeScript types for the feature — discriminated unions for UI state, Zod (or similar) for boundary validation
- Module boundaries (feature folder, shared vs local, barrel exports or not)
- Does this feature require a native module? If yes, flag it for `/ov-rn-ios-native-plan` and `/ov-rn-android-native-plan` follow-ups.

### 2. Simplify pressure-test

Before finalizing, ask:

- Am I introducing abstraction with only one use site? Inline it.
- Am I wrapping every callback in `useCallback` / every value in `useMemo` without a downstream memo consumer? Drop it.
- Am I adding a config option or flag for a hypothetical future? Drop it.
- Is there already a pattern in the codebase that does this? Reuse it.
- Am I adding fallback / retry / catch logic for scenarios that cannot happen? Remove it.
- Three similar call sites is fine — no helper yet.

### 3. Security threat-model

Apply the Security section from the rules. Identify:

- Sensitive data touched (PII, credentials, tokens, biometrics, location, health)
- Storage surface (`AsyncStorage` is plaintext — sensitive data goes to Keychain / SecureStore; react-native-mmkv for large non-sensitive)
- Network surface (endpoints, auth method, TLS, cert pinning — typically via native layer or `react-native-ssl-pinning`)
- Input surface (deep links, universal links, share extensions, pasteboard, WebView messages)
- Bundle surface — no secrets or API keys in the JS bundle (it ships to the device; extractable)
- OTA update signing (CodePush / EAS Update signature verification)

### 4. Testing strategy

Apply the Testing section from the rules. Decide:

- Unit tests for pure logic (reducers, selectors, utils) — Jest
- Component tests — React Native Testing Library with `userEvent` over `fireEvent`; query priority `getByRole` > `getByLabelText` > `getByText`
- Network stubs — MSW for declarative handler setup
- E2E — Detox / Maestro only for high-value flows (login, checkout, critical journeys) — not for every screen
- Coverage of hooks (use `renderHook`) and native module mocks (jest automocks + manual overrides)

### 5. Rollout

- Feature flag? Default is **no** unless there's a real reason (A/B test, risky migration, staged rollout). Justify either way.
- Migration plan for persisted data (MMKV / AsyncStorage schema changes, server-driven state)
- Telemetry events to add (names, properties)
- OTA-compatible vs requires a native rebuild — state clearly which
- Rollback story (OTA rollback vs store rollback)

## Output format

A single markdown document with the 5 sections. Flag any section where you had to assume — do not silently default.

## Done when

User reviews and approves the plan. On approval, implementation proceeds. The `rules/rn-typescript.md` conventions govern code-level decisions automatically (they are imported in CLAUDE.md), so the plan does not need to re-state every standing rule.
