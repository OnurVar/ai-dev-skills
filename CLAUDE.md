# ai-dev-skills

A Claude Code plugin marketplace for iOS, Android, and React Native development. Users add it via `/plugin marketplace add <this-repo>` and install the stack-specific plugins they need.

This file is the **reference point for contributors** working on this repo. It captures the design decisions we've locked in — purpose, structure, principles, review pipeline, how to add stacks, what to include and what to exclude. Read this before adding, removing, or changing any plugin.

## What this repo is

Five plugins, one per tech stack:

| Plugin | Covers | Status |
|---|---|---|
| `ios` | Native iOS (Swift / SwiftUI / UIKit / Obj-C) | Rules file drafted; skills scaffolded |
| `android` | Native Android (Kotlin / Java / Jetpack Compose) | Rules file drafted; skills scaffolded |
| `rn-typescript` | React Native TypeScript / JS layer | Rules file drafted; skills scaffolded |
| `rn-ios-native` | React Native iOS bridge (Swift / Obj-C) | Rules file drafted; skills scaffolded |
| `rn-android-native` | React Native Android bridge (Kotlin / Java) | Rules file drafted; skills scaffolded |

## Per-plugin structure (all plugins identical)

```
plugins/<stack>/
├── .claude-plugin/plugin.json
├── rules/<stack>.md              ← always-on rules, imported into user's CLAUDE.md
└── skills/
    ├── init/SKILL.md             ← /<stack>:init   — bootstraps @import into project CLAUDE.md
    ├── plan/SKILL.md             ← /<stack>:plan   — planning ritual
    └── review/SKILL.md           ← /<stack>:review — review pipeline
```

**Why this shape:**

- **`rules/<stack>.md`** — always-on knowledge. When imported into a project's CLAUDE.md, every Claude session in that project loads it automatically. It is also load-bearing for review: `/pr-review-toolkit:review-pr`, `/security-review`, `/simplify`, `/code-review:code-review` all read CLAUDE.md to know what rules to apply.
- **`skills/init/`** — the bootstrap ritual. A plugin cannot modify the user's project CLAUDE.md directly, so `/<stack>:init` copies the rules file into `.claude/<stack>-rules.md` and appends an `@import` line to the project's CLAUDE.md.
- **`skills/plan/`** — the before-implementation ritual.
- **`skills/review/`** — the after-implementation ritual; orchestrates the full pipeline.

## Design principles (non-negotiable)

1. **One command per phase, no flags.** `/<stack>:plan`, `/<stack>:review`. No `--fast` / `--deep` variants. Pick one behavior per command and make it right. If flags start creeping back, something is wrong with the default.

2. **Chain upstream plugins, don't copy.** We invoke `/pr-review-toolkit:review-pr`, built-in `/security-review`, built-in `/simplify`, and `/code-review:code-review`. We do not re-implement them. Our value is the stack-specific pre-check, the CLAUDE.md rules we inject via `init`, and the noise filter we apply.

3. **Rules live in files, not in skills.** Standing knowledge (language, concurrency, memory rules) goes in `rules/<stack>.md` and reaches the user via CLAUDE.md `@import`. Skills are for rituals (init, plan, review), not for holding rules.

4. **Reviews are high-signal only.** Every review must filter out:
   - Pure style, whitespace, formatting, import order
   - Anything a linter / formatter / compiler catches (SwiftLint, SwiftFormat, ktlint, tsc, ESLint, Xcode warnings)
   - Pedantic naming, "could be shorter" suggestions
   - Pre-existing issues on lines not in the diff
   - Findings about languages or frameworks not in the current diff
   - Low-impact nits a senior engineer would not raise
   - Anything below 80% confidence

   Every `rules/<stack>.md` has a `## Review behavior` section that encodes this filter so downstream reviewers apply it. Every `/<stack>:review` orchestrator applies the filter again in its aggregation step (belt-and-suspenders).

5. **Skills read, rules govern.** Because downstream reviewers read CLAUDE.md for rules, the CLAUDE.md `@import` chain is the load-bearing mechanism. Skills only orchestrate the pipeline.

## Review pipeline (every `/<stack>:review`)

Run these steps in order, then aggregate and filter:

