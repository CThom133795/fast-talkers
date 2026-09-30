# Claude → Codex (ChatGPT) handoff channel

This is Claude's reply channel. `CLAUDE_HANDOFF.md` is Codex → Claude. Each agent appends
dated entries at the bottom of its own file; neither agent edits the other's file.
The user relays when needed. Newest entry is at the bottom.

---

## 2026-09-28 22:05 EDT — Claude: overnight polish pass started

User request to Claude: "Test and polish as many systems as you can so I have a nice demo to play in
the morning. I need at least an option that lets me explore the world and demo the guns." The user also
asked Claude to leave this file so Codex can pick up where Claude stops. The user reported Codex's
session ended at ~22:00, so Claude edited `scripts/`, `tests/`, `project.godot` and the export in place.

---

## 2026-09-28 23:05 EDT — Claude: pass COMPLETE, prototype 0.2 exported

**Ownership:** Claude is finished. `scripts/`, `tests/`, `project.godot`, launchers and the export are
yours again. If Claude resumes, it will claim files here first.

**Your pre-Claude state is preserved** — diff it against the live tree to review everything:

| What | Path |
|---|---|
| Your final source at fork time (22:00) | `work/claude-base/` |
| Your 0.1 exe | `work/backup-codex-0.1/Fast Talkers 0.1 (Codex).exe` |
| Render review screenshots | `work/captures/*.png` (regenerate with `tests/capture.gd`) |

`git diff --no-index work/claude-base/scripts outputs/project-fast-talkers/scripts` → ~2,800 insertions.

### Verification (all green at hand-off)

| Suite | Result |
|---|---|
| `tests/integration.gd` — **your file, unmodified** | 59 checks, 0 failures |
| `tests/free_roam.gd` — new | 53 checks, 0 failures (repeated runs stable) |
| `tests/soak.gd` — new chaos bot, 6,000 frames, both modes | no script errors |
| `tests/capture.gd` — new, run windowed | 23 screenshots, reviewed by eye |
| Release export, exe run standalone with `-- --capture` | boots, renders free roam, empty error log |

`Run Tests.cmd` now runs all three headless suites and prints each exit code.

### What changed, by file

**New files**
- `scripts/sfx.gd` — procedural sound bank (per-weapon shots, reload/pump/bolt, hit/headshot/kill ticks,
  steel ring, whiz, footsteps, crash, door, UI, cash) + 14 2D voices + 10 positional voices; seamless
  loops for engine, skid, horn, ambience. API: `play(name, pitch, gain_db)`, `play_at(name, pos, ...)`,
  `stream(name)`, `master_db(extra)`, `volume`.
- `scripts/effects.gd` — capped tracers, impact debris (world/flesh/steel/dust/car), bullet decals (ring
  buffer 90), brass, muzzle omni-light pool, damage numbers, tyre marks (ring buffer 360), smoke. `clear()`.
- `scripts/range_target.gd` — `kind` "plate" (falls, resets after `reset_delay`) or "dummy" (100 hp, head
  zone). Optional `travel` slide. Signal `struck(amount, headshot, downed, at)`. `hit_zone`, `take_hit`,
  `take_damage`, `reset_target`. Local +Z faces the shooter.
- `scripts/armory.gd` — armory yard east of the main road (bench, rack, plate rack, dummies, heavy plates,
  mover) and long-range lane on the east street (plates at 26/40/54/67 m). Consts `SPAWN`, `RACK`,
  `LONG_LINE_X`; arrays `targets`, `rack`.
- `scripts/mesh_merge.gd` — `merge_children(node)` collapses sibling MeshInstance3Ds into one ArrayMesh with
  a surface per material (materials reused, so flashes/brake lights still work). Used by world, cars,
  armory, targets.
- `tests/free_roam.gd`, `tests/soak.gd`, `tests/capture.gd`, `docs/PLAYTEST_CHECKLIST.md`.

**`scripts/main.gd`** (largest change; every function your tests call keeps its name and behaviour)
- Free Roam mode: `free_roam` flag, `_start_free_roam()`, all weapons + infinite reserve + regen, no clock/
  economy, briefcase hidden, drill guards present, death → respawn at armory (`_respawn`), rearm (`_rearm`,
  E at rack or T), free-roam pause menu (rearm, return to armory, reset world, invulnerable, settings).
- Multi-car: `cars` array (4 colours, `CAR_SPAWNS`); `car` is now "the last car entered". `_nearest_car`.
  `_lock_controls` freezes every car (your pause test still passes).
- Security: `_all_guards()`; `drill_guards` (3 extra, free roam only, `set_present(false)` in contracts).
  `_alert_guards(near := INF)`: contract = all guards + `violence` (unchanged); free roam = guards within
  38 m. Gunfire within `GUNFIRE_ALERT_RADIUS` (7 m) of a calm guard alerts. Free-roam guards regroup after
  `GUARD_RESPAWN` (12 s).
- Combat: `_on_shot` adds range falloff, head-shot multipliers (`hit_zone`), target routing, impacts,
  tracers from the muzzle. New `_on_weapon_fired` (sound, muzzle light, brass, pump/bolt cycle, accuracy
  stats), `_on_weapon_event`, `_register_hit`, `_on_target_struck`, timed plate-rack drill (`rack_best`).
  `guard_shot(origin, end, hit := true)` — misses continue to an impact and whiz past the player.
- Shop: shotgun $1,100 and marksman $2,200 added (`PRICES`, `SHOP`, `PRIMARIES`). One-primary rule kept.
  Contract loadout is pistol + purchased primary, switchable (CS-style); resets each round.
- HUD rebuilt (bars, ammo panel, slots, prompts panel, dynamic crosshair drawn on `overlay`, which is aliased
  as `crosshair` for your centering test; hit/head/kill markers; damage arcs; scope; minimap with building
  footprints, cars and guards). HUD text uses outlines — **drop-shadowed Labels cost ~2 draw calls per
  glyph in the Compatibility renderer** (one message was 281 calls).
- Settings persisted to `settings_path` (`user://settings.cfg`): volume, sensitivity, FOV, fullscreen,
  shadows (Off / Medium default / High), FPS counter. F11 / F3 hotkeys. Pause on focus loss
  (`pause_on_focus_loss`, disabled by capture scripts).
- Driving: chase-camera mouse orbit with auto-recentre, speed FOV, crash shake, gear-shifting engine loop,
  skid loop + tyre marks + smoke, horn (H), door sounds. Title camera orbits the district.
- `_capture_views` also saves `work/freeroam.png`.

**`scripts/player.gd`** — five weapons (`WEAPONS` keeps your keys; adds name, ads_time, pellets, spread,
recoil, head-shot, falloff, per_round, scope, sound). Inventory: `owned`, `switch_weapon`, `cycle_weapon`,
`quick_swap`, `set_loadout`, `refill`, per-weapon magazine memory; `equip(id)` still means "grant full and
select". Camera recoil with recovery (shots use the camera ray + spread cone, so crosshair and impact still
agree), bloom, FOV-scaled ADS sensitivity, sight-aligned ADS (`_sight_height`, aperture/notch + front post),
scope (`is_scoped`), shell-by-shell shotgun reload (fire interrupts), draw time, sway/bob, muzzle
obstruction pose, landing dip, death tilt. New signals: `weapon_fired`, `weapon_event`, `damaged(amount,
source)`, `footstep`, `landed`. `take_damage(amount, source := INF)`, `invulnerable`, `regenerate`,
`infinite_reserve`, `face(yaw)`, `muzzle_position()`, `ejector_position()`, `current_spread()`.

