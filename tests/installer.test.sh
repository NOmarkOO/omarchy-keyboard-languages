#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

export PATH="$repo_root/tests/bin:/usr/share/omarchy/bin:$PATH"
export NOMARKOO_TEST_HYPR_LOG="$test_root/hyprctl.log"
export NOMARKOO_TEST_OMARCHY_LOG="$test_root/omarchy.log"

repository_url=https://github.com/NOmarkOO/omarchy-keyboard-languages.git
fixture_remote="$test_root/fixture-remote"
mkdir -p -- "$fixture_remote"
cp -R -- "$repo_root/." "$fixture_remote/"
rm -rf -- "$fixture_remote/.git"
git -C "$fixture_remote" init -q
git -C "$fixture_remote" config user.name 'Installer tests'
git -C "$fixture_remote" config user.email 'installer-tests@example.invalid'
git -C "$fixture_remote" add .
git -C "$fixture_remote" commit -qm 'Fixture release one'
fixture_commit_one=$(git -C "$fixture_remote" rev-parse HEAD)
printf 'release two\n' >"$fixture_remote/release-marker.txt"
git -C "$fixture_remote" add release-marker.txt
git -C "$fixture_remote" commit -qm 'Fixture release two'
fixture_commit_two=$(git -C "$fixture_remote" rev-parse HEAD)

export GIT_CONFIG_GLOBAL="$test_root/gitconfig"
git config --global protocol.file.allow always
git config --global url."file://$fixture_remote".insteadOf "$repository_url"

prepare_home() {
  local name=$1
  export HOME="$test_root/$name/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p -- "$XDG_CONFIG_HOME/omarchy" "$XDG_STATE_HOME"
  cp -- "$repo_root/tests/fixtures/shell-before.json" "$XDG_CONFIG_HOME/omarchy/shell.json"
}

assert_installed() {
  local expected_commit=$1
  [[ -d $XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout/.git ]]
  [[ -x $XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout/bin/nomarkoo-keyboard-layout ]]
  [[ $(git -C "$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout" rev-parse HEAD) == "$expected_commit" ]]
  [[ -z $(git -C "$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout" symbolic-ref --quiet HEAD 2>/dev/null || true) ]]
  jq -e '
    .bar.layout.right[0].id == "nomarkoo.keyboard-layout" and
    .bar.layout.right[1].id == "omarchy.tray" and
    ([.bar.layout[]?[]? | select(.id == "omarchy.keyboard-layout")] | length) == 0
  ' "$XDG_CONFIG_HOME/omarchy/shell.json" >/dev/null
  jq -e '
    .layouts == [{layout:"us",variant:""},{layout:"ru",variant:"phonetic"}] and
    .switchOption == "grp:ctrl_shift_toggle" and
    .nonGroupOptions == ["compose:caps"]
  ' "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json" >/dev/null
  jq -e --arg commit "$expected_commit" '
    .version == 2 and .commit == $commit and
    .repository == "https://github.com/NOmarkOO/omarchy-keyboard-languages.git"
  ' "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout-install.json" >/dev/null
}

run_installer() {
  local commit=$1
  git -C "$fixture_remote" checkout -q --detach "$commit"
  NOMARKOO_SKIP_SHELL_RESTART=1 "$fixture_remote/install.sh" --commit "$commit"
}

# Mutable refs and abbreviated or missing commits are rejected before mutation.
prepare_home invalid_commit
shell_before=$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")
for invalid_args in '' '--commit main' '--commit deadbeef'; do
  read -r -a args <<<"$invalid_args"
  if NOMARKOO_SKIP_SHELL_RESTART=1 "$fixture_remote/install.sh" "${args[@]}" >/dev/null 2>&1; then
    printf 'Installer accepted an invalid commit request: %s\n' "$invalid_args" >&2
    exit 1
  fi
