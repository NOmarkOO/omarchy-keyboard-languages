# Architecture

The repository root is an Omarchy `bar-widget` plugin, so Omarchy can clone and update it as one unit. `KeyboardLayout.qml` owns shell integration and panel state, `KeyboardLayoutModel.js` contains pure parsing and placement logic, and `KeyboardSearchableDropdown.qml` provides the bounded XKB pickers.

The QML resolves `bin/nomarkoo-keyboard-layout` relative to its own checkout. UI and helper therefore always come from the same revision.

Installation requires a full commit SHA. The installer fetches only that commit, checks it out detached, verifies `HEAD`, and executes the helper and shell patcher from the verified checkout. The installation record keeps the commit for diagnostics, while a failed update restores the previous commit and branch/detached state.

## State flow

1. On first use, the helper imports `input:kb_layout`, `input:kb_variant`, and `input:kb_options` from a live Hyprland session.
2. It validates the full candidate against the installed XKB catalog and compiles the exact keymap.
3. It pauses Hyprland config autoreload, writes state and the generated Omarchy toggle atomically, applies only the three input values through `hl.config` IPC, selects the requested index, and restores autoreload.
4. Any rejected apply restores both files and the previous live values.

Bar aliases are optional metadata on individual layout entries. The helper updates them atomically under the same state lock, but deliberately leaves the generated toggle and live Hyprland configuration untouched.

Before shrinking the layout array, every Hyprland keyboard device is moved to an index guaranteed to survive. This avoids retaining references to a removed keymap—the failure mode that made early removal implementations destabilize a session.

## Compatibility boundary

The interface intentionally depends on Quattro's shared QML primitives and plugin manifest schema. CI validates against the current `quattro` branch. Runtime data depends only on Hyprland JSON IPC and libxkbcommon's `xkbcli` catalog/compiler.
