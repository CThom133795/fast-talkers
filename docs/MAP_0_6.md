# Port Halcyon 0.6 — expanded city, M1

M1 expands the existing procedural city; it retains the original game controller and current multiplayer build. No new project or imported assets are introduced.

The mainland and waterfront cover approximately 850 x 778 metres including map padding. Nine additional districts connect the established neighborhoods: Uptown, Motor Mile, Nightlife, West End, Old Town, Slip Side, Old Wharf, East Shore and South Docks. An arterial ring gives drivers alternate approaches around Midtown. The practice wheelman retains the downtown loop.

## Crew routes

Measured over the seeded street graph to the Exchange at (0, -42):

| Crew | HQ doorstep x/z | Route |
|---|---|---|
| Kojimoto893 | -313, -40 | 370.5 m |
| Cartel Sol Negro | 318, -141 | 373.2 m |
| Kingsway Royals | 252, 152 | 360.9 m |
| Morris Mafia | -99, 219 | 359.5 m |

Route spread is 3.8%. Every HQ pair is at least 300 m apart; none meets the corner-placement definition in the acceptance tests. Every new district has at least two connected road entries. World generation keeps seed 31071999, fixed plot build order and deterministic car/door records.

## Businesses and range

Eight reserved plots use builders under `scripts/buildings`: high-rise, hotel, garage, motel, nightclub, strip club, burger restaurant and gun store. **The first seven are M1 placeholder shells.** Their full interiors, walkable stairs and working synchronized lifts are M2. Shared construction and lift helpers are foundations, not a claim that those buildings are finished.

Halcyon Arms is an accessible gun shop on East Shore Drive, with customer parking, an indoor range and an outdoor yard. Free roam spawns at its firing line and provides all practice targets. Contract and online modes retain the shop but lock its range doors/gate and hide, disable and remove collision from practice targets and range dressing. Actual game resets apply these restrictions. Ordinary shop doors still reopen and windows restore between rounds. Rear bullet-trap geometry leaves a clear aisle to the yard door.

`ArmoryScript.SPAWN`, `RACK` and `LONG_LINE` contain the relocated world positions. HUD/radar use the complete `LONG_LINE` vector. World and armory both expose `set_mode("free_roam" | "contract" | "online")`; the controller selects the mode on resets and when returning to the title.

## Experience direction

The intended nostalgia comes from shared play, not copying the appearance of another game. Keep neighborhood identities and landmarks consistent so players acquire their own local knowledge. Fair travel distances, alternative streets, readable doors and reliable collision should support improvised meetings, escapes and betrayals that friends remember afterward. Players choose where to meet; no prescribed meeting zone is painted into the city.

This pass preserves match rules and art direction. It adds a place-based free-roam welcome and a truthful locked-range prompt. It does not add retention rewards, daily chores or bots to real matches. Social playtests should judge whether people understand the deal, can recover from setbacks, discover useful routes, and want another round. Online voice, public matchmaking and a Steam launch remain separate work.

## Verification

Run `tests/map_06.gd` for geometry, plots, routes, range modes and deterministic builds. `tests/wiring_05.gd` checks actual game transitions and reset restrictions. Two-process `net_pair` with `lobby,round` checks online gameplay and confirms that both peers close the practice range. The full suite runner includes map_06.

GPU street/city captures and performance review complement headless checks. Real internet play remains a user playtest, and functional M2 lifts need host-owned progress, interaction and late-join synchronization before shipping.
