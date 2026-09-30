# Project Fast Talkers — shared handoff

## Shared objective
Original low-poly round-based business-negotiation shooter, eventual Steam release.
References for desired feel: Sub Rosa / No Big Deal round negotiations, GTA IV vehicle weight,
Battlefield / BattleBit responsive gunplay, Arma Reforger grounded movement, CS2 round buying.
PS2 / Xbox / GameCube visual era; low-end PCs; development storage budget 75 GB.
User confirmed typical matches: 12 players, 3 companies of 4. Large: 24 players, 4 companies of 6.
Do not copy assets, maps, logos, characters, audio, or source code from those games.

## Coordination — active build
Codex owns `scripts/`, `project.godot`, `main.tscn`, launchers, and integration tests during this build.
Claude can immediately own `docs/MULTIPLAYER_DESIGN.md` and `docs/PLAYTEST_CHECKLIST.md`.
Please inspect the implementation, document proposed interfaces, and leave code changes for
the next coordinated pass. These are file ownership boundaries to avoid simultaneous overwrites.
There is no direct agent messaging connection between this Codex task and the user's Claude session.
Coordinate through this file and docs, or messages relayed by the user.

## Claude's bounded first task
1. Read current scripts and produce a concrete, staged server-authoritative multiplayer design.
2. Identify changes required for input commands, movement snapshots, car occupancy, transactions,
   shot validation, briefcase ownership, disconnect recovery, round transitions and proximity voice.
3. Provide a playtest checklist for the offline prototype and later 100 ms / packet-loss multiplayer.
4. Record recommended next tasks with acceptance criteria. Do not describe planned systems as built.

## Current implementation
Godot 4.4.1, GDScript, Compatibility renderer, procedural meshes, zero external art dependencies.
Offline, single-player handling laboratory; no networking or voice implementation yet.
`main.gd` owns MENU → BUY → LIVE → RESULT, purchases, briefcase and interaction, HUD and menus.
`player.gd`: FastPlayer CharacterBody3D, layer 2/mask 1, camera, weapon model, stance/stamina,
ammo/reload, shot_fired(origin,direction,damage), died, equip, reset_player, set_vehicle_mode.
`car.gd`: FastCar CharacterBody3D, layer/mask 1, occupied/enabled/speed_kph, reset_car,
exit_position. Forward is -Z. Handling is kinematic; suspension/roll are cosmetic.
`world.gd`: FastWorld procedural static district. Main owns interactive content.
`guard.gd`: stationary deal security, line-of-sight damage, no navigation or advanced AI.

## Prototype rules
Start $3,200. Pistol/car free, carbine $1,600, SMG $1,000, armor $650.
One primary purchase per round; no duplicate buying. Equipment resets each round.
Exchange costs $800 or can be robbed; return briefcase for $2,600 gross revenue.
Loss relief starts at $1,200, increases by $300 to $2,400. Cash capped at $16,000.
Four-minute active round. Menus pause offline action. No kill bonus.
Multiplayer design must revisit pause, equipment retention, friendly fire, and economy balance.

## Quality gates
Parse/import cleanly; boot; complete paid and hostile routes; test loss/reset and purchase limits;
enter/exit safely; blocked exit and moving exit checks; no money from repeated delivery;
camera ray and weapon aim agree; no client-trusted cash/hits in future network version.
Performance numbers and 'potato PC' support are targets until hardware profiling establishes them.

## Next coordination point
Codex is currently integrating and testing. Do not overwrite active code files.

---

## 2026-09-29 — Codex → Claude: user-requested 0.5 handoff, MAP / INTERIORS / VEHICLE ART

The user explicitly asked me to offload the heavy lifting to you. The latest 0.4 entry in `CODEX_HANDOFF.md` says you were finished and returned code ownership. This new entry claims a fresh, disjoint split. Please read the user's latest request, `CODEX_HANDOFF.md`, and `docs/MULTIPLAYER_DESIGN.md` before editing.

**Your owned files for this pass:** `scripts/world.gd`, `scripts/car.gd`, new `scripts/interiors.gd` (or other new world/vehicle art scripts), new `tests/map_interiors.gd` / `tests/vehicle_art.gd`, relevant city/vehicle capture scripts, `CODEX_HANDOFF.md`. You can update map and vehicle art docs in a new `docs/MAP_0_5.md`. Do not edit `scripts/main.gd`, `scripts/player.gd`, `docs/MULTIPLAYER_DESIGN.md`, `CLAUDE_HANDOFF.md`, `project.godot`, `README.md`, the Windows export, or Codex's existing integration tests while my pass is active. I own those files and will integrate your exported world APIs into main. If you need a main.gd hook, document the desired method/signal in your handoff and I will wire it.

**Map heavy lift:** The 0.4 four corner islands with two bridges apiece and the west canal are too restrictive. The user wants a physically asymmetrical city with far fewer canals/channels, more continuous land, open spaces and plazas, realistic connected streets instead of a rigid grid. Routes from each crew HQ to Midtown should be broadly even in travel time, but HQs should not be placed in four corners. Keep the existing named districts and recognizable landmark art where practical; move crew bases into distinct neighborhoods distributed across the city. Build alternate pedestrian and vehicle approaches to each district. Preserve the main scene's public world API (`crew_spawns`, `landmarks`, `footprints`, `districts`, `parked_vehicles`, `road_loop`, `draw_map`, `map_bounds`, `district_at`) or document any changes. Update radar/full-map geometry from the same road/land data. Validate all HQs can reach Exchange and that the fastest reasonable routes are close enough for fair contracts. Capture and inspect an aerial/full-map render and street views.

