#!/usr/bin/env bash
#
# install.sh — install ai-dev-skills into ~/.claude/ without the /plugin command.
#
# Use this when /plugin marketplace commands are unavailable (company policy,
# offline environments, etc.). All 5 plugins' skills are placed at
# ~/.claude/skills/<stack>-<ritual>/, and rules files at
# ~/.claude/ai-dev-skills/rules/<stack>.md.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: ./install.sh [--symlink|--copy] [--uninstall] [--dry-run]

Install ai-dev-skills (15 skills + 5 rules files) into ~/.claude/.

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

After install, invoke skills as:

  /ios-init                 /ios-plan                 /ios-review
  /android-init             /android-plan             /android-review
  /rn-typescript-init       /rn-typescript-plan       /rn-typescript-review
  /rn-ios-native-init       /rn-ios-native-plan       /rn-ios-native-review
  /rn-android-native-init   /rn-android-native-plan   /rn-android-native-review

(Colon-to-dash: `/ios:init` under the plugin system becomes `/ios-init`
here, since user-level skills aren't plugin-namespaced.)
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

STACKS=(ios android rn-typescript rn-ios-native rn-android-native)
RITUALS=(init plan review)

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

install_all() {
    do_or_echo mkdir -p "$SKILLS_DIR" "$RULES_DIR"

    local tmp_manifest
    tmp_manifest="$(mktemp)"

    local stack ritual
    for stack in "${STACKS[@]}"; do
        for ritual in "${RITUALS[@]}"; do
            local src="$REPO/plugins/$stack/skills/$ritual"
            local dest="$SKILLS_DIR/${stack}-${ritual}"
            printf '%s\n' "$dest" >> "$tmp_manifest"
            install_entry "$src" "$dest"
        done

        local rules_src="$REPO/plugins/$stack/rules/${stack}.md"
        local rules_dest="$RULES_DIR/${stack}.md"
        printf '%s\n' "$rules_dest" >> "$tmp_manifest"
        install_entry "$rules_src" "$rules_dest"
    done

    if $DRY_RUN; then
        rm -f "$tmp_manifest"
        log ""
        log "DRY-RUN complete — no changes made."
    else
        mv "$tmp_manifest" "$MANIFEST"
        log ""
        log "Installed 15 skills + 5 rules files ($MODE mode)."
        log "Manifest: $MANIFEST"
        log ""
        log "Try:  /ios-init   /ios-plan   /ios-review"
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
