# LiveSplit

In-game splits and timers for Hades II. Built on Museus's Timer mod.

Part of the [Speedrun modpack](https://thunderstore.io/c/hades-ii/p/adamantSpeedrun/Speedrun_Modpack/).

## Timing

- **IGT**: the game's run timer.
- **RTA**: wall-clock time.
- **LrT**: RTA with map loads removed.

Show any combination. Splits are per biome on Underworld, Surface and Dream Dive routes.

## Categories

| Category | Goal |
|---|---|
| Single Run | Splits for every run until you stop recording. |
| All Regions | Clear the Underworld and the Surface, either order, same aspect. |
| 3 Weapons | Clears with 3 different weapons. |
| One Weapon | Clears with all 4 aspects of one weapon. |
| All Weapons | Clears with all 6 weapons. |
| All Aspects | Clears with all 24 aspects. |
| Custom | Your own rules. |

Multi-run categories time the whole session: RTA runs from the first run's start, including time in
the Crossroads, and IGT is the sum of every run. Deaths are logged as failed runs and the session
keeps going. Repeats and rule breaks are shown but don't count.

**Custom** can reproduce any preset (Settings → Copy to Custom) and change it:
- up to 50 runs;
- which of region, weapon or aspect must be new or stay the same;
- which regions count;
- whether a death ends the session;
- whether to keep biome splits for every run.

## Long sessions

- **Pause** (F6) between runs to take a break. The session clocks stop, and the break shows up as
  a Paused split, so the total stays honest.
- Sessions **survive a game exit or crash**. Time with the game closed isn't counted.
- The overlay pages through finished runs with **F7/F8**.

All keys can be rebound under Hotkeys & Advanced. Conflicts with other mods' keys are flagged
there.

## Installation

Install via r2modman, usually as part of the [Speedrun modpack](https://thunderstore.io/c/hades-ii/p/adamantSpeedrun/Speedrun_Modpack/).
It only reads the game. It never changes runs.