**`scripts/guard.gd`** — new model (suit, tie, glasses, raised/lowered arms), hit flash + flinch, fall-back
death, strafing when hostile, walk back to post when calm, deterministic accuracy budget
(`hit_chance`: distance, target speed, crouch), no firing without line of sight, `hit_zone`,
`set_present`, `home_yaw`. Damage per hit unchanged (9).

**`scripts/car.gd`** — `paint_color`, `model_name`, `spawn_transform`/`reset_to_spawn`, brake/tail and head
lamp emission, `crashed(strength)` signal, run-over damage to anything with `take_damage`, telemetry vars
(`throttle_input`, `slip`, `braking`, `handbrake_on`, `longitudinal_speed`), `rear_contacts()`, merged body
mesh. **Handling constants untouched.**

**`scripts/world.gd`** (small) — yard crates moved out of the firing lanes, `footprints` for the minimap,
`sun` exposed for the shadow setting, 3D labels no longer cast shadows, leftover one-off boxes merged.

**`project.godot`** — description/version 0.2 only.

### Design calls Claude made that you should review

1. Recoil and spread now exist (first-pass numbers). Rays still start at the camera, so aim/impact agree.
2. Contract players carry pistol + primary and can switch (was: primary replaced pistol).
3. Firing within 7 m of calm security alerts them (contract: makes the deal hostile).
4. Guard hit chance is a deterministic budget (0.12–0.9) rather than always-hit-on-sight.
5. Shotgun and marksman prices ($1,100 / $2,200) are placeholders for economy balancing.

### Known issues / not done

- Human feel untested: recoil, sound mix, engine note and handling need the user's feedback
  (`docs/PLAYTEST_CHECKLIST.md`).
- Low-end hardware FPS not measured; draw calls ~520–710 on the dev PC after the performance pass.
- `docs/MULTIPLAYER_DESIGN.md` (your original ask of Claude) is still not written.
- Your `integration.gd` prints a benign "ObjectDB instances leaked at exit" (audio playbacks alive when the
  harness quits the same frame). `free_roam.gd`/`soak.gd` wait 10 frames before `quit()` to avoid it.
- Guards hold a post; no navigation, cover-seeking or reloading.

### Suggested next tasks (acceptance criteria)

1. **Feel pass from user feedback** — adjust `WEAPONS` numbers / car exports; keep both suites green.
2. **Authoritative LAN slice** (DEVELOPMENT_PLAN milestone 1). `_on_shot`, `_purchase`, `_pay_deal`,
   `_finish` and `_alert_guards` are the natural server-authority seams; `player.shot_fired` already
   carries origin/direction/damage per pellet.
3. **Security navigation** — cover points around the exchange; accept when guards never stand in the open
   for >3 s while hostile and never path through buildings.

---

## 2026-09-28 23:33 EDT — Claude: 0.3 pass IN PROGRESS (read this before touching anything)

**User's new brief to Claude (verbatim intent):** write the multiplayer design doc; typical matches are
*multiplayer only, no AI*; compare Sub Rosa and No Big Deal and improve on them, with the focus on skill and
player interaction rather than funny jank; Steam controller support; a weapon attachment system; a
visually striking PS2/GameCube/Xbox-era art style that stands apart from Sub Rosa and NBD; four teams:
**mafia, street gang, cartel, yakuza**. Expand the world, using NBD/Sub Rosa/PS2-era GTA map design, into
crew districts plus neutral common areas that tie them together.
The user asked that Codex **organise and develop the design further** while Claude works, and leave
suggestions Claude can read when it resumes.

### File ownership while this entry says IN PROGRESS
- **Claude owns** `scripts/`, `tests/`, `project.godot` and the export. Please do not edit them.
- **Codex owns** new files under `docs/` (any names except the three below), plus your own `CLAUDE_HANDOFF.md`.
- **Claude owns** `docs/MULTIPLAYER_DESIGN.md`, `docs/PLAYTEST_CHECKLIST.md` and `docs/BUILD_VERIFICATION.md`.
  Propose edits to them in your own file, not in place.

### Done so far in 0.3 (code state may be mid-change; run `Run Tests.cmd` before trusting it)
- `docs/MULTIPLAYER_DESIGN.md` v1 is written. It covers:
  - the reference teardown table (Sub Rosa / NBD / ours), crews, the Week and contract structure;
  - the deal system: handshake atomic trade, escrow, counterfeit tells, Street Rep;
  - the no-AI rule, network architecture, controller plan, the attachment table, art direction, milestones.
  - Some **[BUILT]** tags are aspirational until this pass finishes; Claude will correct them.
- `scripts/factions.gd` holds the four crews: Famiglia Varano (mafia, crimson, fedora), Kingsway Royals
  (street gang, teal, cap), Cártel Sol Negro (cartel, gold, cowboy hat), Aogiri-kai (yakuza, violet, pompadour).
- `scripts/character_model.gd` builds a stylised crew member: colour-blocked wardrobe, hat silhouette,
  crew armband and ink outline.
- `scripts/retro_textures.gd` generates 64 px procedural textures with nearest filtering and world triplanar mapping.
- `scripts/world.gd` has been **rewritten as Port Halcyon**, 400 × 400 m, with Midtown kept as the centre:
  - Crew districts: Lantern Row NW, Solana Heights NE, Little Varano SW, Kingsway SE.
  - Neutral areas: Harbor N, Union Station S, Canal Market W, The Strip E.
  - Dusk lighting and neon.
  - Not yet compiled or tested at the time of writing.

### Still to do in 0.3 (Claude's queue, in order)
1. Compile and fix the new world, and move practice bots onto the character model with rival crew outfits.
2. Crew selection, crew car paint, crew sleeves on the viewmodel, HUD accent, and a title-screen crew lineup.
3. Player-centred radar plus a full-screen city map (M / Back), now that the city is 400 m.
4. Controller support: sticks, triggers, menus with focus, Xbox/PlayStation prompt names, vibration, settings.
5. Weapon attachments: optic / muzzle / underbarrel / magazine, gunsmith menu, contract shop, visible models.
6. Era post-filter (posterise, dither, grade, toggle).
7. Update Codex's two boundary tests. The city limit moved from ±81 m to ±200 m. Only the coordinates change.
8. Captures, performance check, export, and docs/handoff wrap-up.

### What Claude would like from Codex (write answers in CLAUDE_HANDOFF.md or new docs/ files)
1. **Economy numbers for the Week.** Contract payouts per type, starting cash, loss relief, and attachment
   prices vs gun prices. Make "trade beats kill" hold mathematically. A small table plus rationale.
2. **Contract specs.** Transaction, Dead Drop, Double Ledger and Courier: exact spawn rules, reveal timings,
   win conditions for 3-crew and 4-crew matches, and edge cases (item destroyed, Boss disconnects, tie).
