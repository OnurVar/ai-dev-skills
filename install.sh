#!/usr/bin/env bash
#
# install.sh — install ai-dev-skills into ~/.claude/ without the /plugin command.
#
# Use this when /plugin marketplace commands are unavailable (company policy,
# offline environments, etc.). All plugins' skills are placed at
# ~/.claude/skills/ov-<stack>-<ritual>/, and rules files at
# ~/.claude/ai-dev-skills/rules/<stack>.md.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: ./install.sh [--symlink|--copy] [--uninstall] [--dry-run]

Install ai-dev-skills (16 skills + 5 rules files) into ~/.claude/.

Modes:
  --symlink    (default) Symlink into this repo. Edits propagate
               automatically. Requires this repo to stay at its
               current path.
  --copy       Snapshot copy. Self-contained, repo may move or be
               deleted. Re-run after repo edits to refresh.

Actions:
  --uninstall  Remove everything this script installed (per the
               manifest at ~/.claude/ai-dev-skills/.installed).
               Leaves unrelated skills alone.
  --dry-run    Preview actions; make no changes.
  --help       Show this message.

After install, every skill is ov- prefixed, so typing `/ov` lists all of
them and nothing else:

  /ov-ios-init                 /ov-ios-plan                 /ov-ios-review-deep
  /ov-android-init             /ov-android-plan             /ov-android-review-deep
  /ov-rn-typescript-init       /ov-rn-typescript-plan       /ov-rn-typescript-review-deep
  /ov-rn-ios-native-init       /ov-rn-ios-native-plan       /ov-rn-ios-native-review-deep
  /ov-rn-android-native-init   /ov-rn-android-native-plan   /ov-rn-android-native-review-deep

  /ov-pr-review-quick   (platform-neutral lightweight PR review)

(Colon-to-dash: `/ov-ios:init` under the plugin system becomes
`/ov-ios-init` here, since user-level skills aren't plugin-namespaced.)
USAGE
}

MODE="symlink"
ACTION="install"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --symlink)    MODE="symlink" ;;
        --copy)       MODE="copy" ;;
        --uninstall)  ACTION="uninstall" ;;
        --dry-run|-n) DRY_RUN=true ;;
        --help|-h)    usage; exit 0 ;;
        *)
            echo "Unknown option: $1 (try --help)" >&2
            exit 1
            ;;
    esac
    shift
done

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
BASE_DIR="$HOME/.claude/ai-dev-skills"
RULES_DIR="$BASE_DIR/rules"
MANIFEST="$BASE_DIR/.installed"

PREFIX="ov"
STACKS=(ios android rn-typescript rn-ios-native rn-android-native)
RITUALS=(init plan review-deep)

# Platform-neutral plugins: "<plugin-dir>:<skill-dir>", no rules file.
EXTRAS=("$PREFIX-pr:review-quick")

log() { printf '%s\n' "$*"; }

do_or_echo() {
    if $DRY_RUN; then
        log "DRY-RUN: $*"
    else
        "$@"
    fi
}

is_previously_installed() {
    local path="$1"
    [[ -f "$MANIFEST" ]] && grep -Fxq "$path" "$MANIFEST"
}

install_entry() {
    local src="$1" dest="$2"

    if [[ ! -e "$src" ]]; then
        log "ERROR: source missing: $src"
        exit 1
    fi

    if [[ -L "$dest" || -e "$dest" ]]; then
        if is_previously_installed "$dest"; then
            do_or_echo rm -rf "$dest"
        else
            log "ERROR: $dest exists and was not installed by this script."
            log "       Remove it manually and re-run. (Not clobbering user content.)"
            exit 1
        fi
    fi

    if [[ "$MODE" == "symlink" ]]; then
        do_or_echo ln -s "$src" "$dest"
    else
        do_or_echo cp -R "$src" "$dest"
    fi
}

# Remove entries a previous install created that this one no longer produces
# (e.g. after a skill rename). Only touches paths the old manifest owns.
prune_stale() {
    local new_manifest="$1"
    [[ -f "$MANIFEST" ]] || return 0

    local path
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        grep -Fxq "$path" "$new_manifest" && continue
        if [[ -L "$path" || -e "$path" ]]; then
            log "Pruning renamed/removed entry from earlier install: $path"
            do_or_echo rm -rf "$path"
        fi
    done < "$MANIFEST"
}

install_all() {
    do_or_echo mkdir -p "$SKILLS_DIR" "$RULES_DIR"

    local tmp_manifest
    tmp_manifest="$(mktemp)"

    local stack ritual
    for stack in "${STACKS[@]}"; do
        local plugin="$PREFIX-$stack"

        for ritual in "${RITUALS[@]}"; do
            local src="$REPO/plugins/$plugin/skills/$ritual"
            local dest="$SKILLS_DIR/${plugin}-${ritual}"
            printf '%s\n' "$dest" >> "$tmp_manifest"
            install_entry "$src" "$dest"
        done

        local rules_src="$REPO/plugins/$plugin/rules/${stack}.md"
        local rules_dest="$RULES_DIR/${stack}.md"
        printf '%s\n' "$rules_dest" >> "$tmp_manifest"
        install_entry "$rules_src" "$rules_dest"
    done

    local extra
    for extra in "${EXTRAS[@]}"; do
        local plugin="${extra%%:*}"
        local skill="${extra##*:}"
        local src="$REPO/plugins/$plugin/skills/$skill"
        local dest="$SKILLS_DIR/${plugin}-${skill}"
        printf '%s\n' "$dest" >> "$tmp_manifest"
        install_entry "$src" "$dest"
    done

    prune_stale "$tmp_manifest"

    if $DRY_RUN; then
        rm -f "$tmp_manifest"
        log ""
        log "DRY-RUN complete — no changes made."
    else
        mv "$tmp_manifest" "$MANIFEST"
        log ""
        log "Installed 16 skills + 5 rules files ($MODE mode)."
        log "Manifest: $MANIFEST"
        log ""
        log "Try:  /ov-ios-init   /ov-ios-plan   /ov-ios-review-deep   /ov-pr-review-quick"
        if [[ "$MODE" == "symlink" ]]; then
            log "Source repo: $REPO — edits propagate automatically."
        fi
    fi
}

uninstall_all() {
    if [[ ! -f "$MANIFEST" ]]; then
        log "No manifest at $MANIFEST — nothing to uninstall."
        exit 0
    fi

    local path
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        if [[ -L "$path" || -e "$path" ]]; then
            do_or_echo rm -rf "$path"
        fi
    done < "$MANIFEST"

    do_or_echo rm -f "$MANIFEST"

    # Remove parent dirs if empty (ignore errors when non-empty).
    if ! $DRY_RUN; then
        rmdir "$RULES_DIR" 2>/dev/null || true
        rmdir "$BASE_DIR" 2>/dev/null || true
    fi

    log "Uninstalled."
}

case "$ACTION" in
    install)   install_all ;;
    uninstall) uninstall_all ;;
esac