done
[[ $shell_before == "$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")" ]]
[[ ! -e $XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout ]]

# Clean install imports the live XKB configuration, is detached, updates to an
# exact second commit, and remains idempotent.
prepare_home clean
NOMARKOO_TEST_HYPR_MODE=live run_installer "$fixture_commit_one" >/dev/null
assert_installed "$fixture_commit_one"
first_head=$(git -C "$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout" rev-parse HEAD)
NOMARKOO_TEST_HYPR_MODE=live run_installer "$fixture_commit_one" >/dev/null
assert_installed "$fixture_commit_one"
[[ $first_head == "$(git -C "$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout" rev-parse HEAD)" ]]
NOMARKOO_TEST_HYPR_MODE=live run_installer "$fixture_commit_two" >/dev/null
assert_installed "$fixture_commit_two"

# The normal uninstaller restores the stock widget and keeps keyboard state.
installed_plugin=$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout
NOMARKOO_SKIP_SHELL_RESTART=1 "$installed_plugin/uninstall.sh" >/dev/null
jq -e '
  .bar.layout.right[0].id == "omarchy.keyboard-layout" and
  .bar.layout.right[1].id == "omarchy.tray" and
  ([.bar.layout[]?[]? | select(.id == "nomarkoo.keyboard-layout")] | length) == 0
' "$XDG_CONFIG_HOME/omarchy/shell.json" >/dev/null
[[ -f $XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json ]]
[[ ! -e $installed_plugin ]]

# A copied pre-public plugin is backed up and migrated to a Git checkout.
prepare_home copied
copied_target=$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout
mkdir -p -- "$copied_target"
cp -- "$repo_root/manifest.json" "$copied_target/manifest.json"
printf 'copied-install\n' >"$copied_target/marker"
NOMARKOO_TEST_HYPR_MODE=live run_installer "$fixture_commit_two" >/dev/null
assert_installed "$fixture_commit_two"
copied_backup=$(find "$XDG_CONFIG_HOME/omarchy/plugins" -maxdepth 1 -type d -name '.nomarkoo.keyboard-layout.bak.*' -print -quit)
[[ -n $copied_backup && -f $copied_backup/marker ]]

# A different Git origin using the same plugin id is never overwritten.
prepare_home conflict
conflict_target=$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout
mkdir -p -- "$conflict_target"
git -C "$conflict_target" init -q
git -C "$conflict_target" remote add origin https://example.invalid/not-this-plugin.git
shell_before=$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")
if NOMARKOO_TEST_HYPR_MODE=live run_installer "$fixture_commit_two" >/dev/null 2>&1; then
  printf 'Installer overwrote a conflicting Git origin.\n' >&2
  exit 1
fi
[[ $shell_before == "$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")" ]]
[[ $(git -C "$conflict_target" remote get-url origin) == https://example.invalid/not-this-plugin.git ]]

# With no state and no live compositor, installation aborts without mutation.
prepare_home offline
shell_before=$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")
if NOMARKOO_TEST_HYPR_MODE=offline run_installer "$fixture_commit_two" >/dev/null 2>&1; then
  printf 'Installer accepted an empty state outside a live Hyprland session.\n' >&2
  exit 1
fi
[[ $shell_before == "$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")" ]]
[[ ! -e $XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout ]]
[[ ! -e $XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json ]]

# A final shell activation failure rolls back plugin, state, toggle, and shell.
prepare_home rollback
shell_before=$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")
if NOMARKOO_TEST_HYPR_MODE=live NOMARKOO_TEST_RESTART_FAIL=1 \
  "$fixture_remote/install.sh" --commit "$fixture_commit_two" >/dev/null 2>&1; then
  printf 'Installer ignored a failed shell restart.\n' >&2
  exit 1
fi
[[ $shell_before == "$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")" ]]
[[ ! -e $XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout ]]
[[ ! -e $XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json ]]
[[ ! -e $XDG_STATE_HOME/omarchy/toggles/hypr/nomarkoo-keyboard-layout.lua ]]

# A failed exact update restores the previous detached commit and all state.
prepare_home update_rollback
NOMARKOO_TEST_HYPR_MODE=live run_installer "$fixture_commit_one" >/dev/null
state_before=$(sha256sum "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")
shell_before=$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")
git -C "$fixture_remote" checkout -q --detach "$fixture_commit_two"
if NOMARKOO_TEST_HYPR_MODE=live NOMARKOO_TEST_RESTART_FAIL=1 \
  "$fixture_remote/install.sh" --commit "$fixture_commit_two" >/dev/null 2>&1; then
  printf 'Installer ignored a failed exact update.\n' >&2
  exit 1
fi
[[ $(git -C "$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout" rev-parse HEAD) == "$fixture_commit_one" ]]
[[ -z $(git -C "$XDG_CONFIG_HOME/omarchy/plugins/nomarkoo.keyboard-layout" symbolic-ref --quiet HEAD 2>/dev/null || true) ]]
[[ $state_before == "$(sha256sum "$XDG_STATE_HOME/omarchy/settings/nomarkoo-keyboard-layout.json")" ]]
[[ $shell_before == "$(sha256sum "$XDG_CONFIG_HOME/omarchy/shell.json")" ]]

printf 'installer integration tests passed.\n'