3. **Street Rep / Heat rules.** Precise triggers, decay, UI, and exploit review (can a crew farm or dodge it?).
4. **Mission-site list for Port Halcyon.** Use the landmarks in `world.gd` (`_landmark(...)` calls). Pick
   two per neutral zone and score each for cover, sightlines, approach routes and fairness to each HQ.
5. **Crew lore and voice.** A one-paragraph bio, three HQ interior beats and three signature taunts or
   quick-chat lines per crew. Keep them original and non-stereotyped. They are archetypes, not real groups.
6. **Server/network task breakdown for milestone M1**, sized in days, using §10–§11 of the design doc.
7. Anything in the design doc you disagree with. Say so plainly, with the reason.

Claude will read `CLAUDE_HANDOFF.md` and `docs/` first when it resumes, and fold agreed points into
`MULTIPLAYER_DESIGN.md`.

### 2026-09-29 00:05 EDT — Claude: art direction update from the user (still IN PROGRESS)
The user saw the first 0.3 renders and said:
- "we can increase the poly count where we need; I don't like how blocky the characters / overall game looks"
- "I want a cartoonish animation style; it should feel fluid, not blocky. Early 2000s gamer vibes."

Direction Claude is now implementing, in order:
1. **Characters.** A procedural rig (hips / torso / head / shoulders / elbows / hips / knees) with springy walk,
   strafe, idle breathing, aim-raise overshoot, hit flinch, and a bouncy cartoon death. Also: exaggerated
   proportions (big head, hands and feet), capsules and rounded boxes, toon (cel) shading and ink outlines.
   `scripts/mesh_kit.gd` provides the rounded box, capsule, sphere, cylinder and torus helpers.
2. **Viewmodel guns and hands.** Rounded parts, finger capsules, toon shading, damped-spring weapon motion,
   and the attachment system (optic / muzzle / underbarrel / magazine).
3. **Cars.** Rounded cartoon bodies, toon shading, springy squash-and-stretch suspension.
4. **World.** Toon shading, softer (less crunchy) textures, bubbly trees and rounded props, and building
   outlines if the performance cost is acceptable.
5. Colour grade post-filter, then tests, captures, export and docs.

Codex: please fold "cartoon, fluid, early-2000s" into any art or design notes you write. Touchstones for
mood only: cel-shaded and cartoon open-world crime/driving games of 2001–2004. Copy nothing.

---

## 2026-09-29 — Claude: 0.3 pass STATE AT HAND-OFF (Claude is low on usage — Codex, please guide the final push)

### Status in one line
Most of 0.3 is built and tested in source. **The exe in `play-fast-talkers/` is still the 0.2 build** unless a later
entry below says it was re-exported. Run `Build Windows.cmd` after verifying.

### Verified at this point (headless)
- `tests/free_roam.gd`: **84 checks, 0 failures**. New checks cover attachments, the contract attachment shop,
  gunsmith, laser, pad bindings, glyph switching, trigger driving, map toggle, 9 districts / 4 HQs, rival crew
  outfits, the animated rig, the film grade, and crew persistence.
- `tests/integration.gd` (yours): passed 59/59 after the city change. **Only change:** the three boundary
  coordinates now use `game.world.HALF` because the city limit moved from 80 m to 200 m. Re-run it; it has not
  been re-run since the last art commits.
- `tests/soak.gd`: not re-run since 0.2. Please run it.

### What 0.3 contains (all in `scripts/`)
- **Port Halcyon** (`world.gd`, rewritten around your Midtown, which is intact):
  - 400 m city.
  - Crew districts: Lantern Row NW / Aogiri, Solana Heights NE / Sol Negro, Little Varano SW / Varano,
    Kingsway SE / Royals.
  - Neutral areas: Harbor N, Union Station and rail yard S, Canal Market W (canal plus 3 bridges), The Strip E.
  - Roads, beveled block plinths, lamps, neon (`_neon`), dusk/day lighting (`set_dusk`), grime textures,
    street furniture (`_street_life`), puddles and steam vents.
  - Exposes `districts`, `landmarks`, `crew_spawns`, `footprints`, `steam_vents`.
- **Crews** (`factions.gd`): four crews, identity only (the same rules for all).
- **Character rig** (`character_model.gd`):
  - Rounded stylised-gritty crew members, thin ink outline.
  - Procedural spring animation: walk, strafe, idle, aim, flinch, death.
  - Practice bots (`guard.gd`) use it, dressed as rival crews. The title screen shows a four-crew lineup.
- **Mesh kit** (`mesh_kit.gd`): rounded box, capsule, sphere, cylinder, torus. `mesh_merge.gd` now also merges
  non-shadow parts.
- **Viewmodel** (`player.gd`):
  - Rounded guns, gloved hands with fingers, and a thin outline.
  - Damped-spring weapon motion.
  - **Attachments:**
    - `ATTACHMENTS` / `SLOTS` with optic / muzzle / underbarrel / magazine, visible on the model.
    - Stats go through `compute_stats`. API: `set_attachment`, `options_for`, `fits`, `attachment_summary`.
    - The marksman's scope can be swapped for a reflex.
- **Cars** (`car.gd`): rounded body with grime band, torus tyres, crew liveries (`stripe_color`), spring
  suspension (`jolt()` on crashes). **Handling constants untouched.**
- **Controller** (`main.gd` `_setup_gamepad`, `_glyph`, `_input`, `_rumble`; `player.gd` `_pad_look`):
  - Full pad play: sticks, triggers, menus with auto-focus, B to go back.
  - Xbox/PlayStation prompt names, vibration.
  - Pad settings: look speed, invert, vibration.
- **UI:**
  - Player-centred radar with district tint.
  - Full city map (M / View).
  - Gunsmith (B / D-pad right, or from the pause menu).
  - Contract attachment shop.
  - Crew selection on the title screen and pause menu.
  - Settings for lighting and film grade.
- **Film grade** post-process (grain, split tone, vignette) on its own CanvasLayer under the HUD.
- `docs/MULTIPLAYER_DESIGN.md`: design doc v1 (reference teardown, crews, the Week, contracts, deal/trust
  systems, the no-AI rule, network architecture, controller, attachments, art, milestones).

### Art direction (the user's own words, in order)
1. "PS2/GameCube/Xbox era", striking, and different from Sub Rosa / NBD.
2. "Increase poly count where needed; I don't like how blocky it looks."
3. "Cartoonish animation style, fluid, early-2000s gamer vibes."
4. "Don't lean too heavily into cartoon; we want grittiness in this crime game."
5. "Keep the world lively and colourful but don't go full Toontown."

Current result:
- Smooth shading, rounded forms, thin ink lines, fluid spring animation with little squash.
- Dusk neon, grime streaks, trash, puddles, steam, colourful street furniture, and a subtle film grain.

### What Claude did NOT get to (the final-push list, priority order)
1. **Re-run all suites and the soak, then re-export and smoke-test the exe.** Use `Build Windows.cmd`, then run
   `Fast Talkers.exe -- --capture` and check `work/freeroam.png`.
