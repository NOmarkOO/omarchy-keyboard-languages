#!/usr/bin/env bash

set -Eeuo pipefail

readonly PLUGIN_ID="nomarkoo.keyboard-layout"
readonly REPOSITORY_URL="${NOMARKOO_KEYBOARD_REPO_URL:-https://github.com/NOmarkOO/omarchy-keyboard-languages.git}"
readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly PLUGINS_DIR="$CONFIG_ROOT/omarchy/plugins"
readonly TARGET="$PLUGINS_DIR/$PLUGIN_ID"
readonly SHELL_FILE="$CONFIG_ROOT/omarchy/shell.json"
readonly SETTINGS_DIR="$STATE_ROOT/omarchy/settings"
readonly STATE_FILE="$SETTINGS_DIR/nomarkoo-keyboard-layout.json"
readonly TOGGLE_FILE="$STATE_ROOT/omarchy/toggles/hypr/nomarkoo-keyboard-layout.lua"
readonly INSTALL_RECORD="$SETTINGS_DIR/nomarkoo-keyboard-layout-install.json"
readonly INSTALL_BACKUP_DIR="$SETTINGS_DIR/nomarkoo-keyboard-layout-install-backup"

stage=""
transaction=""
target_backup=""
old_target_head=""
shell_changed=false
target_changed=false
state_changed=false
success=false

