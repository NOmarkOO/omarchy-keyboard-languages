#!/usr/bin/env bash

set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output_dir="$repo_root/docs/screenshots"
capture_root=$(mktemp -d)
original_theme=$(omarchy theme current)

cleanup() {
  omarchy-shell -q nomarkoo.keyboard-layout close || true
  omarchy theme set "$original_theme" >/dev/null 2>&1 || true
  rm -rf -- "$capture_root"
}
trap cleanup EXIT INT TERM

for command in omarchy omarchy-shell hyprctl grim magick jq; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'capture: required command not found: %s\n' "$command" >&2
    exit 1
  }
done

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
  if ! omarchy-shell nomarkoo.keyboard-layout.demo "$method" >/dev/null 2>&1; then
    printf 'capture: the demo IPC target is unavailable; install this checkout and try again.\n' >&2
    exit 1
  fi
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
