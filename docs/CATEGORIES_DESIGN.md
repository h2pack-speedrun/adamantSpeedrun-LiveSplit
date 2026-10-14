# Category Sessions Design

Status: phases 1-3 implemented; phase 4 pending. See the phases at the end.

## Goal

Players use LiveSplit for specific goals, not for "N runs in a row". The common goals are a
single run and five multi-run categories. Today the multi-run mode collapses every finished run
into one unlabeled row and resets on death, which fits none of those goals.

This design replaces the single/multi split with **category sessions**: one engine driven by a
small set of settings, with the six common goals shipped as presets. The current multi-run
behavior survives as the advanced, fully configurable form of the same engine.

## Concepts

- **Session**: one attempt at a category. It owns its settings, an attempt log, and session timers.
- **Attempt**: every run started while a session is armed. Attempts are never discarded.
- **Key**: a property read from a run that rules and labels use: `route` (underworld or surface),
  `weapon`, or `aspect`.
- **Progress**: the set of `distinct` key values from counted attempts. The session completes when
  that set reaches `runs` values.

### Attempt status

| Status | Meaning |
|---|---|
| `counted` | Cleared, passed the rules, and added a new `distinct` value. |
| `failed` | Died or abandoned. |
| `duplicate` | Cleared and passed the rules, but its `distinct` value was already counted. |
| `invalid` | Broke a rule at run start (for example the wrong aspect for All Regions). |
| `active` | The run in progress. |

A failed attempt does not consume its key: a failed Torch run can be retried.

## Settings

Rules decide which runs count; display settings decide how the log is shown. Presets only fill
these in.

### Rules

| Setting | Values | Meaning |
|---|---|---|
| `runs` | integer | Distinct values needed to complete the session. |
| `distinct` | `none`, `route`, `weapon`, `aspect` | Each counted run must add a new value of this key. |
| `same` | `none`, `weapon`, `aspect` | Every attempt must share this key with the first attempt. |
| `onDeath` | `continue`, `reset` | `continue` logs a failed attempt and keeps going; `reset` ends the session. |
| `resumeAfterRestart` | bool | After a game exit or crash, resume the saved session (`true`) or discard it. |

`onDeath` and `resumeAfterRestart` are independent options.

### Display

| Setting | Values | Meaning |
|---|---|---|
| `completedRun` | `splits`, `summary` | Keep a finished attempt's biome rows, or collapse it to one row. |
| `label` | `route`, `weapon`, `aspect`, `index` | What names an attempt row. |
| `pageSize` | integer | Finished attempts per overlay page. |

## Presets

| Preset | runs | distinct | same | onDeath | completedRun | label |
|---|---|---|---|---|---|---|
| Single Run | 1 | none | none | continue | splits | route |
| All Regions | 2 | route | aspect | continue | splits | route |
| 3 Weapons | 3 | weapon | none | continue | summary | weapon |
| One Weapon | 4 | aspect | weapon | continue | summary | aspect |
| All Weapons | 6 | weapon | none | continue | summary | weapon |
| All Aspects | 24 | aspect | none | continue | summary | aspect |

All presets allow any order and any region unless a rule says otherwise. "3 of 6 weapons" falls
out of `runs = 3` with `distinct = weapon`.

Single Run keeps today's behavior: every new run starts a fresh recording that replaces the last.

The old multi-run batch is the advanced form: `distinct = none`, `same = none`,
`onDeath = reset`, `completedRun = summary`, `label = index`, with `runs` chosen by the player.

## Timing

- **RTA** is the official time for every category. It runs from the first attempt's start across
  the whole session, including time in the hub between runs.
- **IGT** for the session is the sum of every attempt's IGT, failed and duplicate attempts included,
  so it covers the same attempts as RTA.
- **LrT** is session RTA minus all map-load time.
- Each attempt row also shows its own times. IGT and LrT columns stay optional through the existing
  column toggles.
- After a game exit or crash, a resumed session continues RTA from its saved elapsed time. Time
  while the game was closed is not counted.

## Key resolution