say() { printf 'keyboard-languages: %s\n' "$*"; }
die() { printf 'keyboard-languages: %s\n' "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

canonical_origin() {
  local value=${1%/}
  value=${value%.git}
  if [[ $value =~ ^git@github\.com:(.+)$ ]]; then
    value="https://github.com/${BASH_REMATCH[1]}"
  fi
  printf '%s\n' "$value"
}

is_this_checkout() {
  local directory=$1
  [[ -f $directory/manifest.json ]] \
    && [[ $(jq -r '.id // empty' "$directory/manifest.json" 2>/dev/null) == "$PLUGIN_ID" ]] \
    && [[ -d $directory/.git ]]
}

restore_file() {
  local saved=$1 destination=$2 existed=$3
  if [[ $existed == true ]]; then
    mkdir -p -- "$(dirname -- "$destination")"
    cp -p -- "$saved" "$destination"
  else
    rm -f -- "$destination"
  fi
}

rollback() {
  local exit_code=$?
  [[ $success == true ]] && return 0
  trap - ERR INT TERM EXIT
  printf 'keyboard-languages: installation failed; restoring the previous configuration.\n' >&2

  if [[ -n $transaction && -d $transaction ]]; then
    restore_file "$transaction/shell.json" "$SHELL_FILE" "$(<"$transaction/had-shell")"
    restore_file "$transaction/state.json" "$STATE_FILE" "$(<"$transaction/had-state")"
    restore_file "$transaction/toggle.lua" "$TOGGLE_FILE" "$(<"$transaction/had-toggle")"
  fi

  if [[ $target_changed == true ]]; then
    rm -rf -- "$TARGET"
    if [[ -n $target_backup && -e $target_backup ]]; then
      mv -- "$target_backup" "$TARGET"
    fi
  fi
  if [[ -n $old_target_head && -d $TARGET/.git ]]; then
    git -C "$TARGET" reset --hard "$old_target_head" >/dev/null 2>&1 || true
  fi

  [[ -z $stage || ! -e $stage ]] || rm -rf -- "$stage"
  if [[ ${NOMARKOO_SKIP_SHELL_RESTART:-0} != 1 ]] && command -v omarchy >/dev/null 2>&1; then
    omarchy restart shell >/dev/null 2>&1 || true
  fi
  exit "$exit_code"
}

trap rollback ERR INT TERM EXIT

require git
require jq
require rg
require xkbcli
require omarchy
[[ -f $SHELL_FILE ]] || die "Omarchy shell configuration was not found at $SHELL_FILE"

mkdir -p -- "$PLUGINS_DIR" "$SETTINGS_DIR" "$(dirname -- "$TOGGLE_FILE")"
transaction=$(mktemp -d --tmpdir="$SETTINGS_DIR" .nomarkoo-keyboard-install.XXXXXX)

if [[ -f $SHELL_FILE ]]; then
  cp -p -- "$SHELL_FILE" "$transaction/shell.json"
  printf 'true' >"$transaction/had-shell"
else
  : >"$transaction/shell.json"
  printf 'false' >"$transaction/had-shell"
fi
if [[ -f $STATE_FILE ]]; then
  cp -p -- "$STATE_FILE" "$transaction/state.json"
  printf 'true' >"$transaction/had-state"
else
  : >"$transaction/state.json"
  printf 'false' >"$transaction/had-state"
fi
if [[ -f $TOGGLE_FILE ]]; then
  cp -p -- "$TOGGLE_FILE" "$transaction/toggle.lua"
  printf 'true' >"$transaction/had-toggle"
else
  : >"$transaction/toggle.lua"
  printf 'false' >"$transaction/had-toggle"
fi

script_dir=""
if [[ ${BASH_SOURCE[0]:-} != /dev/fd/* ]]; then
  candidate_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)
  if [[ -n $candidate_dir ]] && is_this_checkout "$candidate_dir"; then
    script_dir=$candidate_dir
  fi
fi

expected_origin=$(canonical_origin "$REPOSITORY_URL")
if [[ -e $TARGET && -d $TARGET/.git ]]; then
  installed_origin=$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)
  [[ -n $installed_origin ]] || die "The installed plugin has no origin remote: $TARGET"
  [[ $(canonical_origin "$installed_origin") == "$expected_origin" ]] \
    || die "Plugin id $PLUGIN_ID belongs to a different Git repository at $TARGET; nothing was overwritten."
  [[ -z $(git -C "$TARGET" status --porcelain) ]] \
    || die "The installed plugin has local changes. Commit or discard them before updating."

  if [[ $script_dir != "$TARGET" ]]; then
    old_target_head=$(git -C "$TARGET" rev-parse HEAD)
    git -C "$TARGET" fetch --quiet origin main
    git -C "$TARGET" merge --ff-only FETCH_HEAD >/dev/null
  fi
  checkout=$TARGET
  say "Using the existing Git-managed plugin checkout."
else
  stage="$PLUGINS_DIR/.${PLUGIN_ID}.install.$$"
  rm -rf -- "$stage"
  if [[ -n $script_dir ]]; then
    git clone --quiet --no-local -- "$script_dir" "$stage"
    git -C "$stage" remote set-url origin "$REPOSITORY_URL"
  else
    git clone --quiet --depth 1 --branch main -- "$REPOSITORY_URL" "$stage"
  fi
  checkout=$stage
fi

omarchy plugin validate "$checkout" >/dev/null
helper="$checkout/bin/nomarkoo-keyboard-layout"
patcher="$checkout/bin/patch-shell-json"
[[ -x $helper && -x $patcher ]] || die 'The repository is missing its executable keyboard helpers.'

if [[ -f $STATE_FILE ]]; then
  payload=$(jq -ce '
    {version: 1, layouts: [.layouts[] | {layout, variant}], switchOption, nonGroupOptions}
    | select(.layouts | length > 0)
  ' "$STATE_FILE") || die "Existing keyboard state is invalid: $STATE_FILE"
elif [[ -f $TOGGLE_FILE ]]; then
  payload=$("$helper" migrate-toggle "$TOGGLE_FILE")
else
  payload=$("$helper" snapshot-current)
fi

active_index=$("$helper" current-index)
"$helper" install-json "$(jq -c . <<<"$payload")" "$active_index" >/dev/null
state_changed=true

if [[ ! -f $INSTALL_RECORD ]]; then
  mkdir -p -- "$INSTALL_BACKUP_DIR"
  cp -p -- "$transaction/shell.json" "$INSTALL_BACKUP_DIR/shell.json.before-install"
  if [[ $(<"$transaction/had-state") == true ]]; then
    cp -p -- "$transaction/state.json" "$INSTALL_BACKUP_DIR/keyboard-state.before-install.json"
  fi
  if [[ $(<"$transaction/had-toggle") == true ]]; then
    cp -p -- "$transaction/toggle.lua" "$INSTALL_BACKUP_DIR/keyboard-toggle.before-install.lua"
  fi
fi

if [[ $checkout == "$stage" ]]; then
  if [[ -e $TARGET ]]; then
    target_backup="$PLUGINS_DIR/.${PLUGIN_ID}.bak.$(date -u +%Y%m%d%H%M%S)"
    mv -- "$TARGET" "$target_backup"
    say "Backed up the previous copied plugin to $target_backup"
  fi
  mv -- "$stage" "$TARGET"
  stage=""
  checkout=$TARGET
  target_changed=true
fi

shell_candidate=$(mktemp --tmpdir="$(dirname -- "$SHELL_FILE")" .shell.json.XXXXXX)
"$TARGET/bin/patch-shell-json" "$SHELL_FILE" "$shell_candidate"
if ! cmp -s -- "$SHELL_FILE" "$shell_candidate"; then
  shell_backup="$SHELL_FILE.bak.$(date -u +%Y%m%d%H%M%S)"
  cp -p -- "$SHELL_FILE" "$shell_backup"
  mv -- "$shell_candidate" "$SHELL_FILE"
  shell_changed=true
  say "Backed up shell.json to $shell_backup"
else
  rm -f -- "$shell_candidate"
fi

jq -n \
  --arg installedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repository "$REPOSITORY_URL" \
  --arg pluginBackup "$target_backup" \
  '{version:1, installedAt:$installedAt, repository:$repository, previousPluginBackup:$pluginBackup}' \
  >"$INSTALL_RECORD"
chmod 0644 "$INSTALL_RECORD"

legacy_helper="$HOME/.local/bin/nomarkoo-keyboard-layout"
if [[ -f $legacy_helper ]] \
  && rg -q 'nomarkoo-keyboard-layout\.lock' "$legacy_helper" \
  && ! cmp -s -- "$legacy_helper" "$TARGET/bin/nomarkoo-keyboard-layout"; then
  legacy_backup="$legacy_helper.bak.$(date -u +%Y%m%d%H%M%S)"
  mv -- "$legacy_helper" "$legacy_backup"
  say "Archived the legacy PATH helper at $legacy_backup"
fi

if [[ ${NOMARKOO_SKIP_SHELL_RESTART:-0} != 1 ]]; then
  omarchy restart shell >/dev/null \
    || die 'The plugin was installed, but the Omarchy shell could not be restarted.'
fi

success=true
trap - ERR INT TERM EXIT
rm -rf -- "$transaction"
say "Installed $PLUGIN_ID from $REPOSITORY_URL"
say 'Left-click switches language; right-click opens the manager.'
