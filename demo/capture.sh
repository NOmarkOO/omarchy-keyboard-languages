#!/usr/bin/env bash

set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output_dir="$repo_root/docs/screenshots"
capture_root=$(mktemp -d)
original_theme=$(omarchy theme current)
original_workspace=$(hyprctl -j activeworkspace | jq -r '.id')
capture_workspace=""

cleanup() {
  omarchy-shell -q nomarkoo.keyboard-layout close || true
  omarchy theme set "$original_theme" >/dev/null 2>&1 || true
  if [[ $original_workspace =~ ^[0-9]+$ ]]; then
    hyprctl dispatch "hl.dsp.focus({ workspace = \"$original_workspace\" })" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$capture_root"
}
trap cleanup EXIT INT TERM

for command in omarchy omarchy-shell hyprctl grim magick jq; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'capture: required command not found: %s\n' "$command" >&2
    exit 1
  }
done

mapfile -t occupied_workspaces < <(hyprctl -j workspaces | jq -r '.[].id')
for candidate in $(seq 10 99); do
  if ! printf '%s\n' "${occupied_workspaces[@]}" | grep -Fxq -- "$candidate"; then
    capture_workspace=$candidate
    break
  fi
done
[[ -n $capture_workspace ]] || {
  printf 'capture: no unused workspace is available in the range 10-99.\n' >&2
  exit 1
}

hyprctl dispatch "hl.dsp.focus({ workspace = \"$capture_workspace\" })" >/dev/null
active_workspace=$(hyprctl -j activeworkspace | jq -r '.id')
workspace_clients=$(hyprctl -j clients | jq --argjson workspace "$capture_workspace" '[.[] | select(.workspace.id == $workspace)] | length')
[[ $active_workspace == "$capture_workspace" && $workspace_clients == 0 ]] || {
  printf 'capture: workspace %s is not an empty active workspace.\n' "$capture_workspace" >&2
  exit 1
}

monitor=$(hyprctl -j monitors | jq -r 'first(.[] | select(.focused == true)).name // empty')
monitor_width=$(hyprctl -j monitors | jq -r 'first(.[] | select(.focused == true)).width // empty')
[[ -n $monitor && $monitor_width =~ ^[0-9]+$ ]] || {
  printf 'capture: a focused Hyprland monitor could not be found.\n' >&2
  exit 1
}
(( monitor_width >= 520 )) || {
  printf 'capture: the focused monitor is too narrow for the documentation crop.\n' >&2
  exit 1
}

mkdir -p -- "$output_dir"
crop_x=$((monitor_width - 520))

capture_view() {
  local theme=$1 method=$2 filename=$3 height=$4
  local full="$capture_root/$filename.full.png"

  omarchy theme set "$theme" >/dev/null
  local ready=false
  for _ in $(seq 1 30); do
    if omarchy-shell nomarkoo.keyboard-layout.demo "$method" >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 0.2
  done
  if [[ $ready != true ]]; then
    printf 'capture: the demo IPC target is unavailable; install this checkout and try again.\n' >&2
    exit 1
  fi
  sleep 0.4
  grim -o "$monitor" "$full"
  magick "$full" \
    -crop "520x${height}+${crop_x}+0" +repage \
    -strip -define png:compression-level=9 \
    "$output_dir/$filename"
  omarchy-shell -q nomarkoo.keyboard-layout close
  printf 'Captured %s\n' "$output_dir/$filename"
}

capture_view 'Matte Black' showMain matte-black-manager.png 380
capture_view 'Catppuccin' showAdd catppuccin-add-language.png 360
capture_view 'Flexoki Light' showShortcut flexoki-light-shortcut.png 310
capture_view 'Gruvbox' showRemoval gruvbox-remove-confirmation.png 380
