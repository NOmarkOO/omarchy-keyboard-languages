#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo_root/bin/nomarkoo-keyboard-layout
test_bin=$repo_root/tests/bin

fixture_output=$(mktemp)
fixture_repeat=$(mktemp)
test_root=$(mktemp -d)
trap 'rm -f -- "$fixture_output" "$fixture_repeat"; rm -rf -- "$test_root"' EXIT
"$repo_root/bin/patch-shell-json" \
  "$repo_root/tests/fixtures/shell-before.json" \
  "$fixture_output"
"$repo_root/bin/patch-shell-json" "$fixture_output" "$fixture_repeat"
cmp -s -- "$fixture_output" "$fixture_repeat"
jq -e '
  .bar.customSetting == "preserve-me" and
  .idle.lock == 777 and
  .bar.layout.left[0].untouched == true and
  .bar.layout.center[0].format == "HH:mm" and
  .bar.layout.center[1] == {id: "omarchy.weather"} and
  .bar.layout.right[0] == {id: "nomarkoo.keyboard-layout"} and
  .bar.layout.right[1] == {id: "omarchy.tray"} and
  .bar.layout.right[2] == {id: "omarchy.network"} and
  ([.bar.layout[]?[]? | select(.id == "nomarkoo.keyboard-layout")] | length) == 1 and
  ([.bar.layout[]?[]? | select(.id == "omarchy.keyboard-layout")] | length) == 0
' "$fixture_output" >/dev/null

export XDG_STATE_HOME=$test_root/state
export PATH=$test_bin:$PATH
export NOMARKOO_TEST_HYPR_LOG=$test_root/hyprctl.log

snapshot_root=$test_root/snapshot-state
XDG_STATE_HOME=$snapshot_root \
NOMARKOO_TEST_HYPR_MODE=live \
NOMARKOO_TEST_LAYOUTS=us,de \
NOMARKOO_TEST_VARIANTS=,nodeadkeys \
NOMARKOO_TEST_OPTIONS=compose:caps,grp:ctrl_shift_toggle \
  "$helper" status | jq -e '
    .layouts == [
      {layout:"us", variant:"", latin:true},
      {layout:"de", variant:"nodeadkeys", latin:true}
    ] and
    .switchOption == "grp:ctrl_shift_toggle" and
    .nonGroupOptions == ["compose:caps"]
  ' >/dev/null
[[ -f $snapshot_root/omarchy/settings/nomarkoo-keyboard-layout.json ]]

initial=$(jq -c . "$repo_root/tests/fixtures/state.json")
"$helper" migrate-toggle "$repo_root/tests/fixtures/legacy-toggle.lua" | jq -e '
  .layouts == [{layout: "us", variant: ""}, {layout: "ru", variant: ""}] and
  .switchOption == "grp:alt_shift_toggle" and
  .nonGroupOptions == ["compose:caps", "shift:both_capslock_cancel"]
' >/dev/null
"$helper" install-json "$initial" 0 >/dev/null
"$helper" status | jq -e '
  .layouts[0].latin == true and .layouts[1].latin == false and
  .switchOption == "grp:alt_shift_toggle"
' >/dev/null

# Bar aliases are per configured entry and update state metadata without
# compiling, applying, or otherwise touching the live keymap and toggle.
state_file=$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json
toggle_file=$XDG_STATE_HOME/omarchy/toggles/hypr/nomarkoo-keyboard-layout.lua
toggle_stamp=$(stat -c '%i:%y:%s' "$toggle_file")
: >"$NOMARKOO_TEST_HYPR_LOG"
NOMARKOO_TEST_HYPR_MODE=live "$helper" alias 0 "  Work  " | jq -e '
  .layouts[0].alias == "Work" and (.layouts[1] | has("alias") | not)
' >/dev/null
NOMARKOO_TEST_HYPR_MODE=live "$helper" alias 1 "РУС" | jq -e '
  .layouts[0].alias == "Work" and .layouts[1].alias == "РУС"
' >/dev/null
[[ ! -s $NOMARKOO_TEST_HYPR_LOG ]]
[[ $toggle_stamp == "$(stat -c '%i:%y:%s' "$toggle_file")" ]]

state_stamp=$(stat -c '%i:%y:%s' "$state_file")
"$helper" alias 1 "РУС" >/dev/null
[[ $state_stamp == "$(stat -c '%i:%y:%s' "$state_file")" ]]

