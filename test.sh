#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

bash -n \
  "$repo_root/install.sh" \
  "$repo_root/uninstall.sh" \
  "$repo_root/bin/nomarkoo-keyboard-layout" \
  "$repo_root/bin/patch-shell-json" \
  "$repo_root/tests/helper.test.sh" \
  "$repo_root/tests/installer.test.sh" \
  "$repo_root/tests/bin/hyprctl" \
  "$repo_root/tests/bin/omarchy"

[[ -x $repo_root/demo/capture.sh ]]

jq -e . \
  "$repo_root/manifest.json" \
  "$repo_root/tests/fixtures/state.json" \
  "$repo_root/tests/fixtures/shell-before.json" >/dev/null

xkbcli list --load-exotic | node "$repo_root/tests/model.test.js"
omarchy plugin validate "$repo_root"
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
  "$repo_root/KeyboardLayout.qml" \
  "$repo_root/KeyboardSearchableDropdown.qml"

rg -q 'defaultSection.*right' "$repo_root/manifest.json"
[[ $(jq -r '.version' "$repo_root/manifest.json") == 1.0.1 ]]
rg -q 'Qt\.resolvedUrl\("bin/nomarkoo-keyboard-layout"\)' "$repo_root/KeyboardLayout.qml"
rg -q 'target: "nomarkoo.keyboard-layout.demo"' "$repo_root/KeyboardLayout.qml"
if rg -q 'command: \["nomarkoo-keyboard-layout"|\.local/bin/nomarkoo-keyboard-layout' \
  "$repo_root/KeyboardLayout.qml"; then
  printf 'QML still depends on a separately installed PATH helper.\n' >&2
  exit 1
fi
if rg -q 'hyprctl reload|hyprctl configerrors' "$repo_root/bin/nomarkoo-keyboard-layout"; then
  printf 'Keyboard helper performs a full Hyprland reload.\n' >&2
  exit 1
fi
if rg -q 'centerOnBar:[[:space:]]*true' "$repo_root/KeyboardLayout.qml"; then
  printf 'Keyboard panel is forced to the middle of the bar.\n' >&2
  exit 1
fi
rg -q 'function resetAddEditor\(\)' "$repo_root/KeyboardLayout.qml"
[[ $(rg -c 'resetAddEditor\(\)' "$repo_root/KeyboardLayout.qml") -ge 4 ]]
rg -q 'onClosed: searchField.text = ""' "$repo_root/KeyboardSearchableDropdown.qml"

if rg -n \
  'raw\.githubusercontent\.com/NOmarkOO/omarchy-keyboard-languages/main/install\.sh|fetch[^\n]*origin main|--branch main|omarchy plugin update nomarkoo\.keyboard-layout' \
  "$repo_root/README.md" "$repo_root/install.sh"; then
  printf 'Mutable upstream execution returned to the reviewed install or update path.\n' >&2
  exit 1
fi
rg -q -- '--commit' "$repo_root/install.sh"
rg -q 'checkout --quiet --detach' "$repo_root/install.sh"

mapfile -t documented_url_commits < <(
  rg -o 'raw\.githubusercontent\.com/NOmarkOO/omarchy-keyboard-languages/[0-9a-f]{40}/install\.sh' \
    "$repo_root/README.md" | sed -E 's#^.*/([0-9a-f]{40})/install\.sh$#\1#'
)
mapfile -t documented_arg_commits < <(
  rg -o -- '--commit [0-9a-f]{40}' "$repo_root/README.md" | awk '{print $2}'
)
[[ ${#documented_url_commits[@]} -gt 0 ]]
[[ ${#documented_url_commits[@]} == ${#documented_arg_commits[@]} ]]
for index in "${!documented_url_commits[@]}"; do
  [[ ${documented_url_commits[$index]} == "${documented_arg_commits[$index]}" ]]
done
if rg -q 'FULL_40_CHARACTER_RELEASE_COMMIT' "$repo_root/README.md"; then
  printf 'Release documentation still contains an unresolved commit placeholder.\n' >&2
  exit 1
fi

"$repo_root/tests/helper.test.sh"
"$repo_root/tests/installer.test.sh"

if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!test.sh' \
  '(github_pat_|ghp_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY)' "$repo_root"; then
  printf 'Credential-like content found in repository.\n' >&2
  exit 1
fi

printf 'All keyboard-language plugin checks passed.\n'
