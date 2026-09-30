# Map 0.6 — expansion plan (cloud tasks)

Owner: tech lead (the local Claude session). Cloud sessions carry out the tasks below on branches named
`cloud/<task>` and open PRs against `master`. Read `docs/CLOUD.md` and `docs/AGENT_BRIEF.md` first.
The M2 tasks run in parallel **only after M1 is merged**.

## The user's brief (verbatim intent)
- **A bigger map.** Move the crew HQs further apart, so there's a real sense of urgency when you think you're
  being betrayed.
- **More interiors across the whole map.**
  - Some businesses have several floors when they're in a big building.
  - Some buildings get more windows, depending on the business or location.
- **More expanded "trademark" locations:**
  - a hotel;
  - a parking garage;
  - a motel;
  - a night club;
  - a strip club;
  - a burger joint;
  - a high-rise with a couple of elevators, so it's not a single chokepoint.
- **The firing range becomes a GUN STORE with a range.** *Clarified by the user:* the gun store **may exist in
  contract and online matches** as an ordinary, believable business in the city. What must not appear in those
  modes is the obvious "beta testing range" from 0.5: target stands, steel plates, painted range lines, floating
  distance labels and practice bots. Those appear only in free roam.

## Hard constraints (all tasks)
- **Files you may not edit:** `scripts/main.gd`, `scripts/online.gd`, `scripts/net.gd`, `scripts/player.gd`,
  `scripts/car.gd`. They are owned by the multiplayer workstream, which is changing them right now. If you need
  a hook there, write the exact function and call site in your PR description under "Lead hooks needed".
- **World API.** Keep it, because main.gd and online.gd use it:
  - `crew_spawns[crew]` → `{car, yaw, hq, door, spawn, spawn_yaw}`
  - `landmarks`, `districts`, `footprints`, `footprint_polys`, `plazas`, `payphones`, `parked_vehicles`
  - `road_loop`, `route()`, `route_length()`, `wheelman_path()`
  - `interactable_doors`, `set_door_open`, `toggle_door`, `door_near`, `glass_panes`, `reset_glass`
  - `draw_map`, `map_bounds`, `district_at`, `is_on_land`, `kit_transform`, `steam_vents`, `sun`, `set_dusk`, `dusk`
- **Determinism.** The world is built from `_rng.seed = 31071999`, and every networked peer must build an
  identical city. Never use unseeded randomness, `randf()` or time in world building. Cars are matched by
  creation order, so `parked_vehicles` order must be stable.
- **No AI.** No pedestrians or traffic. Lifts and doors are deterministic scripted movers (allowed).
- **Everything procedural.** No imported assets. Keep the grounded late-90s look (see `docs/MAP_0_5.md`).
- **Performance budget, checked with `tests/capture_perf.gd` on the local GPU by the lead.**
  - Keep every street view at or below the 0.5 Midtown figure (~1,550 draw calls).
  - Use merged static meshes (`_finish` / MeshMerge) and `visibility_range_end` on interior props (≤ 45 m) and
    small details.
  - Interior lights use `INTERIOR_LAYER` and at most one OmniLight per room group.
  - Use no more than about 8 dynamic lights near any view.
- **Tests.**
  - `bash tests/run_all.sh` must pass (update tests that pinned old coordinates; keep their intent).
  - Add checks for everything new: routes, doors, lifts, stairs, plots.
  - In a headless test, also verify the player can walk up every staircase and ride every lift.
- **Networking.** Doors and lifts will be synced by the lead. Expose state as plain data plus deterministic
  setters: `set_door_open(i, open)` already exists; lifts get `call_lift(i, floor)` / `lift_state(i)` /
  `set_lift_state(i, floor, t)`.

---

## M1 — layout expansion, plots and gun store (one cloud session, first)
Branch `cloud/map-m1`. You own `world.gd`, `interiors.gd`, `armory.gd`, `range_target.gd`, new `scripts/buildings/*`,
and the map/vehicle/capture tests.