before_invalid=$(sha256sum "$state_file")
for invalid_alias in 1234567 $'bad\talias'; do
  if "$helper" alias 0 "$invalid_alias" >/dev/null 2>&1; then
    printf 'An invalid bar alias unexpectedly succeeded.\n' >&2
    exit 1
  fi
done
if "$helper" alias 99 nope >/dev/null 2>&1; then
  printf 'A bar alias for a missing language unexpectedly succeeded.\n' >&2
  exit 1
fi
invalid_alias_state=$(jq -c '.layouts[0].alias = false' "$state_file")
if "$helper" install-json "$invalid_alias_state" 0 >/dev/null 2>&1; then
  printf 'A non-string persisted bar alias unexpectedly succeeded.\n' >&2
  exit 1
fi
[[ $before_invalid == "$(sha256sum "$state_file")" ]]

"$helper" alias 0 "" | jq -e '(.layouts[0] | has("alias") | not) and .layouts[1].alias == "РУС"' >/dev/null
"$helper" alias 1 "" | jq -e 'all(.layouts[]; has("alias") | not)' >/dev/null
[[ ! -s $NOMARKOO_TEST_HYPR_LOG ]]
[[ $toggle_stamp == "$(stat -c '%i:%y:%s' "$toggle_file")" ]]

# Regression: neither action relies on the old shell.json-only `latin` field.
"$helper" shortcut grp:ctrl_shift_toggle >/dev/null
"$helper" add de "" >/dev/null
jq -e '
  .switchOption == "grp:ctrl_shift_toggle" and
  .layouts == [
    {layout: "us", variant: ""},
    {layout: "ru", variant: ""},
    {layout: "de", variant: ""}
  ]
' "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json" >/dev/null

"$helper" remove 2 >/dev/null
before=$(sha256sum "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")
if "$helper" remove 0 >/dev/null 2>&1; then
  printf 'Removing the required leading Latin layout unexpectedly succeeded.\n' >&2
  exit 1
fi
after=$(sha256sum "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")
[[ "$before" == "$after" ]]

if "$helper" shortcut grp:not_real_toggle >/dev/null 2>&1; then
  printf 'An unsupported XKB shortcut unexpectedly succeeded.\n' >&2
  exit 1
fi
after_invalid=$(sha256sum "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")
[[ "$before" == "$after_invalid" ]]

NOMARKOO_TEST_HYPR_MODE=reject "$helper" shortcut grp:alt_shift_toggle >/dev/null 2>&1 && {
  printf 'A rejected Hyprland configuration unexpectedly succeeded.\n' >&2
  exit 1
}
after_reject=$(sha256sum "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")
[[ "$before" == "$after_reject" ]]
rg -q 'eval hl\.config\(\{ misc = \{ disable_autoreload = true \}' "$NOMARKOO_TEST_HYPR_LOG"
rg -q 'eval hl\.config\(\{ input = .*grp:alt_shift_toggle' "$NOMARKOO_TEST_HYPR_LOG"
rg -q 'eval hl\.config\(\{ input = .*grp:ctrl_shift_toggle' "$NOMARKOO_TEST_HYPR_LOG"
rg -q 'eval hl\.config\(\{ misc = \{ disable_autoreload = false \}' "$NOMARKOO_TEST_HYPR_LOG"
if rg -q '(^| )reload($| )|configerrors' "$NOMARKOO_TEST_HYPR_LOG"; then
  printf 'Rejected keyboard change attempted a full Hyprland reload.\n' >&2
  exit 1
fi

: >"$NOMARKOO_TEST_HYPR_LOG"
NOMARKOO_TEST_HYPR_MODE=live "$helper" shortcut grp:alt_shift_toggle >/dev/null
jq -e '.switchOption == "grp:alt_shift_toggle"' \
  "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json" >/dev/null
rg -q 'eval hl\.config\(\{ input = .*grp:alt_shift_toggle' "$NOMARKOO_TEST_HYPR_LOG"
if rg -q '(^| )reload($| )|configerrors' "$NOMARKOO_TEST_HYPR_LOG"; then
  printf 'Successful keyboard change attempted a full Hyprland reload.\n' >&2
  exit 1
fi

"$helper" shortcut grp:alt_shift_toggle >/dev/null &
first_pid=$!
"$helper" shortcut grp:ctrl_shift_toggle >/dev/null &
second_pid=$!
wait "$first_pid" "$second_pid"
jq -e '.switchOption == "grp:alt_shift_toggle" or .switchOption == "grp:ctrl_shift_toggle"' \
  "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json" >/dev/null

