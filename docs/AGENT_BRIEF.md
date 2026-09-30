# Agent brief — Fast Talkers (read this first)

This brief is for Sonnet subagents working under the tech-lead session. It is meant to stop them re-deriving
the codebase. Keep it current when architecture changes.

## Paths
- Project: `C:\Users\CThom\Documents\Codex\2026-09-28\i-want-to-create-a-game\outputs\project-fast-talkers`
- Godot (console build): `..\..\work\tools\godot\Godot_v4.4.1-stable_win64_console.exe`, relative to the project.
  From bash: `/c/Users/CThom/Documents/Codex/2026-09-28/i-want-to-create-a-game/work/tools/godot/Godot_v4.4.1-stable_win64_console.exe`
- Exported game: `..\play-fast-talkers\Fast Talkers.exe`. Only the lead exports.
- Backups (for diffs): `..\..\work\backup-*`. The project is **not** a git repo.

## Engine and style
- Godot 4.4.1, GDScript, GL Compatibility renderer, 60 Hz physics, no physics interpolation.
- The game ships **no imported assets**: meshes, textures and sounds are all procedural.
- Typed GDScript, tabs, `##` doc comments. Forward is **-Z**. `Basis(Vector3.UP, yaw)`.
- `main.tscn` is one `Node3D` running `scripts/main.gd`. Everything else is built in code.

## File map (lines ≈)
| File | Role |
|---|---|
| `scripts/main.gd` (3,000) | Game controller: phases MENU/BUY/LIVE/RESULT, contract round, buy menu, HUD/radar/map, input setup, vehicles and seats, shooting resolution (`_on_shot`), tips (payphones), settings, practice bots |
| `scripts/player.gd` (1,900) | `FastPlayer`: local first-person controller, weapons table `WEAPONS`, attachments, recoil, seat camera (`enter_seat`, `seat_yaw`), emits `shot_fired(origin, dir, damage)` |
| `scripts/car.gd` (1,250) | `FastCar`: kinematic CharacterBody3D vehicles (sedan/coupe/suv/pickup/motorcycle), `TYPES` specs, seats and doors, breakable glass (`glass_hit`, `break_glass`), autopilot (practice wheelman only) |
| `scripts/world.gd` (2,200) | `FastWorld`: the whole city built in code. `crew_spawns`, `landmarks`, `districts`, `road graph route()`, `interactable_doors`, `glass_panes`, `payphones`, `parked_vehicles`, `draw_map` |
| `scripts/interiors.gd` | Midtown shop shells and interiors (12 walk-in businesses) |
| `scripts/character_model.gd` | Procedural skinned human (`build(crew)`, `animate(delta, velocity, aiming)`, `seated`, `set_dead`) |
| `scripts/guard.gd` | Practice bot (**offline only**) |
| `scripts/factions.gd` | Crew data: `morris`, `kingsway`, `solnegro`, `kojimoto` |
| `scripts/sfx.gd` / `effects.gd` | Procedural sound bank (`play`, `play_at`) and particles/tracers |
| `scripts/armory.gd` | Free-roam range and targets (Midtown, near (13,0,-42)) |

## Tests (all `extends SceneTree`; exit code 0 = pass)
Run from the project dir, for example:
`timeout 170 "$GODOT" --headless --path . --script res://tests/<suite>.gd`

| Suite | Checks | Covers |
|---|---|---|
| integration | ~66 | contract loop, buy phase, money |
| free_roam | ~137 | arsenal, guards, cars, seats |
| soak | — | 6,000-frame chaos bot; pass = no errors (use `--fixed-fps 60`) |
| map_interiors | ~96 | map, doors, glass, railings |
| vehicle_art | ~60 | vehicle meshes, seats, glass |
| wiring_05 | 13 | doors, GPS, wheelman |

- Noise to ignore at exit: `BUG: Unreferenced static string`, `RID allocations ... leaked`, `Thread object is being destroyed`.
- **A SCRIPT ERROR in a headless test hangs forever**, so always use `timeout`.
- Tests set `game.settings_path` to a `user://..._settings.cfg` so they don't clobber the player's settings.

## Hard rules from the user
- Real matches are players only. Bots are offline practice only.
- Skill over jank: deterministic damage, crosshair-true hitscan, no ragdoll exploits.
- Grounded, non-cartoon art. No downloaded assets without the user's approval.
- The core loop must not break: spawn → read objective board → buy → make the deal / backstab / crash it → return to HQ.

## Gotchas
- Bash heredocs containing GDScript (tabs and quotes) break. Write a `.py` script file and run it, or use the Edit tool.
- `main.gd` stores state in many globals: `phase`, `free_roam`, `vehicle`, `seat`, `carrying`, `cash`. New
  per-round state must be reset in `_reset_world_state()` / `_start_round()`.
- Car glass is one merged mesh per car, rebuilt on change. `window_closed(pane)` replaced the old `_panes`.
- **New `class_name` scripts are invisible until the class cache refreshes.** After creating one, run
  `timeout 120 "$GODOT" --headless --import --path .` once, or you get "Could not find type".
- The project is now a **git repo**. Do not commit; the lead commits. `git diff` shows your changes.
- Networking contract: `docs/NET_M1_SPEC.md`.

## Cloud sessions
Claude Code cloud sessions (Linux sandbox cloning the GitHub repo) work on disjoint files and open PRs to `master`.
- Full guide and rules: `docs/CLOUD.md`.
- `bash tools/cloud_setup.sh` installs Godot 4.4.1 into `~/.godot-4.4.1/` and primes the class cache; then `export GODOT=...`.
- `bash tests/run_all.sh [suite ...]` runs all suites headless (`timeout 170` each, soak at `--fixed-fps 60`) and prints a
  summary table; also works in Git Bash on Windows with `GODOT` set to the console exe. `net_pair` is skipped without `../../work`.
- Branch `cloud/<task>`, PR body includes the test table; never touch `main.gd` / `online.gd` / `net.gd` unless told to.