1. **Bigger city.**
   - Grow the mainland from about 520 × 530 m to about **800 × 800 m** (`HALF` about 320 → 400 as needed).
   - Midtown stays at the centre, **unchanged** (its test positions are pinned).
   - Move the six neighbourhood kits (`KITS`) outward: crew kits about 110–140 m further out. Keep their art.
   - Fill the new ring of land with new districts:
     - an **Uptown** high-rise/hotel district between Midtown and the north shore;
     - a **Motor Mile** strip with a motel, a burger joint and a parking garage, along a main road to one HQ;
     - a **Nightlife** block with a night club and a strip club, near the Strip;
     - more of the waterfront.

     Use `_block`, `_building`, `_street_life` and the kit helpers.
2. **HQs further apart.**
   - Street-route length from each crew HQ doorstep to the Exchange (`route_length`): **330–380 m**, with a
     spread of ≤ 6%.
   - Straight-line distance between any two HQs: **≥ 300 m**.
   - HQs are not in the four corners. They are distinct neighbourhoods with 3+ road entries each.
   - Update `docs/MAP_0_5.md` → `docs/MAP_0_6.md` with the new table.
3. **Roads.**
   - Extend the road graph so every new district has 2+ routes in.
   - Add at least one arterial loop around Midtown at about r = 200 m, so chases have somewhere to go.
   - `road_loop` (practice wheelman) stays the downtown ring.
   - Update `draw_map` so the radar and full map show everything.
4. **Plots for the trademark buildings.**
   - Reserve footprints: `const PLOTS: Dictionary` with keys `hotel`, `garage`, `motel`, `nightclub`,
     `stripclub`, `burger`, `highrise`, `gunstore`. Each is `{center: Vector2, size: Vector2, yaw: float,
     front: Vector3, district: String}`.
   - Place them on real streets with clear frontage.
   - Create `scripts/buildings/building_kit.gd`: shared helpers so the M2 tasks don't duplicate code.
     - Walls with window and door openings, floors and ceilings with openings.
     - Straight and U-return **stairs** with real walkable colliders (rise ≤ 0.18 m, run ≥ 0.28 m, or ramps
       ≤ 30°).
     - **Lift shafts** with an `AnimatableBody3D` car (sync_to_physics, deterministic), landing doors and
       call/floor buttons registered as `interactable_doors` entries with `kind: "lift"` plus the fields
       `lift` and `floor`.
     - Railing and parapet helpers that follow the 0.5 railing rules (collision matches the visible geometry).
     - Signage and neon helpers.
     - Interior light helper (`INTERIOR_LAYER`).
   - Give each plot a stub builder file, `scripts/buildings/<key>.gd`, with `static func build(world, plot)`.
     The stub builds a plain placeholder shell with a sign, so the city looks right before M2.
   - `world.gd` calls each builder once, in a fixed order.
5. **Gun store, a real business, with the range dressing in free roam only.**
   - Move the armory, range and targets out of Midtown into **"HALCYON ARMS — GUNS & RANGE"** at the `gunstore`
     plot. It's a believable late-90s gun shop:
     - storefront with a sign;
     - barred windows and a glass door;
     - counters and gun wall inside;
     - a back door to an **indoor range** (lanes, booths, baffles);
     - a fenced outdoor range yard behind, for long range.
   - The old Midtown range lot becomes a normal Midtown business or car park. Keep Midtown's other positions.
   - `armory.gd` constants (`SPAWN`, `RACK`, `LONG_LINE_X`, ...) must move with it. Update every test that uses
     them. main.gd reads `ArmoryScript.SPAWN`/`RACK`, so those names must stay.
     - Report any hard-coded armory coordinates you find in main.gd (for example
       `Vector3(ArmoryScript.LONG_LINE_X, 0, -15)`) as lead hooks.
   - **Mode dressing:** add `world.set_mode(mode: String)`, where mode is `"free_roam"`, `"contract"` or
     `"online"`, and `armory.set_mode(mode)`.
     - **Contract and online:** the shop is present and walk-in, like any other business, with a normal door and
       breakable windows. It gives no buying or rearming there (buying stays at the crew HQ). The **range
       dressing is hidden and has no collision**: targets, plates, rack, painted lines, distance labels, "LONG
       RANGE" signage and bench labels. The range doors are locked and the yard gate is shut, so it reads as a
       closed range, not a test level. It appears on the map as an ordinary business, not a highlighted
       landmark.
     - **Free roam:** everything is visible and active, as today.
     - Lead hook needed: main calls `world.set_mode()` / `armory.set_mode()` when a mode starts.