# Regression: reinstalling identical state must not replace a live keymap.
delete_state_root=$test_root/delete-state
export XDG_STATE_HOME=$delete_state_root
delete_payload='{"version":1,"layouts":[{"layout":"us","variant":""},{"layout":"ru","variant":""},{"layout":"de","variant":""}],"switchOption":"grp:alt_shift_toggle","nonGroupOptions":["compose:caps","shift:both_capslock_cancel"]}'
NOMARKOO_TEST_HYPR_MODE=offline "$helper" install-json "$delete_payload" 2 >/dev/null
: >"$NOMARKOO_TEST_HYPR_LOG"
state_stamp=$(stat -c '%y:%s' "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")
toggle_stamp=$(stat -c '%y:%s' "$XDG_STATE_HOME/omarchy/toggles/hypr/nomarkoo-keyboard-layout.lua")
NOMARKOO_TEST_HYPR_MODE=live NOMARKOO_TEST_ACTIVE_INDEX=2 \
  "$helper" install-json "$delete_payload" 2 >/dev/null
[[ $state_stamp == "$(stat -c '%y:%s' "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")" ]]
[[ $toggle_stamp == "$(stat -c '%y:%s' "$XDG_STATE_HOME/omarchy/toggles/hypr/nomarkoo-keyboard-layout.lua")" ]]
if rg -q 'eval|switchxkblayout' "$NOMARKOO_TEST_HYPR_LOG"; then
  printf 'An identical install unexpectedly touched the live keymap.\n' >&2
  exit 1
fi

# Regression: deletion first selects an old index that survives the shorter
# list, applies the same targeted input update as add, then selects the new
# intended index. It never reloads Hyprland.
: >"$NOMARKOO_TEST_HYPR_LOG"
NOMARKOO_TEST_HYPR_MODE=live NOMARKOO_TEST_ACTIVE_INDEX=2 "$helper" remove 1 >/dev/null
jq -e '.layouts == [{layout: "us", variant: ""}, {layout: "de", variant: ""}]' \
  "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json" >/dev/null
safe_line=$(rg -n -F 'switchxkblayout test-keyboard 0' "$NOMARKOO_TEST_HYPR_LOG" | head -n1 | cut -d: -f1)
aux_safe_line=$(rg -n -F 'switchxkblayout power-button 0' "$NOMARKOO_TEST_HYPR_LOG" | head -n1 | cut -d: -f1)
apply_line=$(rg -n -F 'kb_layout = "us,de"' "$NOMARKOO_TEST_HYPR_LOG" | head -n1 | cut -d: -f1)
final_line=$(rg -n -F 'switchxkblayout test-keyboard 1' "$NOMARKOO_TEST_HYPR_LOG" | tail -n1 | cut -d: -f1)
[[ -n $safe_line && -n $aux_safe_line && -n $apply_line && -n $final_line ]]
(( safe_line < apply_line && aux_safe_line < apply_line && apply_line < final_line ))
if rg -q '(^| )reload($| )|configerrors' "$NOMARKOO_TEST_HYPR_LOG"; then
  printf 'Layout deletion attempted a full Hyprland reload.\n' >&2
  exit 1
fi

# A rejected shrink restores both persisted state and the former live index.
NOMARKOO_TEST_HYPR_MODE=offline "$helper" install-json "$delete_payload" 2 >/dev/null
: >"$NOMARKOO_TEST_HYPR_LOG"
NOMARKOO_TEST_HYPR_MODE=reject-shrink NOMARKOO_TEST_ACTIVE_INDEX=2 \
  "$helper" remove 1 >/dev/null 2>&1 && {
    printf 'A rejected layout deletion unexpectedly succeeded.\n' >&2
    exit 1
  }
jq -e '.layouts == [{layout: "us", variant: ""}, {layout: "ru", variant: ""}, {layout: "de", variant: ""}]' \
  "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json" >/dev/null
rg -q -F 'kb_layout = "us,ru,de"' "$NOMARKOO_TEST_HYPR_LOG"
rg -q -F 'switchxkblayout test-keyboard 2' "$NOMARKOO_TEST_HYPR_LOG"
if rg -q '(^| )reload($| )|configerrors' "$NOMARKOO_TEST_HYPR_LOG"; then
  printf 'Rejected layout deletion attempted a full Hyprland reload.\n' >&2
  exit 1
fi



printf 'helper integration tests passed.\n'
