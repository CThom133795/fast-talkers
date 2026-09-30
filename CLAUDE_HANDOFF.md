# Project Fast Talkers — shared handoff

**Newest pickup (2026-09-30 overnight): branch `cloud/overnight-heavy-lift`. Read the "Overnight heavy lift" entry at the end of this file first. The paste-ready Claude Desktop command, which recreates the sub-agent split, is in `docs/CLAUDE_DESKTOP_PICKUP.md`.**

**Earlier pickup: Codex's city-detail pass is complete. Read `docs/CITY_DETAIL_HANDOFF.md` and the newest entry below. Historical ownership notes do not block the next coordinated pass.**

**Earlier local pickup: read `docs/VEHICLE_TIDY_HANDOFF.md`. The cabin/surface tidy pass is source-only until the normal-permission settings test and Windows export are rerun.**

## Shared objective
Original low-poly round-based business-negotiation shooter, eventual Steam release.
References for desired feel: Sub Rosa / No Big Deal round negotiations, GTA IV vehicle weight,
Battlefield / BattleBit responsive gunplay, Arma Reforger grounded movement, CS2 round buying.
PS2 / Xbox / GameCube visual era; development storage budget 75 GB.
Performance target (user, 2026-09-30): 60+ fps on the user's RTX 3080 at normal settings. A POTATO MODE
settings toggle serves bare-minimum PCs; it may hide decoration but never anything with collision.
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
Performance is judged on the user's RTX 3080 (60+ fps). The old ~1,550 draw-call 'potato' budget is retired;
keep batching sensible and use POTATO MODE (world.set_potato_mode) for minimum-spec machines.

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

---

## 2026-09-29 session — Codex COMPLETE: city detail, slower cars, diner and motel