2. **Performance check on the bigger city.** Measure draw calls with the captures. The 0.2 baseline was
   ~520–710; the city is roughly 6× the area. If it is too high, add visibility ranges on district merged
   meshes, cut street-life density, and drop `Label3D` neon beyond ~120 m.
3. **Docs.**
   - `MULTIPLAYER_DESIGN.md`:
     - §6.1: reflex now also fits the marksman.
     - §13: say "stylised-gritty", not cartoon.
     - Confirm the [BUILT] tags for city, crews, controller and attachments. These are now true.
     - §9: the server-build strip of `guard.gd` is still PLANNED.
   - README, `START HERE.txt`, the playtest checklist and `BUILD_VERIFICATION.md`: add a 0.3 section.
4. **Visual polish seen in captures:**
   - The torso chest block reads a little "puffy". Try `character_model.gd` chest radius 0.12 → 0.07.
   - Lantern Alley is still dark. Consider two warm OmniLights, or more lit windows.
   - News boxes near the camera read as floating: they need a contact shadow or a darker base.
5. **Controller:** menus have not been tested with a real pad. The glyphs are text names. Steam Input API
   (GodotSteam) is PLANNED only.
6. `tests/capture_city.gd`, `capture_characters.gd` and `capture_guns.gd` are the windowed review tools. Run
   them (not headless) and read `work/captures/`.

### What Claude would like Codex to decide or answer (append in CLAUDE_HANDOFF.md)
- Your review of the art balance in `work/captures/char_*.png`, `city_*.png` and `gun_*.png` against the user's
  five notes above.
- The economy, contract, Street Rep, mission-site and M1 network task breakdowns requested in the 00:05 entry.
- Anything in `docs/MULTIPLAYER_DESIGN.md` you would change before M1 (LAN slice) starts.

### 2026-09-29 00:10 EDT — addendum: verified and exported
- `integration.gd` **59/59**, `free_roam.gd` **84/84**, `soak.gd` **clean** (6,000 frames, no script errors).
- **`play-fast-talkers/Fast Talkers.exe` is now the 0.3 build.** It was run standalone with `-- --capture`,
  the log is error-free, and `work/freeroam.png` was written. `project.godot` version is 0.3.
- Items 2–6 of the final-push list above are still open. The performance measurement on the big city is the
  most important one.

---

## 2026-09-29 01:45 EDT — Claude: 0.4 pass IN PROGRESS (read before touching anything)

**User's brief (their words, condensed):** read all handoffs; consider changing engine — characters still look
too cartoonish; controller works in gameplay but NOT on any menu; the map should not be a square — analyse the
maps referenced in the handoffs (Sub Rosa, No Big Deal, PS2-era GTA) and reshape it; several weapons per class,
unique (start with an AK-type and an M4-type rifle, do the same for every class); the parked "vehicles" can't be
entered — fix it; add vehicle types (SUV / coupe / motorcycle) with passenger seats you can shoot from (windows,
back of a bike); make buying a real **pre-round buy phase** (CS-style); study the Sub Rosa and No Big Deal loops
(creator videos, clips) and optimise our core loop toward skill and player interaction, "anything can happen in a
city full of crime, deals and gunfights". **Rename: mafia → Morris Mafia, yakuza → Kojimoto893.**

**Ownership:** Claude owns `scripts/`, `tests/`, `project.godot`, launchers, the export and the three Claude docs
until an entry below says COMPLETE. Codex: new files under `docs/` and `CLAUDE_HANDOFF.md` only.
**Backup of the 0.3 state (source + exe):** `work/backup-0.3-before-0.4/`.

**Queue (in order; ticked items are recorded in later addenda):**
1. Crew renames (Morris Mafia, Kojimoto893) everywhere incl. district names.
2. Controller on menus (root-cause, then fix + headless test with synthetic joypad events).
3. Buy phase: freeze-time + buy menu (B / pad), buy & sell-back, keep gear if you survive, round timer.
4. Weapon roster: 2+ per class (pistols, SMGs, rifles AK/M4, shotguns, marksman), unique handling/models/sounds.
5. Vehicles: every parked car enterable; SUV / coupe / motorcycle (+ sedan); seats; passenger & drive-by shooting;
   offline practice driver so a solo player can test passenger shooting.
6. Map: non-square city shaped by coastline/river/bridges (research-driven), keep Midtown.
7. Characters: realistic proportions, less toon (engine decision recorded in design doc).
8. Research write-up: `docs/LOOP_ANALYSIS.md` (Sub Rosa / NBD loops → our loop changes).
9. Tests, captures, export, docs, this file.

### 0.4 progress addendum (02:40 EDT) — still IN PROGRESS
- [x] 1 Renames: `morris` / MORRIS MAFIA (district MORRIS PARK), `kojimoto` / KOJIMOTO893 (ids changed in factions.gd).
- [x] 2 Controller menus: ROOT CAUSE — Godot 4.4's built-in `ui_accept`/`ui_cancel` have NO joypad buttons
  (only Enter/Space/Escape). D-pad moved focus but A never pressed and B never backed out. Fixed in
  `_setup_gamepad` (A→ui_accept, B→ui_cancel). Verified with synthetic joypad events.
- [x] 3 Buy phase: `Phase.BUY` is now a live 25 s freeze at the crew HQ (look/walk the yard, holstered),
  non-pausing tabbed buy menu (B / D-pad right, LB/RB tabs), sell-back of this round's purchases, swap within
  a slot, survivors keep gear (CS rules). `_purchase(item, cost)` semantics unchanged for your tests.
  Contracts now start and end at the player's crew HQ (`HOME` is a var set per crew).
- [x] 4 Weapons: 13 (3 pistols, 3 SMGs, M4 + KV-47 rifles, 3 shotguns, 2 marksman). Ids `pistol smg rifle
  shotgun marksman` kept as each class's base. Per-weapon `mods` replace attachment `fits`.
- [x] 5 Vehicles (car.gd rewrite): sedan/coupe/SUV/pickup/motorcycle, seats + doors + fire arcs, compound
  hull with open windows, window roll-down, vehicle health/wreck, practice wheelman autopilot. Parked
  "props" are now real vehicles (`world.parked_vehicles`). Your integration.gd: **59/59, file unmodified**.
- [ ] 6 Map reshape  - [ ] 7 Characters  - [ ] 8 Research doc  - [ ] 9 Tests/captures/export/docs
- [x] 6 Map (03:30): Port Halcyon is now an island city: four crew islands (channels at x/z = ±88 outside the
  Midtown ring), two bridges each, capes round each HQ corner (Lantern Point pagoda, Solana Lookout, Morris
  Marina, Kingsway Docks), harbor basins + moored freighter, Halcyon Beach + Ocean Drive + pier/Ferris wheel,
  ferry pier. `world.land` (polygons), `world.roads` (polylines), `world.bridges`, `world.draw_map()`,
  `world.district_at()`, `world.map_bounds()`. North quay z=-200 and west quay x=-200 kept for your tests.
  Both suites green (integration 59/59 unmodified, free_roam 130/130).
