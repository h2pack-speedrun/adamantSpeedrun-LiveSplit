# LiveSplit

Mod to add LiveSplit like native support to the game. Thanks to Museus for their original Timer mod. This is a big expansion on that

Part of the [Speedrun modpack](https://thunderstore.io/c/hades-ii/p/adamantSpeedrun/Speedrun_Modpack/).

## What It Does

LiveSplit records runs and shows selected timing information while you play. Its main feature is a recording table that tracks your route through a run like a compact in-game LiveSplit layout.

## Examples

<img src="https://raw.githubusercontent.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/main/assets/Timer1.png" width="60%"/>

<img src="https://raw.githubusercontent.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/main/assets/Timer2.png" width="60%"/>

The recording table supports:

- Underworld routes: Erebus, Oceanus, Fields, and Tartarus.
- Surface routes: Ephyra, Thessaly, Olympus, and The Summit.
- Dream Dive routes, where the biome order is detected from the run.
- Single-run splits for a normal attempt.
- Multi-run batch recording for routing or practice sessions across several consecutive runs.

The timer can show these timing columns:

- IGT: in-game run time from the game's run timer.
- RTA: real elapsed time.
- LrT: load-removed time, with map-load time subtracted.

## Current Options

- Start, stop, and clear single-run or multi-run recording.
- Show or hide the recording table.
- Show optional raw IGT/RTA/LrT timer rows while recording is active.
- Choose which timer columns are visible.
- Pick a category: Single Run, All Regions (Underworld and Surface with one aspect), 3 Weapons, One Weapon (all 4 aspects of a weapon), All Weapons, All Aspects, or Custom for your own rules.
- Multi-run categories log every attempt: deaths are shown as failed runs and the session keeps going. All Regions keeps the biome splits of both regions.
- Custom sets your own rules: 1 to 10 runs, which key must be new or stay the same each run, and whether a death ends the session.
- **Single-run recording continues across runs until you stop it.** A multi-run session stops when it completes (or, in Custom, when a death ends it), keeping its results until you press Start New.
- Disabling LiveSplit or the pack clears the current recording but keeps it armed for when you re-enable.
- The multi-run overlay shows one page of finished runs; page through older ones with F7/F8. The keys are managed by ModpackLib (modifiers allowed, conflicts with other modules reported) and listed on the Speedrun window's Hotkeys page. The module tab lists the full session history.
- Multi-run sessions survive a game exit or crash (Resume after restart, on by default); time while the game is closed is not counted.

### Single-Run Recording

<img src="https://raw.githubusercontent.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/main/assets/SingleRun.png" width="60%"/>

### Multi-Run Recording

<img src="https://raw.githubusercontent.com/h2pack-speedrun/adamantSpeedrun-LiveSplit/main/assets/MultiRun.png" width="60%"/>

## Gameplay Impact

This module only displays timing information. It does not change rooms, rewards, enemies, boons, or run generation.

## Installation

Install via r2modman.

This module is usually installed as part of the full [Speedrun modpack](https://thunderstore.io/c/hades-ii/p/adamantSpeedrun/Speedrun_Modpack/), where it appears in the shared Speedrun UI.
