# Build verification — prototype 0.1

## Verified

- Godot 4.4.1 imports and parses all gameplay scripts.
- The integrated main scene starts and advances without GDScript errors.
- Windows x64 release export succeeds; the executable includes its game data.
- The exported executable boots independently of the source project.
- The exported executable renders title, buy, first-person and driving views.
- Render captures reviewed at 1280×720; title content fits, city and sedan render, HUD is legible.
- Crosshair draws at the camera center. Mouse sensitivity uses screen-relative input.
- Matching beveled sidewalk visuals and collisions replace square movement-blocking ledges.
- Official editor and export-template archives verified against the release SHA-512 checksum list.
- Engine license and bundled third-party notices included beside the executable.

## Integration checks

See `tests/integration.gd` and run `Run Tests.cmd` for executable scene/physics checks. Coverage includes
economy debits, duplicate rejection, one-primary rule, finite ammo/reload, line-of-sight combat,
paid delivery, dropped-case recovery, loss streak and wallet cap, death/reset, actual car acceleration,
safe/unsafe exit, wall collision, robbery, blocked doors, pause and timeout.

Physics tests exercise the real scene and collision world. In headless mode the engine does not
capture the OS mouse, so scripted character motion is used for the sidewalk collision check.
Human mouse feel and driving quality still require hands-on testing.

## Environment-specific messages

The sandbox cannot read the system certificate store or create the default application shader cache.
Godot reports those restrictions during these test runs. This offline game does not use certificates;
render captures succeeded without a shader cache. These messages are not being hidden as gameplay
errors, and this run does not establish whether they occur outside the sandbox on another machine.
Logs are retained under this task's `work` directory.

## Not validated

Multiplayer, Steam functionality, low-end hardware performance, persistent settings, long sessions,
controller support, accessibility coverage, non-16:9 layouts and equivalence to reference-game feel.
No claim of a release-ready product or measured minimum hardware is made.

---

# Build verification — prototype 0.2 (Claude overnight pass, 2026-09-28)

## Verified

- `tests/integration.gd` (Codex's contract-loop suite): 59 checks, 0 failures, unchanged test file.
- `tests/free_roam.gd` (new): 53 checks, 0 failures, stable across repeated runs. Covers mode setup,
  weapon switching and per-weapon magazines, infinite reserve, shotgun pellets and shell reloads,
  recoil kick/recovery, spread, plate fall/reset, dummy head/body damage, the timed plate rack, armory rearm,
  security head shots, squad alerts, respawn/regroup, return to post, gunfire alerts, missed-shot handling,
  free-roam death/respawn, invulnerability, multi-car entry/exit, crash detection, run-over damage,
  contract-mode isolation (drill guards removed, one-primary rule, owned-only switching, armory closed)
  and settings persistence.
- `tests/soak.gd` (new): 6,000-frame chaos bot across both modes, 8 deaths, 15 car entries, no script errors;
  particle/decal/skid caps held.
- `tests/capture.gd` (new, windowed): 23 render review screenshots, reviewed by eye (sights, scope, HUD,
  guards, driving, menus).
- Windows release export rebuilt; the exported exe boots standalone and runs title → contract → driving →
  free roam via `-- --capture` with an empty error log.
- Draw calls measured on the development PC (RTX 3080, 1280×720, vsync off): before the performance pass the
  0.2 scenes measured 1,500–2,200 calls; after it they measure ~520–710 (mesh merging, 3D labels no longer cast
  shadows, 2-cascade shadows by default, outline instead of drop-shadow HUD text). Drop-shadowed `Label` text
  was costing ~2 draw calls per glyph in the Compatibility renderer; 0.1's HUD used the same style.

## Not validated

Human feel (recoil, sound, handling), low-end hardware frame rate, controller support, non-16:9 layouts,
long sessions beyond the soak, and anything multiplayer.

---

# Build verification — prototype 0.4 (Claude, 2026-09-29)

## Verified

- **`tests/integration.gd`** (Codex's contract suite): **59/59, file unmodified**. It covers the new buy
  phase, HQ delivery, vehicle seats and compound hulls, and the island map's quays.
- **`tests/free_roam.gd`: 135/135.** New checks cover:
  - pad A/B on menus using synthetic joypad events;
  - the live buy phase: countdown, holster, tabs by RB, strict purchase, swap with sell-back, sidearm swap,
    armour sell-back, attachment swap refund, carry-over for survivors and reset on death;
  - all 13 weapons firing, with distinct models, the AK vs M4 headshot rule, variant cycling on repeated keys
    and the revolver cylinder;
  - every vehicle type and seat count; drive-by lean-out; seat swap; window roll-down;
  - a passenger shot through the window hitting a target outside; fire-arc clamps; the pillion blocked cone;
  - the practice wheelman driving and pulling over; bike crash ejection; vehicle damage and wrecks;
  - the street tip flow (ring, answer, grab, bank without ending the round);
  - crew names.
- **`tests/soak.gd`:** 6,000 frames, both modes, no script errors.
- **Windowed captures reviewed by eye:**
  - all 13 weapons at hip and ADS (`work/captures/sheet_guns_*.png`);
  - the vehicle lineup and gunner views (`veh_*`);
  - every district, the capes, harbour, beach, pier and full map (`city_*`);
  - characters (`char_*`, `rig_*`).
- **Release export:**
  - `play-fast-talkers/Fast Talkers.exe` rebuilt.
  - It runs standalone with `-- --capture` (run from its own folder): title → buy phase → street → driving →
    free roam.
  - The log has 0 errors.

## Bug found and fixed while verifying

`MeshKit.rounded_box` produced un-indexed meshes. `MeshMerge` appends parts into one SurfaceTool, and when
any part in a material group is indexed (cylinders, spheres), the un-indexed parts are silently dropped. The
result was invisible gun slides and receivers, and missing car trim. This was present in 0.3 too. The rounded
box is now indexed.

## Performance (RTX 3080, 1280×720, vsync off, `tests/capture_perf.gd`)

| View | Draw calls | Frame |
|---|---|---|
| Midtown street | ~1,300 | 6.4 ms |
| Midtown, looking down the avenue | ~1,370 | 5.8 ms |
| Harbor | ~530 | 3.7 ms |
| Strip and beach | ~1,040 | 4.2 ms |
| Lantern Row | ~470 | 3.7 ms |
| Aerial | ~1,370 | 6.2 ms |

Draw calls are above 0.2's ~520–710.

**Causes:**
- About 30 real vehicles, each with about 20 surfaces. Vehicles are now culled past 130 m.
- District meshes merged into one instance per district, which can't be frustum-culled in pieces.

**Next steps:** split district merges into ~50 m spatial chunks, and atlas vehicle materials into vertex
colours.

**Low-end hardware is still unmeasured.**

## Not validated

- Human feel for the 13 weapons, 5 vehicles, drive-bys and buy-phase length.
- A real gamepad on menus. The fix is verified with synthetic joypad events, not a physical pad.
- Low-end frame rate, non-16:9 layouts, and anything multiplayer.
