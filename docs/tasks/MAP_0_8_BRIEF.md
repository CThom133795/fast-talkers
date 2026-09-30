# Map 0.8 overnight pass: tighten, fill, open up (brief for every agent)

Written by Claude Desktop (lead) on 2026-09-30, from the user's words before bed. Target: a playtest with friends the
next evening. Read `docs/GAME_VISION.md` (tone: late 1999, a city paused in time) and `docs/WORKFLOW.md` first.

## The user's asks (binding)
1. **Halcyon Trust:**
   - You can't walk up its stairs; you have to jump. Fix it, and fix it for every staircase in the game.
   - A stairwell there leads to nowhere. Fix it: it must reach a real floor or roof, or not exist.
2. **Tighten and polish the map.** Nothing floating or sunk, no dead ends, no stairs to nowhere, no doors into walls.
3. **Fill the huge gaps** round the map with new buildings. *"Everything besides Midtown feels EMPTY."*
   Every district needs life:
   - storefronts, stoops, laundry lines, fire escapes, parked cars;
   - alleys with dumpsters, loading bays, back doors;
   - a lit window here and there.
4. **Enterable buildings:** at least **50%** of buildings enterable, **75%** if performance allows. More explorable
   interiors in the *larger* buildings: several rooms, upper floors reachable by working stairs.
5. **Prefabs are the way:** reusable, parametric, seeded building prefabs, placed many times with variety.
6. **Break the long sightlines.** A crew driving round town must not see you coming "a mile away", and finding a
   crew should feel like a surprise. Use:
   - street walls of buildings;
   - bends and doglegs;
   - elevated rail or overpasses;
   - billboards, trees and kiosks;
   - alleys cut through blocks, so there are short routes that aren't the main road.
7. **Performance:** don't tank it. Target 60+ fps on the user's RTX 3080 in the worst view. Measured baseline
   (windowed, 1280x720, vsync off): 71–103 fps, 655–1,589 draw calls, draw-call bound (see
   `docs/OVERNIGHT_CITY_PERF.md`, "GPU numbers").
   - Budget: worst view ≤ 2,000 draw calls and ≥ 60 fps.
   - Interiors and props use `visibility_range_end` (30–45 m), merged meshes, the interior/clutter render layers,
     no shadows on props, and the `potato_optional` group for decor.

## Rules for every agent
- **No NPCs, no traffic.** Everything stays deterministic: seeded `_rng`, a stable `parked_vehicles` order, stable door
  indices for the network (doors sync by index; new doors must be created in a deterministic order).
- **Keep existing multiplayer APIs working:** `crew_spawns`, `interactable_doors`, `glass_panes`, `landmarks`,
  `roads`, `route()`, and the Dead Drop's use of neutral landmarks and roads.
- **Keep every existing suite green.** Add tests for what you build. Never loosen an existing check.
- **Original names only.** Real brands are out: "CASINO ROYALE" and "GOLDEN NUGGET" in `world.gd` `FILL_STYLES`
  must be renamed to invented names.
- **Walkability rules** (`BuildingKit`):
  - steps rise ≤ 0.18 m and run ≥ 0.28 m;
  - ramps ≤ 30°;
  - rails at 1.12 m;
  - door openings ≥ 1.2 m wide and 2.6 m tall;
  - interior floors at 0.17 m, above the 0.16 m plinth;
  - every stair lands on a floor.
- **Each agent works in its own git worktree and branch.**
  - Commit to your branch with clear messages; the lead merges into `dev`.
  - Don't edit files you don't own (see your task).
  - Need something in another agent's file? Write it in your final report.
- **Godot:** `C:\Users\CThom\Documents\Codex\2026-09-28\i-want-to-create-a-game\work\tools\godot\Godot_v4.4.1-stable_win64_console.exe`.
  Run `--headless --path . --import` once in a fresh worktree. This PC has an RTX 3080, so windowed perf and capture
  runs are real.
