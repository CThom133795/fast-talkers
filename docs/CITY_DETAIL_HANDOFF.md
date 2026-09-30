# City detail and driving playtest — Claude pickup

## Current source of truth

Continue `cloud/map-integration` in the existing `CThom133795/fast-talkers` repository. The open draft integration PR is https://github.com/CThom133795/fast-talkers/pull/1. This branch contains the newer multiplayer work, the recovered `cloud/map-m1` expansion, and this city-detail pass. **Do not rebuild from the old map-only branch, overwrite master, or create a second game project.** Check status and preserve any subsequent local changes before editing. This entry supersedes the old active ownership split in the top of CLAUDE_HANDOFF.md: Codex has finished this pass and releases the changed files for the next coordinated pass.

Windows primary checkout: `C:/Users/CThom/Documents/Codex/2026-09-28/i-want-to-create-a-game/outputs/project-fast-talkers`. The separate `C:/Users/CThom/projects/cloud/fast-talkers` checkout holds the recovered map-only source; it is not the integrated multiplayer build. Cloud Claude should fetch and branch from `origin/cloud/map-integration`; it cannot update the user's Windows executable directly.

## The user's direction, and my interpretation

The user wants an original social negotiation city with the feeling of coming back tomorrow with friends. Lego Island/GTA are emotional references, not visual templates. Sub Rosa/No Big Deal inform the deal-centered social play. My take: recognizable places, believable everyday objects, several ways to approach and leave, and incidents players can retell. “Meet behind the diner” should be natural player language. No official meeting zones, imposed safe zones, copied assets, or NPC clutter.

The user explicitly asked to **suggest, not implement**, new deal incentives, apologies, restitution or trust systems. See `docs/REFERENCE_RESEARCH.md`; those proposals remain unimplemented. No economy, combat reward, inventory, voice or trust logic changed in this pass. The user cannot test with friends until tomorrow. Automated localhost multiplayer is checked; real internet/human play remains necessary.

## What is built

- Eight authored spaces: Trust Plaza, West End Gardens, Old Town Green, Nightlife Commons, Sunset Picnic Lawn, West Bank Promenade, Nightlife Parking, Wharf Workers Lot.
- **85 new static props**: raised planters, benches, picnic tables, hot dog carts, newsstands, community boards, bins and parking wheel stops. Parking has marked bays and a central manoeuvring aisle. No additional driveable vehicles or dynamic lights outdoors.
- Placement rejects roads plus shoulders, building footprints, entrances, crew spawns and parked cars. Existing sidewalk scatter leaves park-path entrances open. Planters/fixtures discourage straight car cuts across public spaces; streets stay open. Small detail meshes are merged per site and culled beyond 85 m with an 8 m margin. Colliders persist at distance.
- **BIG BOY BURGERS** replaces its sealed shell: four booth tables, order counter, service hatch, kitchen counters/griddles, refrigerator, real front and rear doors, breakable storefront windows, a clear 3 m central aisle.
- **SEA BREEZE MOTEL** replaces its sealed shell: reception/key board, waiting booth, ice machine, two furnished rooms with beds/desks/CRT-style monitors and doors, front/rear exits and a clear corridor. This is a single-storey starter, not the completed planned motel.
- Reusable `scripts/buildings/neighborhood_rooms.gd` demonstrates shells, booths, desks and interior finish on the established BuildingKit. Interior furnishings/linings use layer 2, 45 m visibility and one lamp per building. Keep extending that kit; no competing prefab architecture is needed.
- Restored test isolation: integration.gd no longer reads the user's real saved vehicle camera preference.

The carts/stands/benches are static scenery: no buying food, sitting, NPC merchants, destructibility or healing. Low wheel stops are not guaranteed to stop a speeding car. Large planters and fixed fixtures are the stronger barriers. Run-over damage and vehicle durability are unchanged; this is a conservative handling pass, not proof vehicles are balanced.

## Driving numbers

Speeds are metres/second in code. Brakes, reverse limits, grip, seats, durability and network movement interfaces are unchanged.