| Key | Source |
|---|---|
| `route` | Existing route detection: surface when the run starts in or has reached the N biome. |
| `weapon` | `CurrentRun.Hero.Weapons` matched against `WeaponSets.HeroPrimaryWeapons` (the game's run history reads `run.WeaponsCache` the same way). |
| `aspect` | The hero's aspect trait for that weapon (`run.TraitCache`). |

Keys are read at `StartNewRun`, so rule violations show as `invalid` immediately, and confirmed at
finalize. Display names start from a built-in English table; switching to game text lookup is a
later improvement.

## Persistence

Implemented in phase 2 for multi-run sessions. Single Run does not persist: it has no history
worth resuming.

**Storage.** Persisted module status (`data.buildStatus`): `SessionState` (`open`, `completed`,
`failed`, or empty), `SessionRuns`, the session clocks `SessionRtaCs`, `SessionLoadCs` and
`SessionIgtCs`, and the `SessionAttempts` table (status, route, weapon, aspect, run ordinal and
end times per attempt, capped at `data.maxSessionAttempts`). `timer/session_store.lua` maps a
session record to these fields. Every persisted status write rewrites the module config file
(about 40 KB at 60 attempts), so writes stay incremental: one table row per attempt change, and
only the clocks at checkpoints.

**When it saves.** When an attempt starts and when it ends, and at every game checkpoint: the
game checkpoints a run at room transitions through `RequestSave`, and LiveSplit wraps it to save
the session clocks alongside, so the saved clocks match the point the game resumes from.

**Run identity.** Each attempt stores its run ordinal: `GameState.CompletedRunsCache` (finished
runs in the save) when the run starts.

**Resume.** With `ResumeAfterRestart` on (default), arming batch recording from a cold start (game
launch, module re-enable) restores the saved session suspended: clocks frozen at the saved values.
The first in-play event (run start, room entrance or game checkpoint) resumes it:

- if the saved active attempt's run is still the current run, the attempt continues;
- if that run finished while LiveSplit was not running, the attempt is settled from
  `GameState.RunHistory` (clear or death, and its IGT);
- RTA and LrT continue from the saved values, so time while the game was closed is not counted.

A finished session (completed or failed) is restored for display only, with recording disarmed.
Start, Start New, Clear, Stop and leaving multi-run mode clear the saved session. With
`ResumeAfterRestart` off, a saved session is discarded when recording arms.

`onDeath` (what a death does to the session) and `ResumeAfterRestart` (what a game exit does)
are independent.

## Overlay

Lib overlay tables have a fixed `maxRows`, but LiveSplit chooses which rows to project each frame,
so paging needs no Lib change.

- **Pinned rows** always show: a header with category, progress and page
  (`All Aspects  9/24 · 3 failed · p2/4`), the active attempt (with biome splits when the category
  keeps them), and the session total.
- **Paged rows** show finished attempts, `pageSize` attempts per page. An attempt is never split
  across pages.
- **Follow newest**: by default the overlay shows the newest page. Paging back holds that page
  until the next attempt ends, then returns to newest. Paging next past the last page also returns
  to newest.
- **Hotkeys** follow Quick Pause: a `string` setting per key chosen from `F5`-`F12` or None
  (F1 opens the Hell2Modding overlay), resolved through `rom.ImGuiKey` and polled with
  `ImGui.IsKeyPressed` in an always-draw tick. Two settings: `PagePrevKey` and `PageNextKey`.
  Defaults avoid Quick Pause's F9. The tick installs once and stays correct across hot reload.
- The module's ImGui tab shows the full attempt log in a scrollable list with no row cap.

## UI

- **Simple (default)**: a category picker with Single Run and the five presets, a one-line rule
  summary for the selected preset, the recording controls, and the display toggles.
- **Advanced**: every rule and display setting, starting from the selected preset. Editing a
  setting turns the session into a custom category.

## Shared snapshot

`speedrun.timer` keeps its current fields. Category id, progress (`done / runs`) and failed count
are added as new fields, so existing readers keep working.

## Phases

1. **Engine.** Done: session, attempt log, key interface, rules and `onDeath`. Port the current single
   and multi modes onto it with no visible change. Tests cover rules and status transitions.
2. **Persistence.** Done: save and resume multi-run sessions with `ResumeAfterRestart`; RTA
   resumes without downtime.
3. **Overlay.** Done: pinned header, current and total rows around one page of finished attempts
   (`PageSize`), follow-newest, `PagePrevKey`/`PageNextKey` (default F7/F8), and the ImGui session
   history. A page key sets a pending flag that also satisfies the interval's `when`, so the new
   page projects within one tick even with no run active.
4. **Categories.** Weapon and aspect key resolvers, name tables, the five presets, and the simple
   and advanced UI.
5. **Optional.** Move hotkey polling into Lib as a shared capability with cross-module conflict
   detection.
