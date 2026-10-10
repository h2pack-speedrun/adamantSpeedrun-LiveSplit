# Changelog

## [Unreleased]

## [5.2.1] - 2026-10-10

### Added

- use Lib overlay font constants (
0eefd9)

## [5.0.0] - 2026-10-05

### Added

- opt out of pack hash, require ModpackLib 4.2.1 (de9b5ad)

## [4.0.0] - 2026-06-15

### Performance

- livesplit: batch retained overlay refresh (5ec7a04)

### Changed

- livesplit: refresh retained overlays by name (
f9ac53)

## [3.0.0] - 2026-06-12

### Changed

- use native module config backend (
acaf48)

## [2.0.2] - 2026-06-09

## [2.0.1] - 2026-06-09

## [2.0.0] - 2026-06-09

### Changed

- Ported timer boot, overlays, hooks, actions, fallback UI, and draw widgets to the current ModpackLib host/draw APIs.
- Moved the recording-ready runtime marker from managed storage to persistent cache.
- Replaced the ENVY public timer read API with the `speedrun.timer` integration provider.

## [1.1.2] - 2026-05-06

### Changed

- Split recording now uses explicit Start/Clear/Stop controls for both single-run and multi-run modes.
- Single-run timer results now persist after the victory screen until the next run or recording reset.

## [1.1.1] - 2026-05-05

### Changed

- Quick tab minor bug fix
- Single run timer now persists after victory screen

## [1.1.0] - 2026-05-05

### Changed

- Moved game hooks to the ModpackLib hook contract for reload-safe registration.
- Hardened GitHub Actions so Lua validation runs before releases.
- Moved timer HUD rendering onto ModpackLib managed overlays.
- Reworked the module UI around selectable timer columns, live timer rows, split table visibility, split mode, and batch recording controls.
- Updated the packaged README to describe the current player-facing timer and split features.

### Added

- Added IGT, RTA, and LrT column selection for live timer rows and split tables.
- Added biome split tables for Underworld, Surface, and Dream Dive routes.
- Added multi-run batch recording with cumulative IGT/RTA/LrT totals.
- Added Quick Setup content with a simple module enable toggle.
- Added runtime persistence for batch recording intent across reloads.
- Added tests for timer formatting, route rows, batch recording, and UI fallback behavior.

## [1.0.0] - 2026-04-21

Initial release

[unreleased]: https://github.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/compare/2.0.2...HEAD
[2.0.2]: https://github.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/compare/2.0.1...2.0.2
[2.0.1]: https://github.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/compare/2.0.0...2.0.1
[2.0.0]: https://github.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/compare/1.1.2...2.0.0
[1.1.2]: https://github.com/h2pack-speedrun/adamant-Speedrun_LiveSplit/compare/1.1.1...1.1.2
[1.1.1]: https://github.com/h2pack-speedrun/adamant-Speedrun_LiveSplit/compare/1.1.0...1.1.1
[1.1.0]: https://github.com/h2pack-speedrun/adamant-Speedrun_LiveSplit/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/h2pack-speedrun/adamant-Speedrun_LiveSplit/compare/634e4468165e8839e160039a7a5d3e751344e5dd...1.0.0