**Midtown interiors heavy lift:** Begin with the buildings/businesses whose exterior signs invite entry. A substantial majority of signed Midtown storefronts should have at least a useful ground-floor interior, with a clear door, collision and sight lines: e.g. Exchange/lobby, shop/cafe, bar, motel, garage/armory as their façades warrant. Interior props and floor plans should match the exterior sign; avoid generic empty rooms. It is acceptable to keep a minority of background buildings sealed. Expose `world.interactable_doors` or a similar array of metadata (`position`, `inside`, `outside`, `label`, optional open/closed state) and/or use a physical doorway so I can wire the E prompt in `main.gd`. Mark interiors and doors on the map if useful. No multiplayer logic needed in world.gd.

**Railing and collision cleanup:** The user reports that invisible/full-height barriers block shots over railings. Audit `_coast`, `_build_bridges`, `_fence`, and any parapet/guard rail. Replace tall invisible solid boxes with collision that matches the visible solid material; thin rails should be separate colliders or no collider so bullets can pass through real gaps. Keep player/vehicle fall prevention where necessary via low curb/guard collision and geometry. Add a test that raycasts over a rail from a standing eye height and hits a target beyond while a lower ray still strikes the visible parapet. Document remaining compromises.

**Vehicle visual polish:** Sedan/coupe/SUV/pickup/motorcycle should read as one late-1990s/early-2000s crime-city fleet. Refine consistent wheel scale, cabin/roof proportions, lights, bumpers, glass and material values while retaining each type's silhouette and seat layout. The current render captures in `work/captures/veh_*` show the starting point. Preserve `car.gd` seat, door, window and driving APIs so my 360° camera changes work. Inspect front, rear and side lineup captures; aim for credible silhouettes and no obvious missing or floating parts. Prioritize shape/material polish over piling on trim.

**Coordination:** I am concurrently changing only `main.gd`, `player.gd`, `docs/MULTIPLAYER_DESIGN.md` and my own tests. Please leave an IN PROGRESS update in `CODEX_HANDOFF.md` before you change code, then a COMPLETE update with changes, APIs, tests and captures. Do not export or modify the exe. I will run integration, export and publish after your code lands. If you cannot actively run in another session, this handoff is the complete queued task; the user can relay it to you.

### Codex update during the 0.5 split

I have promoted tested updates to `main.gd`, `player.gd`, `tests/integration.gd`, `tests/free_roam.gd`, `docs/MULTIPLAYER_DESIGN.md`, and a character-art pass in `character_model.gd`. The current `main.gd` now uses a first-person 360-degree driver camera, passenger free-look, a 30-second buy phase, buy-phase refunds, and an HQ supply counter without mid-round refunds. These files are Codex-owned; please keep edits to your listed files. The two existing gameplay suites pass (65 + 135 checks) against the pre-map 0.4 world.

One explicit map-art clarification: please remove any painted or labeled `MEETING POINT`/designated deal-zone markings from the city and map. Players choose any location for negotiations. The Exchange may remain a contract pickup landmark, but it is not an official place where meetings must happen.

When your `interactable_doors` interface is stable, record the exact metadata and method names in `CODEX_HANDOFF.md`. I will wire main.gd prompts and E interactions after your world changes land.

### 2026-09-29 15:42 EDT — Codex visual review of first map render
I rendered the current map. The continuous routes, fewer canals, varied east/north roads, and four off-corner HQs are working. Two visual criteria remain before COMPLETE: central Midtown reads as a tightly repeated orthogonal block grid, and the overall coastline still reads as a chunky rectangle from the full-map view. Please bend/break a few Midtown axes, vary block sizes or add a diagonal/open plaza connection, and soften at least one major edge of the land silhouette where possible without undermining equal central route times. Keep the one-inlet canal limit and crew HQ accessibility. I have fixed full-map landmark label collisions in my `main.gd` staging; you do not need to touch UI.

### 2026-09-29 15:46 EDT — Integration failure from new map
I pulled your current `world.gd`/`interiors.gd` into a separate staging checkout and ran both suites. `integration.gd` passes 70/70 including the new E-to-toggle storefront door interaction I added in `main.gd`. `free_roam.gd` now fails 1/137: "The wheelman drives off along the road loop". `world.gd` still builds `road_loop` from old fixed corners (-88,-88)/(88,-88)/(88,88)/(-88,88) near line 144, which likely cuts through the new Midtown geometry. Please update the loop to valid continuous drivable road points for the new map (or add a route API for the loop) and verify the practice bike can travel >8m from its (30,50) test start in 200 physics frames. Keep ownership of world.gd.

Visual finding: `world.gd:1512` still paints a giant "MEETING POINT" on the street (visible in my character close-up). This contradicts the anywhere-meetings design. Please remove the marking; the Exchange can keep its objective identity without claiming this is where deals must occur. The gantry comment at line 1464 is stale too.

### 2026-09-29 15:55 EDT — Vehicle render review
I pulled your new `car.gd` + `vehicle_kit.gd` into staging and captured the five-vehicle lineup. The external silhouettes are much more coherent (coupe, SUV and pickup read distinctly). Two capture issues: `capture_vehicles.gd` lineup_rear view at (10,1.6,52) is blocked by a large streetside post/new geometry, so move the review camera to actually show the rears; and the sedan driver's first-person `driver_chase` / `driver_driveby` views have a large opaque tan wedge along the left quarter of the screen that obscures the road. Please check the new interior/side shell geometry against the existing driver eye point, and adjust mesh or seat eye so the driver has a clear forward view while keeping pillars/doors as real cover.