| Vehicle | Old top km/h | New top km/h | Old acceleration m/s² | New acceleration m/s² |
|---|---:|---:|---:|---:|
| Sedan | 113.4 | 90.0 | 7.2 | 5.6 |
| Coupe | 129.6 | 102.6 | 9.0 | 7.0 |
| SUV | 100.8 | 81.0 | 6.0 | 4.8 |
| Pickup | 104.4 | 82.8 | 6.4 | 5.0 |
| Motorcycle | 136.8 | 108.0 | 11.0 | 8.2 |

All online players must use this same build: door/glass indices and world-generated car order must match. Do not mix the earlier map executable with this one.

## Validation completed

**1,075 assertions passed**, plus the 6,000-frame soak and an exported executable startup check. Headless suites: integration 66, free_roam 137, wiring_05 18, map_interiors 97, map_06 150, city_detail 201, vehicle_art 52, vehicles_06 24, remote_player 71, chat_ui 46, net_lobby_ui 84; localhost host 67 + client 62. Integration initially failed because the user had saved third-person mode; the isolated rerun passed, with user settings preserved.

`tests/city_detail.gd` checks road clearance and real physical furniture collision, standing-capsule park crossings, both buildings' front-to-back corridors, and all five vehicles driving on a real test floor: two-second acceleration, reached speed caps and braking. Both runners include this suite. Linux: `bash tests/run_all.sh` (set GODOT first); Windows: `Run Tests.cmd` plus `tests/run_net_pair.ps1 -Steps 'lobby,round'`. The Windows launcher covers the core nine suites; the Linux runner also covers remote/UI/network tests.

Eight new GPU screenshots were captured; selected park, plaza, parking, diner and motel views were inspected. Recreate with Godot 4.4.1: `--path . --script res://tests/capture_map06.gd -- only=detail`. Captures go to ignored `work/captures/map06_detail_*.png`.

After distance culling, the local street performance sample is **82–121 FPS**, with approximately 841–2,043 draw calls. Midtown 1,746; north long view 2,043; Motor Mile 1,742; gun store 1,599; Exchange 1,693. The inherited ~1,550-call target is **still missed** in those views. Figures are one development PC, not a low-end hardware guarantee. Small props barely change downtown cost; optimize existing windows/material surfaces and visibility before filling every empty patch. No claim of public-release readiness.

## Recommended next pass, in order

1. Human playtest tomorrow: enter/exit diner, motel rooms, park crossings and parked cars; drive each vehicle; test honest and contested rounds with at least two friends. Check that deal approaches/escapes still work and that slower cars remain useful for the larger map. Record actual chase/deal outcomes before changing weapon or vehicle damage.
2. Bring high-cost views nearer the rendering target. Profile material/shadow batches, room visibility and window grouping. Preserve readable cover and openings. Do not add dynamic lights or a crowd before measuring.
3. Finish motel M2 around the existing lobby: exterior upper walkway, more rooms, two independent accessible routes and drained courtyard pool. Build on this source rather than restoring the old solid stub. Burger still needs drive-through lane/window and exterior trim. Hotel, garage, high-rise and both clubs remain earlier placeholders; they are good next interior tasks. Full upper-floor/lift work must include actual walking/riding tests and an agreed multiplayer state interface.
4. Add one distinctive, useful interior or public corner at a time: sight lines, cover that matches its visible geometry, at least two useful exits where possible, a plausible purpose, restrained signage. Avoid filling the city with interchangeable boxes.
5. Discuss (do not silently ship) deal/trust changes with the user. Reliable trade should be worthwhile; voluntary restitution could invite acceptance by the wronged team without deleting the history of betrayal. These are proposals needing design and abuse review, not implemented rules.

## Delivery and ownership

The user's usual executable in `outputs/play-fast-talkers/Fast Talkers.exe` is updated after verification. A pre-city-detail backup is kept alongside this chat's deliverables, separate from the earlier pre-map backup. The distributable `Fast Talkers Map Playtest.zip` is refreshed for friends. Claude should read this file and the newest CLAUDE_HANDOFF.md entry before touching code. Master remains unchanged; integration PR stays draft until the user has played the build.