Continue from cloud/map-integration (draft PR #1), not the map-only branch or master.
Full current handoff: docs/CITY_DETAIL_HANDOFF.md. Codex releases the changed files for Claude's next coordinated pass; earlier IN PROGRESS/ownership notes above are historical.

Built eight public spaces with 85 static furniture pieces, marked parking, protected park entrances, modest speed/acceleration reductions for all five vehicle types, a walk-in diner and a starter motel lobby/two rooms. Reused world batching and BuildingKit. No new core deal/trust/social mechanics implemented: those remain proposals per the user's explicit request. Same build required on every multiplayer machine.

Validation: 1,075 passing assertions, 6,000-frame soak, localhost host/client rounds, rendered screenshots and release startup. Busy downtown still exceeds the ~1,550 draw-call target. User will test friends tomorrow; genuine internet/human balance remains unverified. Next priority is that test and measured visibility/material optimization, then extend motel/diner and remaining placeholder landmark interiors. Preserve both exits, crew route fairness, deterministic creation order and actual collision tests.

My take: make Halcyon memorable through recognizable ordinary places and choices of approach/escape. Players should invent stories and meeting locations. Keep original art, readable low-poly silhouettes and purposeful detail. No official meeting zones or copied game appearance.

---

## 2026-09-30 overnight — Cloud Claude: overnight heavy lift (branch `cloud/overnight-heavy-lift`)

Branched from `origin/cloud/map-integration` at `de11b76`. Draft PR targets `cloud/map-integration`, never `master`.
Nothing here was run on Windows or a GPU. Captures and draw-call counts come from Xvfb with Mesa llvmpipe
(software OpenGL) on the Compatibility renderer. Treat the counts as renderer counts; the frame times mean nothing.
No executable was exported or modified.

**User direction captured this session.** Performance target is the user's RTX 3080 at 60+ fps; the old potato budget is retired
(see the top of this file). A POTATO MODE setting exists for minimum-spec PCs. Mood: "a world paused in time, ripe for deals and
deceptions" (late 1999). Steam play with friends should be as simple as possible for the end user. Guns should sound gritty and
boomy, with no "childish beeps".

### What landed (one commit per workstream; see `git log origin/cloud/map-integration..cloud/overnight-heavy-lift`)

1. **Landmark interiors (lead).** All on the existing BuildingKit; no new prefab system.
   - `scripts/buildings/nightclub.gd`, CLUB VOLTAGE. Street queue rope and canopy; lobby with coat check and cover charge;
     a 7×6 emissive dance floor; raised DJ booth with speaker stacks; a 13 m bar; lounge booths; a VIP mezzanine reached by a
     railed stair; back of house with stock and office. Exits: front, alley and side fire door.
   - `scripts/buildings/stripclub.gd`, THE VELVET ROOM. Tasteful, with no people or imagery. Windowless neon front; cashier booth;
     stage, runway and poles; horseshoe booths; bar; dressing room; office with safe. Exits on both side alleys.
   - `scripts/buildings/hotel.gd`, HOTEL MERIDIAN ground floor under a sealed tower. Reception with key cubbies, lounge, lobby bar
     with its own street door, lift lobby, back of house and a coffered ceiling. The lift cars are not fitted and are signed
     "service suspended".
   - `scripts/buildings/garage.gd`, CENTRAL PARKING. Three decks with two 11.7° ramps that a sedan can drive; tested to the roof.
     Two offset U-stairs, parapets, ticket booth, dust-sheeted static cars.
   - `scripts/buildings/highrise.gd`, HALCYON TRUST. Lobby plus a second-floor claims office with two working lifts
     (`kit.lift`, lobby↔2) and two U-stairwells at opposite corners; sealed 18-storey tower above.
   - `scripts/buildings/motel.gd`, SEA BREEZE upper storey. Rooms 201–204 on a railed roof walkway reached by independent
     east and west stairs; VACANCY pole sign. The drained pool still has no space on this 32×28 plot.
   - `scripts/buildings/burger.gd` plus `neighborhood_rooms.gd`. Drive-through lane with a glass pickup window, menu board and
     speaker; pole sign; awning; rooftop plant. `shell()` gained an optional `east_openings` argument.
   - **Fixes.** Interior floors were buried under the 0.16 m block plinth, so the street paving showed indoors. Club, strip club,
     hotel and high-rise floors now sit at 0.17 m, and the diner/motel overlay moved up. `BuildingKit.stairs_u` started its return
     flight at the landing's far edge; it is fixed, and the garage was its only caller.
   - `scripts/main.gd` interior sound beds: club bass in both clubs, room tone elsewhere, hall reverb in the garage. The garage roof
     and the motel walkway count as outdoors.
2. **City audit and draw calls (city agent).** Files: `scripts/world.gd`, `scripts/city_detail.gd`, `scripts/mesh_merge.gd`,
   `tests/city_audit.gd`, `docs/OVERNIGHT_CITY_PERF.md`.
   - Per-district shadow proxy, plus a clutter render layer that neon lights skip.
   - Software-GL draw calls: Midtown 1,741 → 1,235; north long view 2,027 → 1,499; Motor Mile 1,739 → 1,237; gun store
     1,593 → 1,079; Exchange interior ≈1,693 → 1,094.
   - Audit fixes: plinths on North Shore Road, floating picnic furniture (`world.surface_height`), repeated signs, empty
     promenade, z-fighting park paths, sunk props.
   - 1999 dressing: posters, window AC units, FOR LEASE shutters, clocks stopped at 11:59, boarded windows, rooftop plant,
     alley dumpsters, tyres, pallets, bunting, leaf drifts, oil stains.
   - `world.set_potato_mode(enabled)` hides only collision-free decor; the audit checks collision parity between modes.
3. **Vehicles (vehicle agent).** Files: `scripts/car.gd`, `scripts/vehicle_kit.gd`, `tests/vehicle_art.gd` (64 → 110 checks),
   `tests/capture_cabins.gd`, `docs/VEHICLE_TIDY_HANDOFF.md` ("Overnight pass").
   - Fixed: footwell hole, floating SUV/pickup seats, steering-wheel sight line, wheels proud of the body, wheel-well liners
     through the tyres, painted arch tunnels across the cabin, door seams in the arches, z-fighting.
   - Added: mirror, visors, plates, pickup mud flaps.
   - Driving, seat, door, glass and network APIs are unchanged.
4. **Audio (audio agent).** Files: `scripts/sfx.gd`, `tests/sfx_audio.gd` (321 checks), `docs/AUDIO_PASS.md`.
   - All 15 guns rebuilt: gritty crack, sub-bass boom, saturation and street slap; `_far` twins.
   - Sine "beeps" removed from bolt, pump, mag, draw, dry-fire, shell and cylinder.
   - New sounds: briefcase, cash, payphone, car door and engine, per-surface footsteps, 1999 ambience beds.
   - New API: `play_shot_at` and `set_space`.
   - Listen to `work/audio/*.wav`; regenerate them with `SFX_DUMP=1 godot --headless --path . --script res://tests/sfx_audio.gd`.
     Nobody has listened to them yet.
5. **Network security and Steam (network agent).** Files: `scripts/net.gd`, `scripts/online.gd`, `scripts/lobby_ui.gd`,
   `scripts/remote_player.gd`, new `scripts/net_security.gd`, new `scripts/steam_transport.gd`, `tests/net_security.gd`
   (91 checks), `docs/NETWORK_SECURITY_AND_STEAM.md`.
   - Security: host-validated relays; build-tagged handshake; rate limits, strikes and kicks; bounded snapshots; seat-0 car
     ownership; damage caps; killer attribution limits; string clipping.
   - The optional Steam (App 480 "Spacewar") transport is **written but unvalidated**: no Steam client or GodotSteam exists in
     the cloud. ENet stays the default.
   - `lobby_ui.gd`, `remote_player.gd` and `tests/remote_player.gd` are CRLF files. `git diff --check` flags only their CR
     endings; `git -c core.whitespace=cr-at-eol diff --check` is clean.
6. **Gameplay (feature agent, after SubRosa / No Big Deal research).** Files: `scripts/main.gd`, `scripts/player.gd`,
   `scripts/character_model.gd`, `tests/social_features.gd`, `docs/SUBROSA_NBD_RESEARCH.md`.
   - Hands up (X): a readable, honest peace signal, synced by state flag 128.
   - Binoculars (hold Z).
   - Contract round report.
   - POTATO MODE setting.
   - Audio hooks wired.
   - Deal and round rule changes (inspect-trade, anti-turtling clock, crew spectating, case-carrier cue) stay **proposals** for
     the user to decide.

7. **Voice chat (audio agent, at the user's explicit request; this overrides the earlier "no voice" rule).** Files: new
   `scripts/voice.gd`, `scripts/voice_codec.gd`, `scripts/voice_relay.gd`, `tests/voice.gd` (87 checks), `docs/VOICE_CHAT.md`;
   changes to `scripts/net.gd`, `scripts/main.gd`, `scripts/net_security.gd` (PROTOCOL 3 → 4) and `project.godot`
   (`audio/driver/enable_input=true`).
   - Open-mic proximity is the default and the intended way to play; the settings toggle reads "Open mic (recommended)".
   - Proximity push-to-talk is optional, on **N**.
   - Holding **Y** sends to the talker's crew only, at any distance, and mutes the talker in proximity. The host enforces this.
   - V and B were already bound, which is why the keys differ from the brief.
   - People inside a building hear each other; passers-by outside do not, except muffled within 4 m of the same open doorway.
   - The dead and the living are kept apart.
   - Codec: 16 kHz IMA-ADPCM, about 65 kbit/s per talker while speaking and nothing in silence.
   - All voice goes through the host, which validates it and relays it within 35 m.
   - **Untested:** a real microphone, a 2-PC run and echo. No echo cancellation or jitter buffer yet; headsets are recommended.
     See the Windows checklist in `docs/VOICE_CHAT.md`.

### Tests (Linux cloud, Godot 4.4.1 headless)
`bash tests/run_all.sh` on the final tree reports **OVERALL: PASS** (exit 0), with 1,710 assertions and 0 failures:

| Suite | Checks | Suite | Checks |
|---|---:|---|---:|
| vehicle_art | 110 | building_landmarks (new) | 187 |
| vehicles_06 | 24 | sfx_audio (new) | 321 |
| integration | 66 | social_features (new) | 29 |
| free_roam | 137 | net_security (new) | 91 |
| wiring_05 | 18 | remote_player | 74 |
| map_interiors | 97 | chat_ui | 46 |
| map_06 | 150 | net_lobby_ui | 84 |
| city_detail | 207 | city_audit (new) | 69 |

- soak: 6,000 frames, PASS.
- net_pair (two-process localhost host and client, lobby and round): PASS.
- `git diff --check` flags only CR line endings in three files that were already CRLF; `git -c core.whitespace=cr-at-eol diff --check` is clean.
- Not run: Windows, GPU, real Steam, internet play with real players, listening to the audio.

### Captures (software GL; review, not GPU validation)
- `docs/captures/overnight/interiors/*.jpg`: club, strip club, hotel, garage, burger lot, motel.
- `docs/captures/overnight/city/*.jpg`: city dressing.
- `docs/captures/overnight/vehicles/*.png`: cabins.
- Regenerate them with `tests/capture_interiors.gd [-- only=<prefix>]`, `tests/capture_cabins.gd`, `tests/capture_map06.gd -- only=detail`
  and `tests/capture_perf.gd`. Output goes to the ignored `work/captures/`.
- High-rise captures: `tower_street`, `tower_lobby`, `tower_office` and `tower_conference` in `docs/captures/overnight/interiors/`.

### Known limitations and open issues
- **Gun store vs Coast Road: fixed.** Coast Road ran through the Halcyon Arms range yard and past the long-range plates.
  It now swings east round the yard: (386,-105) → (388,-22) → (340,-22), rejoining its old line at x 340. The range is unchanged.
  `building_landmarks` checks the road stays clear, and `city_audit` no longer needs the exception.
- **Strip ring road meets the beach rock revetment** at about (24, 400). Also KNOWN in `city_audit`.
- **Props sunk 16 cm into the plinth** in the hotel, high-rise, burger, motel and nightclub lots. `city_audit` REPORTs them without
  failing. Use `world.surface_height()` for exterior solid props.
- Hotel guest floors, the hotel lift and stair, the motel pool, high-rise floors 3–18 and any roof access are not built.
- Surface-aware footsteps are not wired: there is no reliable surface lookup yet. Several new sounds have no trigger yet; see
  `docs/AUDIO_PASS.md`.
- Security gaps that remain: movement and health are still client-side; the host is fully trusted; ENet traffic is unencrypted;
  door toggles have no distance check.
- `free_roam`'s "round goes live when the buy timer runs out" check was flaky under heavy parallel load (it waits 6 frames for a
  0.05 s timer). It passed on every unloaded run.
- `Run Tests.cmd` was not edited here; Claude Desktop takes it over (see `docs/CLAUDE_DESKTOP_PICKUP.md`) and adds the new suites: `voice`, `city_audit`,
  `building_landmarks`, `sfx_audio`, `social_features`, `net_security`.

### Claude Desktop: next steps
1. `git fetch origin && git checkout cloud/overnight-heavy-lift`. Keep your local Windows-only files. Review the diff per commit.
2. Run the suites on Windows: `Run Tests.cmd` (after adding the six new suites above), and `tests/run_net_pair.ps1 -Steps 'lobby,round'`.
3. On the RTX 3080, run `tests/capture_perf.gd` windowed and confirm 60+ fps in the busiest views. Toggle POTATO MODE and compare.
4. Walk the new interiors, ride the high-rise lifts, drive up the garage, and listen to the guns, reloads and interior beds.
5. Steam: follow `docs/NETWORK_SECURITY_AND_STEAM.md`. Install a GodotSteam build that matches 4.4.1, put `steam_appid.txt` (480)
   beside the project and the exe, and run the two-PC checklist. `create_host` and `create_client` arguments are the likeliest
   thing to need adjusting.
6. Drive the rerouted Coast Road round the gun store, and decide on the proposals in `docs/SUBROSA_NBD_RESEARCH.md`.
7. Only after local validation: export, smoke-test, and decide whether to merge into `cloud/map-integration`. Never merge into `master`
   from here.