- [ ] 7 Characters (next): procedural SKINNED human (Skeleton3D + one mesh), realistic proportions, face texture.
- [x] 7 Characters (04:20): `character_model.gd` is now a procedural SKINNED human: Skeleton3D (17 bones) + one
  mesh (body with vertex colours + textured head with a painted 128 px face), 1.8 m realistic proportions,
  overlay shirt fronts/ties/lapels, crew armband, hats. Same API (build/animate/flinch/set_dead, seated/riding,
  eye_height()). No outlines anywhere now (guns, cars, characters).
- BUG FIXED (existed in 0.3): MeshKit.rounded_box was un-indexed; MeshMerge mixing it with indexed primitives
  dropped every rounded box in that material (gun slides, receivers, car trim). rounded_box now calls index().
- Suites: integration 59/59, free_roam 130/130, soak clean. Captures: work/captures/sheet_guns_*.png, veh_*, rig_*.
- [ ] 8 Research doc + street events (next)  - [ ] 9 docs/export

---

## 2026-09-29 04:35 EDT — Claude: 0.4 pass COMPLETE, exported

**Ownership:** Claude is finished. `scripts/`, `tests/`, `project.godot`, launchers and the export are yours again.
0.3 backup (source + exe): `work/backup-0.3-before-0.4/`.

**Status:**
- `play-fast-talkers/Fast Talkers.exe` is **0.4**. The smoke capture run has an error-free log.
- integration.gd **59/59, unmodified**. free_roam.gd **135/135**. soak clean.

### What the user asked for, and what now exists
| Ask | Result |
|---|---|
| Consider changing engine; characters too cartoonish | **Engine kept** (reasoning in design doc §13). Characters rebuilt as procedural skinned humans; outlines removed everywhere |
| Controller works in game but not menus | Root cause: Godot 4.4 `ui_accept`/`ui_cancel` have no joypad buttons. Bound A/B. Tested with synthetic joypad events |
| Map is a square; use the referenced maps | Island city: 4 crew islands × 2 bridges, capes, harbour basins + freighter, beach + Ocean Drive + pier. See design §8 |
| More than one rifle (AK + M4), same for every class | 13 weapons: 3 pistols, 3 SMGs, M4 + KV-47, 3 shotguns, 2 marksman. Design §6 table |
| Enterable parked vehicles; SUV/coupe/motorcycle; shoot from windows / back of a bike | Every parked car is real. 5 types, seats, fire arcs, drive-bys, pickup-bed + pillion gunners, damage/wrecks, practice wheelman |
| Buy system should be a pre-round buy phase | 25 s live buy phase at the crew HQ, tabbed menu, sell-back, survivors keep gear |
| Analyse Sub Rosa / NBD loops, creators and clips; optimise for skill + interaction | `docs/LOOP_ANALYSIS.md` (I could not watch video; titles, wikis and dev interview used). Street tips built |
| Morris Mafia, Kojimoto893 | Renamed everywhere (ids `morris`, `kojimoto`) |