1. **Stack-specific pre-check.** Inline in the skill. Catches what generic reviewers miss (e.g., `@MainActor` violations and retain cycles on iOS; lifecycle leaks on Android; bridge marshalling errors on RN).
2. **`/pr-review-toolkit:review-pr`** — invoked via the Skill tool. Picks sub-agents per file type. Reads project CLAUDE.md (which imports our rules).
3. **`/security-review`** — built-in, invoked via the Skill tool.
4. **`/simplify`** — built-in, invoked via the Skill tool.
5. **`/code-review:code-review`** — invoked via the Skill tool. Adapts to context:
   - **PR open:** runs as-designed; posts a filtered comment to the PR.
   - **No PR:** runs the 5 parallel Sonnet agents on local `git diff`; skips PR eligibility check and `gh pr comment`; returns findings to our aggregator.
6. **Aggregate + noise filter.** De-duplicate across steps, apply the filter one more time, output Critical / Important / Suggestions + a Status block noting which tools ran and where the code-review output went.

If any companion plugin is not installed, the review skill notes it and skips that step gracefully — the pipeline degrades but does not error.

## Planning ritual (every `/<stack>:plan`)

Produces a written plan before any code is written. Five required sections:

1. **Architecture decisions** — stack-specific (e.g., SwiftUI vs UIKit, Compose vs View for Android, store shape for RN)
2. **Simplify pressure-test** — avoid premature abstraction, minimize surface area, no speculative features, no backwards-compat shims without real external consumers, three similar call sites is fine
3. **Security threat-model** — sensitive data, storage, network, input surfaces specific to the stack
4. **Testing strategy** — what to test, at which boundary, with what tools
5. **Rollout** — feature flag (usually no), migration, telemetry, rollback

## What NOT to include in plugins

- **Style / formatting rules.** Delegate to SwiftLint, SwiftFormat, ktlint, Prettier, tsc, ESLint. These are linter jobs, not Claude jobs.
- **AI-prompting meta** ("be concise", "think step-by-step"). We write rules about code, not about Claude.
- **Org-specific content** (team names, Slack channels, ticket patterns, internal URLs). These belong in the user's project CLAUDE.md, never in our plugin's rules.
- **Generic platitudes.** Every rule must be specific, actionable, opinionated, and non-obvious to a senior engineer. "Write clean code" is not a rule.
- **Backwards-compat shims** for API surfaces we own. If we change a rule, change it — don't keep both.

## Adding a new stack

