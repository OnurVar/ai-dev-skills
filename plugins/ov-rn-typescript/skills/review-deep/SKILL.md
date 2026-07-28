---
description: Comprehensive review of pending React Native TypeScript changes. Runs RN-TS-specific pre-check, /pr-review-toolkit:review-pr, /security-review, /simplify, and /code-review:code-review (adapted for local diff when no PR). Filters out style, nits, linter-catchable issues, and findings below 80% confidence. Invoke when reviewing RN TypeScript changes before commit or after creating a PR. For a lightweight one-pass review of a GitHub PR instead, use /ov-pr-review-quick.
---

# /ov-rn-typescript-review-deep

Full review pipeline over the current pending changes to React Native TypeScript code.

## Preconditions

`rules/rn-typescript.md` should be imported via the project's CLAUDE.md (run `/ov-rn-typescript-init` if not). Any reviewer that reads CLAUDE.md picks up the RN TypeScript scope and `## Review behavior` filter rules automatically.

## Pipeline

Run every step. Aggregate and filter at the end. If a companion tool is not installed, note it in the Status block and continue with the remaining steps.

### 1. RN TypeScript-specific pre-check (inline)

Scan `git diff` for RN/React/TypeScript concerns that generic reviewers miss:

- Infinite render loops — `setState` called during render (outside `useEffect` / event handler)
- Unmounted-component `setState` — async work in `useEffect` without an `AbortController` or `isMounted` guard
- `FlatList` / `SectionList` with index-based `keyExtractor` on mutable data, or missing `keyExtractor` when stable IDs exist
- Component defined inside another component (unmounts and remounts on every parent render; destroys state / refs / focus)
- `{value && <Comp/>}` landmines — `value` could be `0`, `""`, `NaN`, which render as text instead of nothing; force `Boolean(value)` or `!!value`
- `any` added without a justification comment; `as Type` cast where narrowing or a type predicate would work
- Secrets / tokens in `AsyncStorage` (always Critical); sensitive data anywhere but Keychain / SecureStore
- Deep-link / universal-link handler without scheme + path validation
- `WebView` with `javaScriptEnabled: true` + non-whitelisted source, missing `originWhitelist`
- `useEffect` dependency array with identity-unstable values (objects / arrays / functions created in render body without `useMemo` / `useCallback`)
- `useCallback` / `useMemo` applied without a downstream memo consumer (adds overhead, no benefit)
- Platform-specific logic without `.ios.ts` / `.android.ts` file split or `Platform.OS` guard
- New Architecture readiness — module / component types not declared via `codegenNativeCommands` / TurboModule spec for new code
- Untyped navigation routes; missing `linking` config for deep-link entry points
- `console.log` / `console.warn` left in production paths; unstripped `Reactotron` calls
- API keys / endpoints / signing secrets in JS bundle or `app.json` / `eas.json` without a secrets boundary

### 2. `/pr-review-toolkit:review-pr`

Invoke via the Skill tool with no extra args (it picks sub-agents per file type). Its `code-reviewer` agent reads the project CLAUDE.md, which imports our RN TypeScript rules and the review-behavior filter.

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

Combine findings from steps 1–5. Apply the filter from `rules/rn-typescript.md § Review behavior` one more time as a safety net (belt-and-suspenders): drop style, linter-catchable, pedantic, out-of-stack (native iOS/Android), pre-existing-unchanged-lines, and <80% confidence findings; keep correctness, security, RN/React/TypeScript-specific concerns, rule violations, and accessibility regressions.

De-duplicate across steps. If multiple steps flagged the same issue, keep the highest-confidence version and note the sources.

## Output

A single markdown document:

```
# React Native TypeScript review

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
