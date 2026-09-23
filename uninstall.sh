#!/usr/bin/env bash

set -Eeuo pipefail

readonly PLUGIN_ID="nomarkoo.keyboard-layout"
readonly CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}"
readonly TARGET="$CONFIG_ROOT/omarchy/plugins/$PLUGIN_ID"
readonly SHELL_FILE="$CONFIG_ROOT/omarchy/shell.json"
readonly STATE_FILE="$STATE_ROOT/omarchy/settings/nomarkoo-keyboard-layout.json"
readonly TOGGLE_FILE="$STATE_ROOT/omarchy/toggles/hypr/nomarkoo-keyboard-layout.lua"
readonly LOCK_FILE="$STATE_ROOT/omarchy/settings/nomarkoo-keyboard-layout.lock"
readonly INSTALL_RECORD="$STATE_ROOT/omarchy/settings/nomarkoo-keyboard-layout-install.json"
readonly UI_PREFS_FILE="$STATE_ROOT/omarchy/settings/nomarkoo-keyboard-layout-ui.json"

purge=false
case "${1:-}" in
  "") ;;
  --purge-state) purge=true ;;
  -h|--help)
    printf 'Usage: %s [--purge-state]\n' "$0"
    exit 0
    ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

command -v jq >/dev/null 2>&1 || { printf 'uninstall: jq is required.\n' >&2; exit 1; }
command -v omarchy >/dev/null 2>&1 || { printf 'uninstall: Omarchy Quattro is required.\n' >&2; exit 1; }
[[ -f $SHELL_FILE ]] || { printf 'uninstall: shell.json was not found at %s\n' "$SHELL_FILE" >&2; exit 1; }

if [[ $purge == true ]] && command -v hyprctl >/dev/null 2>&1 && hyprctl -j devices >/dev/null 2>&1; then
  printf '%s\n' \
    'uninstall: refusing to remove the live keyboard override inside a running Hyprland session.' \
    'Run the normal uninstall now, then use --purge-state after logging out if you also want to remove saved keyboard settings.' >&2
  exit 1
fi

shell_backup="$SHELL_FILE.bak.$(date -u +%Y%m%d%H%M%S)"
shell_candidate=$(mktemp --tmpdir="$(dirname -- "$SHELL_FILE")" .shell.json.XXXXXX)
jq '
  def entry_id:
    if type == "object" then (.id // "" | tostring) else tostring end;
  {id: "omarchy.keyboard-layout"} as $stock
  | .bar.layout |= with_entries(
      .value |= map(select((entry_id == "nomarkoo.keyboard-layout" or entry_id == "omarchy.keyboard-layout") | not))
    )
  | .bar.layout.right |= (
      (map(entry_id) | index("omarchy.tray")) as $tray
      | if $tray == null then [$stock] + .
        else .[0:$tray] + [$stock] + .[$tray:]
        end
    )
' "$SHELL_FILE" >"$shell_candidate"
jq -e . "$shell_candidate" >/dev/null

cp -p -- "$SHELL_FILE" "$shell_backup"
mv -- "$shell_candidate" "$SHELL_FILE"

plugin_backup=""
if [[ -e $TARGET ]]; then
  plugin_backup="$(dirname -- "$TARGET")/.${PLUGIN_ID}.uninstalled.$(date -u +%Y%m%d%H%M%S)"
  mv -- "$TARGET" "$plugin_backup"
fi

if [[ $purge == true ]]; then
  rm -f -- "$STATE_FILE" "$TOGGLE_FILE" "$LOCK_FILE" "$INSTALL_RECORD" "$UI_PREFS_FILE"
fi

if [[ ${NOMARKOO_SKIP_SHELL_RESTART:-0} != 1 ]]; then
  omarchy restart shell >/dev/null || {
    cp -p -- "$shell_backup" "$SHELL_FILE"
    [[ -z $plugin_backup ]] || mv -- "$plugin_backup" "$TARGET"
    printf 'uninstall: shell restart failed; the previous installation was restored.\n' >&2
    exit 1
  }
fi

printf 'Restored the stock Omarchy keyboard indicator.\n'
printf 'Shell backup: %s\n' "$shell_backup"
if [[ -n $plugin_backup ]]; then
  printf 'Recoverable plugin backup: %s\n' "$plugin_backup"
fi
if [[ $purge == false ]]; then
  printf 'Keyboard layouts and shortcut were preserved. Use --purge-state after logging out to remove them.\n'
fi
