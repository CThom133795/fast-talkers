# Map M1 integration — review status

The local cloud/map-m1 checkout was preserved and committed as 420f7e7, then pushed to CThom133795/fast-talkers. Claude's web sandbox could not reach those Windows files; Codex transferred them locally.

The original project remains the integration destination. A cloud/map-integration branch was created from master b6d4a06, then the map branch was merged without conflicts. All five newer multiplayer commits remain in the ancestry. Master and the existing exported build remain intact; no second project structure was created.

## Changes

- Moved Solana Heights 18 m east and 8 m south to keep its HQ out of the corner region, preserving >=300 m separation and fair 330–380 m routes.
- Widened East Shore Drive to 14 m for accepted gun-store frontage.
- Cleared the rear range-door aisle through the bullet trap, and kept storefront/window/partition openings clear in interior lining without duplicate glass panes.
- Applied world/armory modes through actual offline/online resets, title return and pause/resume. Practice targets stay hidden, inactive and without collision during matches. Ordinary shops still reopen; locked range doors stay closed.
- Corrected relocated LONG_LINE HUD/radar coordinates. Added a place-based welcome and an accurate locked-range prompt.
- Included map_06 in runners; added game-transition and two-peer regression checks. Windows network tests run hidden with explicit engine logs.
- Documented M1 versus unfinished M2, reference research and proposed-only trust/restitution ideas.

## Verification and limitations

Map acceptance 150/150. Wiring 18/18. Two-peer lobby/round: host 67/67, client 62/62. Offline gameplay, free roam, map/interiors, vehicle art, vehicle behavior, remote players, chat and lobby suites were exercised, plus a 6000-frame soak. The vehicle settings check initially failed under filesystem restrictions, then passed 24/24 with access to its temporary test file. See final playtest verification for the full counts.

Aerial and gun-store exterior/interior/mode captures were rendered and inspected. Trademark builders other than the gun store remain M1 placeholder shells.

The GPU performance target is NOT met: sampled Midtown 1744 draw calls, north long view 2044, Motor Mile 1694, gun store 1591, Exchange interior 1695, versus the planned approximately 1550 ceiling. Other street samples were 835–1320. Measured street frame rates on this machine were approximately 73–125 fps; this does not establish performance on other hardware. Keep the PR draft for performance and human playtest review.

Functional M2 lifts need interaction, authoritative progress and late-join synchronization. Real internet play, native voice, public matchmaking and Steam release remain separate work. Proposed deal incentives and apology/restitution systems were NOT implemented. The deliverable is a private playable map test.
