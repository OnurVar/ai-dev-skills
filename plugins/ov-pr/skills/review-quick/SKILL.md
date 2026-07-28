---
description: Lightweight review of a GitHub PR. Reads the diff in one moderate-depth pass (no subagents), reports at most three high-value findings, and posts them as short per-line questions. Use when asked to review a GitHub PR by number or URL and the goal is the two or three things that actually matter, not a full audit. For an exhaustive review, use a heavier review skill instead.
---

# /ov-pr-review-quick

One pass, top findings only, posted as line comments. Signal over coverage.

## Args

`$ARGUMENTS` may be a PR number, a PR URL, or empty (then use the PR for the current branch: `gh pr view --json number`).

Strip any `/files`, `/changes`, or `#discussion_r...` suffix from a pasted URL.

## 1. Read the diff

```bash
gh pr view <n> --json title,body,author,baseRefName,additions,deletions,changedFiles,state
gh pr diff <n> --name-only
gh pr diff <n> > <scratchpad>/pr<n>.diff
gh repo view --json nameWithOwner -q .nameWithOwner   # <owner>/<repo> for step 5
```

If a pasted URL points at a repo other than the working directory, take `<owner>/<repo>` from the URL and pass `--repo <owner>/<repo>` to every `gh pr` call.

Read the whole diff yourself, at moderate depth: every file gets read once and understood; no file gets interrogated. Do not spawn subagents — a single reader holding the entire change is what lets cross-file problems surface.

If the diff is too large to hold in one pass (>2000 lines), say so and recommend a heavier review skill rather than silently sampling.

## 2. What qualifies as a finding

The bar is **obvious trigger, cheap confirmation**.

Obvious trigger: an attentive reader would notice it reading the file once. Visible on the line, not inferred from a model of the system.

Cheap confirmation: before it earns a slot, sanity-check it.
- Depends on how another function behaves → open that file and read it.
- Depends on a language or stdlib detail → prove it with a three-line snippet in the scratchpad, using whatever the project's toolchain is.
- Depends on being reachable → find a caller. If you can't, call it latent rather than asserting impact.

Following one lead into one other file is in budget. Investigating a subsystem is not.

If it doesn't hold up, drop it. A confident wrong finding costs more than a missed one.

Report:
- Correctness, crashes, data loss, security
- Broken contracts — serialization round-trips that aren't symmetric, protocol/interface violations, API misuse
- Missing tolerance in code that parses untrusted or server-controlled input

Do not report:
- Style, formatting, naming — the formatter and linter own these
- Anything the compiler or linter already catches
- Pre-existing issues on lines this PR didn't touch
- Test coverage gaps, unless the untested path is one of your findings
- Anything you'd prefix with "consider" or "might be nice"
- Anything requiring a deliberate hunt to find — races, domain-logic errors, performance you'd have to measure

## 3. Pick at most three

Hard cap. Rank by blast radius — crashes and wrong behavior in shipped code beat everything else. Fewer than three is fine; zero is fine. Never pad.

If several findings share a root cause, name the theme once — it's more useful than three instances, and it belongs in the review body rather than repeated per comment.

Minor-but-real observations get **one line total** at the bottom, explicitly labeled as minor. Omit that line entirely if there are none.

If nothing survives, say so plainly.

## 4. Draft the comments

One short question per finding, anchored to the line that needs to change.

- Question form, not verdict form. "Could this return an error instead of crashing here?" gets a reply; "this is a crash risk" gets defensiveness. The author may know a constraint you don't.
- Lead with the fact the reader can't see from the line itself, then ask. Keep it to one or two sentences.
- No consequence escalation, no restating the diff, no code blocks unless the fix is shorter written than described.
- Shared context goes in the review body, not repeated in every comment.

Show every draft in chat with its `file:line`. Wait for the go-ahead before posting.

## 5. Post as one review

Write the payload to the scratchpad and post as a single `COMMENT` review so the comments arrive together:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/reviews --method POST \
  --input <scratchpad>/review.json --jq '{id, state, html_url}'
```

```json
{
  "body": "one sentence of shared framing, or omit",
  "event": "COMMENT",
  "comments": [
    { "path": "full/path/from/repo/root.ext", "line": 12, "side": "RIGHT", "body": "..." }
  ]
}
```

- `path` is repo-root-relative, exactly as `gh pr diff --name-only` prints it.
- `side: "RIGHT"` for added or existing lines; `"LEFT"` only for a deleted line.
- The line must fall inside a diff hunk or the API rejects the entire review.
- Never `event: "REQUEST_CHANGES"` or `"APPROVE"` — this skill comments, it doesn't gate.

Report the returned `html_url`.

## Revising after posting

Comments are editable, so posting isn't final:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/comments \
  --jq '.[] | select(.pull_request_review_id == <review_id>) | "\(.id) \(.path):\(.line) -> \(.body)"'
gh api repos/<owner>/<repo>/pulls/comments/<comment_id> --method PATCH -f body='...'
gh api repos/<owner>/<repo>/pulls/<n>/reviews/<review_id> --method PUT -f body='...'
```

When the user rejects wording, change only the comments they named. Don't apply the same edit to the others unless asked.

## Done when

At most three confirmed findings reported in chat, drafts approved, one review posted, `html_url` returned.