1. `mkdir plugins/<new-stack>` and create `.claude-plugin/plugin.json` (copy from `plugins/ios/.claude-plugin/plugin.json` and adjust name / description / keywords).
2. Digest source repos into `rules/<new-stack>.md`. Follow the iOS rules file structure (Review behavior, Architecture, language rules, Concurrency / lifecycle, Memory, Security, Testing, Accessibility, References).
   - The `## Review behavior` section is **verbatim** across stacks except for the scope sentence (which names the stack's languages / frameworks).
3. Write `skills/init/SKILL.md` — copies `rules/<stack>.md` into the project's `.claude/` directory and appends `@import` to CLAUDE.md.
4. Write `skills/plan/SKILL.md` — the 5-section planning ritual with stack-specific checklists.
5. Write `skills/review/SKILL.md` — the 6-step review pipeline.
6. Add a plugin entry in `.claude-plugin/marketplace.json`.
7. Update the "What this repo is" table above.

## How rules files are built

Source reference repos are shallow-cloned into `references/` (git-ignored). For each new stack we delegate a digest agent that reads only the mapped repos and writes the draft `rules/<stack>.md`. Stack-by-stack, not all at once — easier to review each one.

### Source repos

| Repo | Local folder | Covers |
|---|---|---|
| [steipete/agent-rules](https://github.com/steipete/agent-rules) | `references/agent-rules/` | Swift / iOS conventions, Swift 6 migration |
| [twostraws/SwiftAgents](https://github.com/twostraws/SwiftAgents) | `references/SwiftAgents/` | Modern Swift / SwiftUI idioms (Paul Hudson) |
| [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) | `references/SwiftUI-Agent-Skill/` | SwiftUI state, performance, accessibility |
| [android/nowinandroid](https://github.com/android/nowinandroid) | `references/nowinandroid/` | Google's real Android sample app + `AGENTS.md` |
| [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills) | `references/kotlin-agent-skills/` | JetBrains Kotlin idioms, AGP / R8 |
| [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills) | `references/agent-skills-vercel/` | React / TS best practices, render hazards |
| [callstackincubator/agent-skills](https://github.com/callstackincubator/agent-skills) | `references/agent-skills-callstack/` | React Native specifics, bridge patterns, brownfield |

### Stack → source repo mapping

| Stack | Source repos |
|---|---|
| `ios` | [steipete/agent-rules](https://github.com/steipete/agent-rules), [twostraws/SwiftAgents](https://github.com/twostraws/SwiftAgents), [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) |
| `android` | [android/nowinandroid](https://github.com/android/nowinandroid), [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills) |
| `rn-typescript` | [vercel-labs/agent-skills](https://github.com/vercel-labs/agent-skills), [callstackincubator/agent-skills](https://github.com/callstackincubator/agent-skills) |
| `rn-ios-native` | [steipete/agent-rules](https://github.com/steipete/agent-rules), [twostraws/SwiftAgents](https://github.com/twostraws/SwiftAgents), [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill), [callstackincubator/agent-skills](https://github.com/callstackincubator/agent-skills) |
| `rn-android-native` | [android/nowinandroid](https://github.com/android/nowinandroid), [Kotlin/kotlin-agent-skills](https://github.com/Kotlin/kotlin-agent-skills), [callstackincubator/agent-skills](https://github.com/callstackincubator/agent-skills) |

Duplicates across stacks are expected — the native-iOS rules feed both the pure iOS plugin and the RN iOS bridge plugin, for example.

Digest philosophy: extract only correctness, security, and stack-specific concerns. Drop style, formatting, AI-prompting meta, org-specific content. If a source repo contributes thin content, use senior-engineer defaults rather than pad with generic advice.

## Companion plugins (not bundled, invoked by our review skills)

Our `/<stack>:review` chain expects these to be available on the user's machine:

| Plugin | Source | Used in |
|---|---|---|
| `pr-review-toolkit` | `claude-plugins-official` marketplace | review step 2 |
| `security-review` | built-in Claude Code | review step 3 |
| `simplify` | built-in Claude Code | review step 4 |
| `code-review` | `claude-plugins-official` marketplace | review step 5 |

We do not declare these as hard dependencies in `plugin.json`. Each review skill checks at runtime and skips gracefully if a companion is missing.

## Repository layout

```
ai-dev-skills/
├── CLAUDE.md                          ← this file (contributor reference)
├── README.md                          ← end-user intro
├── .gitignore                         ← includes references/
├── .claude-plugin/
│   └── marketplace.json               ← the catalog
├── plugins/
│   ├── ios/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── rules/ios.md
│   │   └── skills/{init,plan,review}/SKILL.md
│   ├── android/
│   ├── rn-typescript/
│   ├── rn-ios-native/
│   └── rn-android-native/
└── references/                        ← shallow clones, git-ignored
    ├── agent-rules/
    ├── SwiftAgents/
    ├── SwiftUI-Agent-Skill/
    ├── nowinandroid/
    ├── kotlin-agent-skills/
    ├── agent-skills-vercel/
    └── agent-skills-callstack/
```

## When adding / changing rules

- If you're editing `rules/<stack>.md`, keep the `## Review behavior` section intact and verbatim across stacks (except the scope sentence).
- If you're adding a new rule, verify it passes the quality bar: specific, actionable, opinionated, non-obvious.
- If you're removing a rule, note in the commit message which source repo it came from (check the References section at the bottom of each rules file).
- If you're adding a new source repo, clone it into `references/` and update the stack-to-repo table above.

## When adding / changing skills

- Skills are rituals, not rules. If content feels like a standing rule, move it to `rules/<stack>.md` and have the skill reference it instead.
- Every skill has a `description` frontmatter field that governs auto-invocation. Keep it specific — vague descriptions cause spurious invocations.
- If a skill starts accumulating flags or branches, rethink. One command per phase, no flags is the rule.