### APIs you will touch
- **`main.gd`**
  - `vehicle` / `seat` (null / -1 on foot). `car` is still "last vehicle entered".
  - `_enter_vehicle(car, seat)`, `_exit_vehicle(force)`, `_swap_seat()`, `_ride(car)`.
  - `_start_wheelman` / `_dismiss_wheelman` (practice only).
  - `_buy_weapon(id)` (UI path, swaps a slot), `_purchase(item, cost)` (strict, **your semantics unchanged**),
    `_sell(item)`, `_purchase_attachment` (refunds this round's replaced part).
  - `purchased` holds price paid per item. `buy_time_left`, `buy_menu_open`, `HOME` (a var, crew HQ).
  - Street tips: `_reset_tip`, `_ring_tip`, `_tip_interact`, `tip_state`.
- **`player.gd`**
  - `WEAPONS` has `class`, `price`, `one_hand`, `action`, `weight`, `mods`, `desc`.
  - `VARIANTS`, `SLOT_ORDER` (classes), `replace_in_class`, `owned_in_class`, `drop_weapon`.
  - Seats: `enter_seat`, `leave_seat`, `seat_vehicle`, `seat_eye_local`. `can_fire` (buy phase),
    `input_grace`.
- **`car.gd`**
  - `TYPES`, `vehicle_type`, `seats`, `occupants`, `seat_eye`, `door_position`, `nearest_free_seat`,
    `next_free_seat`, `set_window_open`.
  - `take_damage`, `disabled`, `wrecked` signal, `start_autopilot` / `stop_autopilot`, `is_bike`.
  - Sedan handling constants are yours, untouched.
- **`world.gd`**
  - `land`, `roads`, `bridges`, `quay_gaps`, `parked_vehicles`, `road_loop`, `payphones`.
  - `draw_map`, `district_at`, `map_bounds`.
  - `HALF` keeps the north quay (z = -200) and west quay (x = -200) where your tests expect them.

### Design calls to review
1. **Survivors keep gear (CS)** replaces "equipment resets each round" (NBD). The user asked for a CS-style
   pre-round buy.
2. **Contracts start and end at the crew HQ**, not the Midtown office. Distance makes vehicles matter.
3. **The practice wheelman is an AI.** It exists only in free roam, like security, and never in matches.
4. **The west islands have an extra canal chokepoint** compared with the east ones. Measure in playtests.
5. **Tip value is $900** against a $2,600 contract. It needs tuning.

### Suggested next tasks (with acceptance criteria)
1. **Draw calls:**
   - Split each district's merged mesh into ~50 m spatial chunks, and give vehicles a vertex-colour atlas
     (one material plus glass).
   - Target: Midtown under 900 draw calls (`tests/capture_perf.gd`), with both suites green.
2. **Real gamepad pass:** verify menus, buy tabs and drive-by on an Xbox and a DualSense pad, and fix any
   focus traps.
3. **Authored characters:**
   - If the user approves downloads, import a CC0 base mesh (MakeHuman export or similar) into the
     `character_model.gd` API (build / animate / seated / eye_height).
   - Otherwise, keep refining the procedural sculpt.
4. **Tips v2:** hot cars (deliver to a chop shop) and dead-drop reveals; in multiplayer, a tip goes to one
   crew and can be sold.
5. **M1 LAN slice** (unchanged from the design doc).

---

## 2026-09-29 15:10 EDT — Claude: 0.5 MAP / INTERIORS / RAILINGS / VEHICLE ART — IN PROGRESS

Accepting the split in your 2026-09-29 CLAUDE_HANDOFF entry.
**Claude edits only:** `scripts/world.gd`, `scripts/car.gd`, new `scripts/interiors.gd`, new
`tests/map_interiors.gd`, new `tests/vehicle_art.gd`, `tests/capture_city.gd`, `tests/capture_vehicles.gd`,
new `docs/MAP_0_5.md`, this file. `tests/free_roam.gd` (Claude's suite) only if a map assertion must move — I will
list every such change.
**Not touching:** `main.gd`, `player.gd`, `docs/MULTIPLAYER_DESIGN.md`, `CLAUDE_HANDOFF.md`, `project.godot`,
`README.md`, `integration.gd`, the export.
**Backup of 0.4 source before this pass:** `work/backup-0.4-before-claude-0.5/`.

Queue:
1. [ ] Map: continuous asymmetric land, far fewer canals, organic street network, plazas, multi-approach districts,
   crew HQs off the corners, fair HQ→Exchange route times (measured over the road graph).
2. [ ] Midtown interiors: majority of signed storefronts enterable, sign-matched props, `world.interactable_doors`.
3. [ ] Railings: collision matches visible solid material; shots pass over rails; low fall-protection kept.
4. [ ] Vehicle art: consistent late-90s/early-00s fleet, same seat/door/window/driving APIs.
5. [ ] Tests + captures + COMPLETE entry.

### 0.5 progress addendum (Claude) — still IN PROGRESS
- [x] 1 Map (first pass lands): one continuous mainland with a single dead-end canal inlet (Canal Market) and the
  West Slip. Each neighbourhood keeps its own skewed street grid. Bent arterials, waterfront drives, the Fountain
  Square roundabout and plazas tie them together. HQs: Lantern Row W, Solana Heights NE, Kingsway E, Morris Park S.
  Road-graph HQ→Exchange: 229 / 229 / 228 / 234 m. The integration suite (your current 65 checks) and free_roam 137
  both pass, unmodified. New world API: `route(from,to)`, `route_length`, `kit_transform`, `footprint_polys`,
  `plazas`, `is_on_land`, and `crew_spawns[*].spawn/spawn_yaw/door`.
- [ ] 2 Interiors (writing `scripts/interiors.gd` + `scripts/breakable_glass.gd` now)
- [x] 3 Railings: quay coping plus a thin top rail. Both are real colliders; the 2.8 m invisible barrier is gone.
  The beach has a 0.72 m rock revetment. Chain-link fences are shoot-through above a 1.2 m windbreak.
- [ ] 4 Vehicle art  - [ ] 5 Tests/captures/COMPLETE
- [x] 2 Interiors: 12 walk-in Midtown businesses (`scripts/interiors.gd`) with a real doorway, door leaves (a roller shutter
  at the garage), breakable shop glass (`scripts/breakable_glass.gd`) and sign-matched rooms. CARGO 04 stays sealed (range
  backstop). API: `world.interactable_doors`, `set_door_open`, `toggle_door`, `door_near`, `glass_panes`, `reset_glass`.
- [x] 4 Vehicle art (first pass): profile-extruded bodies with real wheel-arch cut-outs (`scripts/vehicle_kit.gd`). Glass
  follows the pillars. One wheel family: hubcap / 5-spoke / off-road / bike. Seat, door, pane and driving APIs are unchanged.
  Hull roofs trimmed to match the models (sedan 1.5, coupe 1.3, SUV 1.92).
- [ ] 5 New tests (`tests/map_interiors.gd`, `tests/vehicle_art.gd`), full suites, final captures, COMPLETE entry.

---

## 2026-09-29 16:40 EDT — Claude: 0.5 MAP / INTERIORS / RAILINGS / VEHICLE ART — COMPLETE

**Ownership:** Claude is finished. `world.gd`, `car.gd` and my test and capture files are yours to integrate.
0.4 backup: `work/backup-0.4-before-claude-0.5/`. Full write-up: `docs/MAP_0_5.md`.
I did not touch `main.gd`, `player.gd`, `MULTIPLAYER_DESIGN.md`, `CLAUDE_HANDOFF.md`, `project.godot`, the launchers or the exe.

### Your 15:42–15:55 review items
- **Meeting-point markings:** removed. The orange squares, the MEETING POINT and NORTHLINE/SAFEHOUSE labels, and `_build_markers`
  are gone. The gantry comment now says the Exchange is a contract landmark, not a meeting zone.
- **Midtown grid:**
  - Canal Street west of Halcyon Avenue is now Canal Walk: pedestrian, bollards at both ends.
  - Two diagonals: BROADWAY (NE corner to Meridian) and PARK ROW (SW corner to Union Street).
  - Eastbank Square and Corner Park replace the two sealed towers at (61,-66) and (-61,60).
- **Coastline:** headlands and bays on the east, west and south-west shores. Still one canal inlet.
- **Wheelman:** `road_loop` is now a dense right-hand-lane ring (64 points). New `world.wheelman_path(from)` follows streets to the
  ring first. In `_start_wheelman`, please use `target.start_autopilot(world.wheelman_path(target.global_position), ...)`.
  Your (30,50) test start is now inside the HOTEL CARLYLE lobby (a hollow building), so the bike can't get out.
  In `tests/free_roam.gd` I changed exactly two lines:
  - line 426: `bike.reset_car(Vector3(91, 0.1, 40))` (on the ring)
  - line 444: `bike.reset_car(Vector3(66, 0.1, 35))`
  - I also added one diagnostic print before the pull-over check.
  Please carry these into your staged copy.
- **Sedan driver wedge:** the driver's eye was 0.2 m behind the windscreen. The sedan glasshouse moved forward (screen base
  z -1.17, roof front -0.5) and the A-pillars are thinner. `veh_driver_chase.png` now shows a normal framed windscreen.
- **lineup_rear:** the vehicle capture is now a studio lineup in the harbour yard: side, three-quarter front and rear, and a
  close-up of each type, with the HUD hidden.

### Changed and new files
- `scripts/world.gd`: map, roads, route graph, kit placement, railings, plazas and squares; calls interiors.
- New `scripts/interiors.gd`: 12 walk-in businesses.
- New `scripts/breakable_glass.gd`
- `scripts/car.gd`: new bodies and wheels; hull roofs trimmed; `wheel_r` retuned.
- New `scripts/vehicle_kit.gd`
- New `tests/map_interiors.gd` (96 checks), new `tests/vehicle_art.gd` (40 checks), new `tests/dump_map.gd` (layout JSON and routes).
- `tests/capture_city.gd`, `tests/capture_vehicles.gd`, `tests/capture_perf.gd` (views moved to the new districts).
- `tests/free_roam.gd`: the 2 lines above.
- New `docs/MAP_0_5.md`

### APIs for main.gd (all in world.gd unless noted)
- **Doors:** `interactable_doors[i]` = `{index, label, kind, position, inside, outside, open, district, width}`.
  - `set_door_open(i, bool)`, `toggle_door(i)`, `door_near(at, radius=2.2) -> int` (-1 if none).
  - Doors start OPEN. Kinds: exchange, imports, logistics, authority, freight, bar, hotel, pawn, cafe, store,
    garage (roller shutter), laundry.
- **Glass:** `glass_panes[i]` = `{body, shop}`. Panes break through your existing `collider.take_damage` branch.
  Call `reset_glass()` at round start if windows should come back.
- **Routing:** `route(from, to)` / `route_length(from, to)` for a GPS line on the radar or map. Also `wheelman_path(from)`.
- **Crew bases:** `crew_spawns[crew]` also has `spawn`, `spawn_yaw` and `door`. Your current 2.5 m-toward-centre rule is tested clear
  for all four crews. `spawn`/`spawn_yaw` also face the player out of the door.
- **Map data:** `footprint_polys`, `plazas`, `is_on_land(at)`, `kit_transform(kit)`. `draw_map` draws plazas and door dots.
- **Parked cars:** `parked_vehicles` includes a GARAGE COUPE inside Midtown Garage. Drive it out through the roller door.
- **Vehicles (car.gd):** every seat/door/window/driving API is unchanged.

### Tests (Godot 4.4.1, headless, run after the final edits)
| Suite | Result |
|---|---|
| integration.gd (current file) | 66/66 |
| free_roam.gd | 137/137 |
| soak.gd | clean: 6000 frames, no script errors |
| map_interiors.gd | 96/96 |
| vehicle_art.gd | 40/40 |

Please add `map_interiors.gd` and `vehicle_art.gd` to `Run Tests.cmd`.
Performance (`capture_perf.gd`, RTX 3080):

| View | Draw calls | Frame time |
|---|---|---|
| Midtown | 1,546 | 9.2 ms |
| Harbor | 609 | 5.7 ms |
| Lantern Row | 789 | 5.8 ms |
| Exchange interior | 1,310 | 7.3 ms |

Midtown is up about 250 draw calls from 0.4. The chunking task is still the fix.

### Compromises (details in docs/MAP_0_5.md)
- Sol Negro and Kingsway HQs are both east-side, 123 m apart. Routes are equal (228–234 m).
- Shop glass stops shots and bot line of sight until it is broken.
- Chain-link is solid below 1.2 m (a windbreak screen).
- Interiors are ground floor only.

---

## 2026-09-29 16:55 EDT — Claude: 0.5 INTEGRATION + EXPORT — IN PROGRESS (user-authorised takeover)

The user reports ChatGPT/Codex is out of usage and asked Claude to finish Codex's integration and hand over an exe.
**Claude now owns everything until this entry says COMPLETE:** `main.gd`, `player.gd`, `project.godot`, launchers, the export,
and the tests. I searched the disk for the staging checkout mentioned in CLAUDE_HANDOFF (door prompt, 70-check integration)
and found nothing, so that wiring is being redone in the live `main.gd`.
Backup of everything (source, launchers, 0.4 exe): `work/backup-before-claude-0.5-integration/`.
Queue:
1. [ ] Doors: E prompt + toggle.
2. [ ] Glass reset each round.
3. [ ] Wheelman via `wheelman_path`.
4. [ ] HQ spawn/facing from `crew_spawns`.
5. [ ] Radar/map GPS route to the objective.
6. [ ] `Run Tests.cmd` + new suites; version 0.5; export; smoke-run the exe; COMPLETE entry.

---

## 2026-09-29 17:10 EDT — Claude: 0.5 INTEGRATION + EXPORT — COMPLETE (exe shipped)

**`play-fast-talkers/Fast Talkers.exe` is now 0.5.** It was exported headless with no errors. A standalone smoke run
(`-- --capture`) produced an error-free `work/release-smoke.log` and wrote title/buy/gameplay/driving/freeroam PNGs to `work/`.
`project.godot` version is 0.5. `START HERE.txt` has a 0.5 section.
**Ownership:** back to the normal split. Codex owns main.gd/player.gd/launchers/export again. Backup of the pre-integration
state (source + 0.4 exe): `work/backup-before-claude-0.5-integration/`.

### Wiring done in main.gd (I could not find your staging checkout, so this is my own version)
- **Doors:**
  - `_shop_door_in_reach()`: a door within 2 m, unless a car door is nearer.
  - `_interact` toggles it. `_prompt_text` shows OPEN/CLOSE THE DOOR, or RAISE/CLOSE THE SHUTTER, plus the shop name.
- **Rounds:** `_reset_world_state` calls `world.reset_glass()` and reopens any shut shop doors.
- **GPS:**
  - `_update_gps` recomputes `world.route()` once a second during contracts: home (teal) when carrying the case or a
    stash, the case (amber) otherwise, the tip stash (blue) when active. It hides within 12 m of the target.
  - `_draw_gps` draws on the radar and the full map. The live-start message mentions the route line.
- **Wheelman:** `_start_wheelman` uses a street route to the ring plus the loop. car.gd
  `start_autopilot(path, speed, loop_from)` treats the lead-in as one-way.
- **HQ spawn:** already used `crew_spawns.spawn/spawn_yaw` (yours). Unchanged.

### Fix found during integration
- The new coastline triangulated into metre-thin land slivers hundreds of metres long, and vehicle hulls snagged on them.
- Land collision is now cut into 32 m cells (`world._grid_faces`); render meshes are unchanged.

### Tests (all green, run after the final code)
| Suite | Result |
|---|---|
| integration | 66/66 |
| free_roam | 137/137 |
| soak | clean |
| map_interiors | 96/96 |
| vehicle_art | 40/40 |
| new wiring_05 | 13/13 |

wiring_05 covers doors (prompt, E, physical block), round reglaze/reopen, the GPS line to the case and home, and a wheelman
driving 98 m of street from Lantern Row with no stalls. `Run Tests.cmd` now runs all six.

### Still open for you
- Midtown draw calls (~1,550) need district chunking.
- Practice wheelman: if its bike is parked nose-to-tail behind another car it bumps and reverses. Worth a smarter stuck
  escape later.
- Real-pad test, and authored characters (unchanged from earlier lists).

---

## 2026-09-29 17:40 EDT — Claude: 0.6 "FIRST PLAYABLE ROUND" — IN PROGRESS (user brief, Claude owns all files)

Codex is still out of usage, so the user handed this whole pass to Claude. **Claude owns every file until this entry says COMPLETE.**
Backup of 0.5 source: `work/backup-0.5-before-claude-0.6/`.

User brief, verbatim intent:
- Car glass too opaque, and it should break.
- 1st/3rd-person toggle while driving.
- Tighter handling (slightly slippery).
- More interiors across the whole map:
  - multi-floor businesses in big buildings;
  - more windows where fitting;
  - trademark locations: hotel, parking garage, motel, night club, strip club, burger joint, a high-rise with two or more lifts (not a chokepoint).
- Bigger map, with HQs further apart (urgency when betrayed).
- The firing range becomes a GUN STORE with a range, not on the contract map (free roam only).
- Payphones ring independently for each crew.
- 10:00 round.
- Research Sub Rosa / No Big Deal design.
- **A networked demo round the user can play with a friend.**

Queue (ticked as it lands):
1. [ ] Vehicles: clearer glass; breakable car glass; 1P/3P driving camera toggle; tighter grip/steer.
2. [ ] Round: 10:00 street phase; per-crew payphone tips.
3. [ ] Research doc `docs/REFERENCE_RESEARCH.md` (Sub Rosa / NBD interviews and wikis).
4. [ ] Networking M1 slice (`scripts/net.gd`, `scripts/remote_player.gd`): ENet host/join, lobby, crews, synced players, cars,
       shots/damage, items (ledger, cash case, decoys), deal round, chat/phone, results. Includes a two-process headless test.
5. [ ] Map 0.6: larger city, HQs further apart, new districts with trademark buildings, multi-floor interiors with stairs and lifts,
       and the gun store moved off the contract map.
6. [ ] Tests, docs, export, START HERE, COMPLETE entry.

### 18:30 update — vehicle work landed; plan re-prioritised by the user
- [x] Vehicles:
  - glass alpha 0.2 (was 0.7);
  - every window breaks: shots through `main._break_car_glass`, and hard crashes;
  - the glass is one mesh per car;
  - V / R3 toggles a 1st/3rd-person vehicle camera, saved in settings;
  - tighter handling: grip-capped yaw, proportional lateral decay, faster self-centring.

  Suites green: vehicle_art 52, integration 66, free_roam 137. A new `tests/vehicles_06.gd` is being written.
- The user asked Claude to act as tech lead with Sonnet subagents (`.claude/agents/` in the session dir) and to put a
  **minimum playable multiplayer round** first. Map and interior expansion waits until that works. Agent brief:
  `docs/AGENT_BRIEF.md`.

### 19:40 update — multiplayer slice in progress; git + GitHub + cloud
- **The project is now a git repo, pushed to a PRIVATE GitHub repo `CThom133795/fast-talkers`.** Commit to branches.
  Cloud Claude sessions work on `cloud/<task>` branches and open PRs; see `docs/CLOUD.md`.
- **Online (M1 slice):**
  - `docs/NET_M1_SPEC.md` is the contract.
  - `scripts/net.gd` covers ENet, the lobby, RPCs and the security rules.
  - `scripts/lobby_ui.gd`, `scripts/remote_player.gd` and `scripts/chat_ui.gd`.
  - `scripts/online.gd` holds the match: remotes, seats, car puppets, items (Ledger, cash case), host round rules and
    payouts. Hooks are in main.gd.
  - The two-process test `tests/run_net_pair.sh` passes the lobby steps. Round steps are being added.
- **Map 0.6:** the plan is `docs/tasks/MAP_0_6_PLAN.md`. M1 (layout, plots, gun store) is running as a cloud task.
  Don't edit `world.gd`, `interiors.gd` or `armory.gd` locally until its PR merges.
- **All suites:** `bash tests/run_all.sh`.

### 21:20 update — 0.6 FIRST ONLINE BUILD EXPORTED
- `play-fast-talkers/Fast Talkers.exe` is 0.6. `outputs/Fast Talkers 0.6.zip` is the shareable copy, and
  `HOW TO PLAY ONLINE.txt` is the connection guide.
  - The 0.5 exe is backed up in `work/backup-0.5-exe/`.
  - The exe smoke run is clean.
- **Verified:**
  - all offline suites are green;
  - net_lobby_ui 84, remote_player 74, chat_ui 48;
  - the two-process net_pair `lobby,round` gives 125 checks and passed 6 runs in a row;
  - a windowed two-instance screenshot review (`tests/run_net_visual.sh`, images in `work/captures/net/`).
- **Open / next:**
  - **Real internet playtest by the user.**
  - Map M1 PR from the cloud (review, then M2 buildings in parallel).
  - Per-crew payphone tips online.
  - Decoy/counterfeit items.
  - In-game voice.
  - Lead hooks from the map PR: `set_mode`, lifts.
  - Host authority for movement and wallet before any public play.

## 2026-09-30 — Claude Desktop (lead): COMPLETE — 0.7 playtest build, heavy-lift integration, design choices
Branch: `cloud/overnight-heavy-lift` (Windows checkout). Never merge into master. Codex: please don't edit files on this
branch until this entry says COMPLETE; put suggestions in CLAUDE_HANDOFF.md.
Goal from the user: a demo exe in the morning and `Fast Talkers Playtest.zip` for a 2+ player Steam (Spacewar) playtest.
The user delegated design choices on improving the No Big Deal / Sub Rosa systems to Claude as lead designer.
- [x] Local tree was clean; checked out the branch.
- [x] `Run Tests.cmd` rewritten: all 18 suites in a loop (CRLF kept).
- [x] Windows baseline: all 18 suites green with counts identical to Linux (integration 66, free_roam 137, soak PASS, map_interiors 97, vehicle_art 110, wiring_05 18, vehicles_06 24, map_06 150, city_detail 217, city_audit 72, building_landmarks 204, sfx_audio 321, social_features 29, net_security 91, voice 87, remote_player 74, chat_ui 46, net_lobby_ui 84); net_pair lobby,round PASSED (host 67, client 62).
- [x] GodotSteam 4.22.1 GDExtension in `addons/godotsteam` (win64 + linux64), `steam_appid.txt` (480). Real Steam host
      verified on this PC: init, friends-only lobby with tags, SteamMultiplayerPeer host. Join side untested (needs 2 accounts).
- [x] Lead hooks: `net.los_check`, `net.map_half_extent` (implementer, main.gd); `net_pair` turns LOS off only for its
      cross-city synthetic claims.
- [x] `docs/LEAD_DESIGN_DECISIONS.md` (binding), and W0 in online.gd:
  - the Week, the Dead Drop, the morning paper with "who shot whom", and END OF WEEK;
  - crew phones with the call gate, and one trade item with the sidearm rule;
  - SOLO WEEK and Quick Week;
  - the belt phone and the speaking cue on remotes;
  - the nervous client and host telemetry.
  `tests/week_flow.gd` covers it.
- [x] Export + zip: `tools/build_playtest.ps1` -> `outputs/Fast Talkers Playtest.zip`; exe smoke on the RTX 3080 shows
      `[steam] ready (app 480)` and SOLO WEEK starting. Walkthrough: `tools/playtest/HOW TO PLAY WITH FRIENDS.txt`.
- [x] Workflow: `docs/WORKFLOW.md` (dev = integration branch, master = the user's), CLOUD.md / AGENT_BRIEF / README updated;
      master's design notes merged in.
- [x] Final regression on HEAD 43301b5 (Windows, one suite at a time), all 0 failures:
  - integration 66, free_roam 137, soak PASS, map_interiors 97, vehicle_art 110, wiring_05 18;
  - vehicles_06 24, map_06 150, city_detail 217, city_audit 72, building_landmarks 204, sfx_audio 321;
  - social_features 55, net_security 91, voice 87, remote_player 79, chat_ui 46, net_lobby_ui 84, week_flow 80;
  - net_pair lobby,round PASSED (host 68, client 62).
- [x] GPU perf on the RTX 3080: every view 71–103 fps (numbers in docs/OVERNIGHT_CITY_PERF.md, "GPU numbers"). The game is
      draw-call bound; POTATO MODE saves little.
- [x] `dev` created from this branch; the dev -> master PR is left for the user.

### For Codex (next queue, in order; branch from `origin/dev`, PR into `dev`, see docs/WORKFLOW.md)
1. After the playtest: read the host's `%APPDATA%\Godot\app_userdata\Project Fast Talkers\telemetry\*.jsonl`. It has one
   line per Day. Tune the nervous-client timing and the contract values from it.
2. Trust systems T1 (deals board, caller ID, host-side "broken deal") and then T2, per docs/DESIGN_WEEK_TRUST.md and
   docs/LEAD_DESIGN_DECISIONS.md §10. online.gd is lead-owned, so propose hooks or take an explicit task.
3. Known gaps:
   - A rejoining player gets their crew bank back but not their personal cash or gear.
   - Phone calls are text chat. Voice calls over the phone are future work.
   - Movement and health are still client-side.
4. City and perf (draw calls): sign text into a texture, a shared prop palette, and a POTATO draw distance.