6. **Tests.** Extend `tests/map_interiors.gd`, or add `tests/map_06.gd`, to check:
   - all HQ routes and pairwise distances meet the targets above;
   - every plot is on land, faces a road, and overlaps no footprint;
   - each stub building exists;
   - gun store:
     - the shop exists in all modes;
     - in contract/online mode every range target, plate, label and painted line is hidden with no collision,
       and the range door and yard gate are shut;
     - in free roam it is all visible and active;
   - determinism: build the world twice and compare checksums of the footprint and parked-vehicle lists.
7. **Captures for the lead.** Aerial full map, one street view per new district, HQ doorsteps. Write them to
   `work/captures/` (add the PNGs to the PR only if they're small, otherwise describe them). Cloud can't render
   with a GPU, so if headless rendering fails, say so. The lead will capture locally.

**Acceptance:** `tests/run_all.sh` is green, the route and distance table is in the PR body, and the lead hooks
are listed.

---

## M2 — trademark buildings (parallel cloud sessions after M1 merges)
There is one branch per building: `cloud/map-m2-<key>`. Each session owns **only**
`scripts/buildings/<key>.gd`, its own test `tests/building_<key>.gd`, and additions to `building_kit.gd`.
Additions to the kit must be new functions, never changes to existing ones, so parallel PRs merge cleanly.

Common requirements:
- Interiors match the sign and are furnished with the Interiors-style prop density.
- Windows are appropriate to the business. The high-rise and hotel get full window grids; the strip club and
  night club get almost none.
- Every public floor is reachable by stairs, and by lifts where listed.
- Doors are registered as `interactable_doors`, glass as breakable `glass_panes`.
- A walk-through test covers every floor, plus a lift ride test where relevant.

| Key | Building | Must have |
|---|---|---|
| `highrise` | 16–20 storey office tower, "HALCYON TRUST" | Lobby with security desk. **Two lift shafts plus two stairwells** at opposite corners, so there is no single chokepoint. 3 fitted floors (open-plan office, executive floor, roof with helipad markings). Other floors are served but sealed at the landing. |
| `hotel` | "HOTEL MERIDIAN", 6–8 storeys | Lobby, bar, a lift and a stairwell. 2 fitted guest floors with corridors and 4–6 enterable rooms each. Rooftop pool terrace. |
| `garage` | 4-level parking garage | **Drivable ramps** (≤ 12°, 7 m lanes) that cars in `car.gd` can climb; test by driving a sedan to the top. Pedestrian stair core. Parked car props on each level. Open sides with parapets per the railing rules. |
| `motel` | "SEA BREEZE MOTEL", 2 storeys | L-shaped with an exterior walkway and stairs. 8–10 enterable rooms. Office, ice machine, pool (empty, drained), neon sign. |
| `nightclub` | "CLUB VOLTAGE" | Queue rope and door, dance floor with coloured light panels (emissive, no extra dynamic lights), DJ booth, bar, upstairs VIP mezzanine with a stair and a back exit to the alley. |
| `stripclub` | "THE VELVET ROOM" | **Tasteful, non-explicit.** No dancers or people at all (no AI rule). Main stage with poles, booths, bar, a back office with a safe, dressing-room corridor to the alley exit, neon exterior with no windows. |
| `burger` | "BIG BOY BURGERS" (or an original name) | Diner-style counter, booths, kitchen behind, **drive-thru lane with window**, big pole sign, parking lot. |
| `gunstore` | Upgrades the M1 compound | Nicer shop fit: gun wall, glass counters, a lane booth. Keep the M1 mode dressing: a normal shop in matches, the full range in free roam. |

---

## Lead (local) work that follows these tasks
- Wire `world.set_mode()`, `armory.set_open()`, the lift prompts (`kind == "lift"`) and door/lift **network
  sync** into main.gd and online.gd.
- Run performance captures on the local GPU. Export.
