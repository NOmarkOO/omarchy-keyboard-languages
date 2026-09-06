# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-09-06

### Added

- Configured layouts can now use a custom bar alias of up to six characters. Aliases are edited per layout or variant from the language manager, and clearing one restores the automatic two-letter label without reapplying the keyboard configuration. Thanks to [@msouza10](https://github.com/msouza10), whose original alias proposal inspired the customizable feature.

## [1.0.2] - 2026-08-23

### Added

- Added a repository-root Marketplace preview assembled from four real Quattro theme captures.
- Added reusable SVG and PNG project icons.

### Changed

- Rewrote the manifest description around user-visible actions and declared the MIT license in plugin metadata.

## [1.0.1] - 2026-08-23

### Security

- Bound installation and updates to an explicit full commit SHA checked out in detached mode before repository code is executed.
- Removed mutable `main` and native-updater commands from the reviewed release path.

### Changed

- Recorded the exact installed commit and restored the previous Git state if an update transaction fails.

## [1.0.0] - 2026-08-23

### Added

- Two-letter Quattro bar indicator with left-click switching and right-click management.
- Layout, variant, shortcut, and safe-removal workflows using installed XKB data.
- Screen-aware pickers for all bar positions and multi-monitor configurations.
- Targeted, rollback-safe Hyprland updates without compositor reloads.
- One-command installer with live-state import and copied-plugin migration.
- Recoverable uninstaller, automated integration tests, CI, and themed documentation.

[1.1.0]: https://github.com/NOmarkOO/omarchy-keyboard-languages/releases/tag/v1.1.0
[1.0.2]: https://github.com/NOmarkOO/omarchy-keyboard-languages/releases/tag/v1.0.2
[1.0.1]: https://github.com/NOmarkOO/omarchy-keyboard-languages/releases/tag/v1.0.1
[1.0.0]: https://github.com/NOmarkOO/omarchy-keyboard-languages/releases/tag/v1.0.0
