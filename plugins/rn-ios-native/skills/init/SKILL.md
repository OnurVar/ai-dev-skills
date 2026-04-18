---
description: Bootstrap React Native iOS bridge rules into the current project. Copies this plugin's rules file into the project's .claude/ directory and appends an @import line to CLAUDE.md so rules auto-load in every Claude session. Run once per project.
---

# /rn-ios-native:init

One-time setup that wires this plugin's RN iOS bridge rules into the current project's CLAUDE.md. After running this, every Claude session in the project auto-loads the bridge rules.

## Steps

1. **Verify the working directory.** Current directory must be a project root (contains `.git/`). If not, tell the user to run from their project root and stop.

2. **Ensure `.claude/` exists** in the project root. Create it if missing.

3. **Copy the rules file.**
   - Source: `${CLAUDE_PLUGIN_ROOT}/rules/rn-ios-native.md`
   - Destination: `.claude/rn-ios-native-rules.md`
   - If the destination already exists, ask the user before overwriting.

4. **Update the project CLAUDE.md.**
   - If `CLAUDE.md` is missing at the project root, create it starting with `# Project rules`.
   - Check whether `@.claude/rn-ios-native-rules.md` is already imported. If yes, tell the user and stop.
   - If not, append:
     ```
     ## React Native iOS bridge rules
     @.claude/rn-ios-native-rules.md
     ```

5. **Report to the user.** Tell them:
   - Setup is done.
   - Every future Claude session in this repo auto-loads RN iOS bridge rules.
   - Next: `/rn-ios-native:plan <module>` to plan a native module or Fabric component, `/rn-ios-native:review` to review pending changes.
   - They can edit `.claude/rn-ios-native-rules.md` for project-local overrides.
   - Re-running `/rn-ios-native:init` refreshes the rules file from upstream (will prompt before overwriting).
   - This plugin's rules are **additive** to the pure-iOS plugin. If the project also has plain iOS code, also run `/ios:init` so SwiftUI / pure-app rules are loaded too. Also run `/rn-typescript:init` for the JS-side rules.

## Notes

- `.claude/rn-ios-native-rules.md` is a project-local snapshot. Commit it with the project so teammates get the same rules.
- If the project already has a different RN-iOS-bridge rules file imported, do not remove it — add ours alongside and let the user reconcile.
- Never overwrite a file or modify CLAUDE.md without the user's explicit confirmation when any destructive change is required.
