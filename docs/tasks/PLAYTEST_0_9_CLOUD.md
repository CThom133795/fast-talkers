# Claude Cloud pickup: 0.9 playtest polish (heavy lifting)

Written by Claude Desktop (lead) on 2026-09-30 for tonight's friends playtest. The lead has already merged 0.9 into
`dev`:
- street props off the road;
- Halcyon Trust terrace and stair-trap fix;
- walk-in crew HQs;
- phone voice calls;
- host voice-routing speed-up;
- menu cleanup.

The lead exports the Windows build locally. Cloud sessions never export.

## How to pick up (paste this into a new Claude Code web session on `CThom133795/fast-talkers`)

> You are a Claude Cloud implementer on Project Fast Talkers. Read, in order: `docs/WORKFLOW.md`, `docs/CLOUD.md`,
> `docs/AGENT_BRIEF.md`, `docs/GAME_VISION.md`, `docs/LEAD_DESIGN_DECISIONS.md`, then this file
> (`docs/tasks/PLAYTEST_0_9_CLOUD.md`). Take **Task N** (below). Run `bash tools/cloud_setup.sh`, branch
> `cloud/<task-slug>` from `origin/dev`, stay inside that task's files, keep every suite green
> (`bash tests/run_all.sh`), merge `origin/dev` into your branch before opening a PR against `dev`, and put the
> suite table in the PR body. Never touch `master`. Never loosen a test.

Run **one task per session**. The tasks are ordered by value for tonight. Tasks 1 and 2 touch different files and can
run in parallel. Task 3 touches the lead's network files, so run it alone, and only when no other session has
`online.gd` / `net.gd` open.

## Standing rules (the user's, binding)

- No NPCs or traffic. Bots are for offline practice only.
- A match is a Week: Monday to Friday. Friday is always the Dead Drop, and it is a bloodbath.
- A crew wins on banked money, never on kills.
- One trade item means sidearm only. One phone per player. The host validates everything that moves money or items.
- World generation is deterministic (fixed seeds). Door indices are stable: doors sync by index, so creation order
  must not depend on anything random or order-unstable.
- Original names only. Sub Rosa and No Big Deal are conceptual references only.
- **Nothing solid stands in a road carriageway.** Props that break sightlines or stop corner cutting go on the free
  gray ground (sidewalk corners, empty lots), never in the street. `tests/city_fill.gd` checks this.
- Stairs are walked by `tests/stair_walk.gd`. Every flight has a closed underside and rails on its open sides (the
  kit does this).
- Performance budget on the user's RTX 3080: ≤ 1,600 draw calls in the worst view, ≥ 60 fps. On Linux, watch the
  headless draw and mesh counts that `tests/city_detail.gd` and `tests/city_fill.gd` print, and don't let them climb
  more than 10 %.

## Task 1: Lantern Row and Kingsway come alive (`cloud/districts-enterable`)

**Why.** After 0.8, 82.6 % of buildings are enterable, but Lantern Row (Kojimoto, NW) and Kingsway (Royals, SE) are
still 0 %: solid `_tower` shells around the crew HQs. The user: "everything besides Midtown feels EMPTY".

**Do.**
- In `scripts/world.gd` `_build_lantern_row` and `_build_kingsway`, replace the non-HQ `_tower` shells with
  `BuildingPrefabs.build(...)` kinds that fit each district. Keep the footprints and the district feel:
  - Lantern Row: pachinko hall, ramen bar, capsule hotel, izakaya, karaoke;
  - Kingsway: project stairwells, corner store, laundromat, youth club, barber.
- If the prefab library lacks a kind, add it to `scripts/buildings/prefabs.gd`.
- The target is ≥ 60 % of each district's buildings enterable.
- **Don't touch** the crew HQ sections (`scripts/buildings/crew_hq.gd` and its calls): they were just rebuilt.

**Files.** `scripts/world.gd` (those two district functions only), `scripts/buildings/prefabs.gd`,
`tests/prefabs.gd`, `tests/building_landmarks.gd`.

**Accept.**
- `tests/prefabs.gd`, `tests/stair_walk.gd`, `tests/building_landmarks.gd`, `tests/city_audit.gd`,
  `tests/city_fill.gd`, `tests/crew_hq.gd` and `tests/free_roam.gd` stay green.
- The enterable percentage per district is printed by a new check.

## Task 2: Startup time and memory (`cloud/startup-speed`)

**Why.** The exe takes about 14 s to reach the title screen and uses about 1.9 GB of RAM. Friends will quit if the
first launch looks hung.

**Do.**
- Profile the world build headless: time each district builder, `CityFill.build`, `CityDetail`, prefab builds and
  mesh merges. Use `Time.get_ticks_usec()` spans behind a `--profile-build` user arg.
- Then cut the worst offenders:
  - cache shared meshes and materials (one `BoxMesh` per size bucket, one material per colour/texture key);
  - build interiors' small props lazily, the first time a player comes within about 60 m of the building;
  - avoid `SurfaceTool` re-commits.
- Keep the visual result identical. The screenshots in `docs/captures` are the reference, so describe any
  difference.
- Add a loading line on the title ("Building Port Halcyon…") if the build is still over 5 s.

**Files.** `scripts/world.gd` (helpers `_box`, `_material`, `_cylinder`), `scripts/mesh_merge.gd`,
`scripts/mesh_kit.gd`, `scripts/buildings/building_kit.gd` (`finish_props` only), and a new
`tests/build_profile.gd`.

**Coordinate.** If Task 1 is open at the same time, don't edit the district functions. Merge `origin/dev` often.

**Accept.**
- The build time (headless, printed) drops by ≥ 30 % and the node count doesn't rise.
- Every suite stays green, and the determinism checks still pass.

## Task 3: Rejoin keeps your Week (`cloud/rejoin`); lead files, run alone

**Why.** Nothing restores a player who drops mid-Week. On a friends' playtest, someone *will* crash or lose Wi-Fi.
Today they come back as a stranger with no cash, gear or crew.

**Do.**
- The host keys each player's Week state on a stable identity: the Steam ID when on Steam, else the chosen name
  plus crew. That state is:
  - crew;
  - personal cash and gear (weapons, armor);
  - whether they carried the phone or a case (drop those at their last position on disconnect, as today).
- On rejoin the same Week restores them (at their crew's HQ spawn if the Day is live), and the lobby shows
  "RETURNING".
- Late joiners also need the current door open/closed states and the live phone-call states. The world event log
  only replays changes after joining, so add a compact snapshot sent on `hello`.

**Files.** `scripts/online.gd`, `scripts/net.gd`, `tests/week_flow.gd`, `tests/net_security.gd`, and a new
`net_pair` step `rejoin` in `tests/net_pair.gd` / `tests/run_net_pair.sh`.

**Accept.**
- A new `net_pair` step disconnects the client mid-Day, reconnects, and checks that its crew, cash and gear are
  back.
- A door that the host closed before the client joined is closed for the client.
- All suites stay green. `net_security` checks that a rejoin can't claim someone else's identity (a Steam ID from
  another connection is refused).

## Not for the cloud (the lead or the user tonight)

- A real two-PC Steam join test. The join side has never been tested on two machines.
- Real-microphone checks: open-mic proximity, the crew radio, and phone calls (pickup of 1.2 m, speaker of 3.5 m).
- Controller check on a real pad, with Steam Input off for Spacewar (see the walkthrough).
- The export: run `tools\build_playtest.ps1` on Windows. It also installs into `play-fast-talkers`.
