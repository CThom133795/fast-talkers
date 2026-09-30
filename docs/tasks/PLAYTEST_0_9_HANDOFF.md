# 0.9 playtest: cloud handoff to Claude Desktop

Written by the Claude Cloud polish lead, 2026-09-30, for tonight's friends playtest. Every branch below is pushed, and
every PR targets `dev`. Pick up from here.

## Merge order (each branch contains the ones before it)

| # | PR / branch | What |
|---|---|---|
| 1 | PR 4 `lead/phone-voice` | Phone voice calls (§12); host voice routing about 17× faster; the parked-car keyframe fix |
| 2 | PR 5 `lead/stairs` | Halcyon Trust open-air railed terrace; closed stair undersides; rails; stair_walk now 95 checks |
| 3 | PR 6 `lead/street-props` | Nothing solid in any carriageway (whole-city `_road_sweep`); off-road corner and sightline props |
| 4 | `lead/crew-hq` | Walk-in crew compounds (see its PR for the state it was left in) |
| 5 | `cloud/playtest-polish` | Phase 2 polish; contains everything above plus `cloud/playtest-sfx` and `cloud/playtest-city` |

Merging in this order gives no conflicts. Each merge only fast-forwards the diff that is new to that branch.

## What friends will notice (Phase 2, `cloud/playtest-polish`)

- **Title:**
  - the first time the title opens, the camera cranes down from the Exchange roofline onto the four-crew lineup over 5.5 s;
  - a restrained Cm9 music sting plays (`sting_title`).
- **HOW THE WEEK WORKS:** a one-screen card beside the buy menu on the first Monday of a session. It covers Monday to Friday, winning on banked money only, the contract, the phone, the case, death and the Dead Drop. The keys shown match the device in use.
- **HUD action strip** (online, on foot), above the controls line and changing with context:
  - `[P] CALL A CREW` / `ANSWER` / `HANG UP` and `[K] DROP PHONE`;
  - `[G] DROP <case>` and `[X] HANDS UP`;
  - `[HOLD Y] CREW RADIO` and `[ENTER] CHAT` (keyboard only).

  It hides under the buy menu.
- **Phones:**
  - a DTMF blip per pick and on dial;
  - the caller hears ringback (2 s on, 4 s off);
  - `busy` plays on "Line busy.";
  - pick-up and hang-up clunks;
  - remote callers raise the handset to their ear during a live call. If they also carry a case, the phone stays on the belt.
  - A stolen crew phone gives its crew "YOUR CREW PHONE IS GONE: <CREW> has it." with a sound, and tells them when it comes back.
- **Juice:**
  - banking at HQ plays a safe thunk with a register "ching" (`bank`);
  - Friday's doors open with the Dead Drop sting and "FRIDAY. THE DEAD DROP.";
  - the morning paper rustles;
  - END OF WEEK is a *Halcyon Herald* late edition: a headline (for example "PHOTO FINISH…" or "BLOOD ON THE STREET, MONEY IN THE SAFE…"), then the crews ranked by banked money in big type, marked "← YOUR CREW".
- **City:** off-road yard and lot dressing (containers, trailer yards, pallets, skips, vans, billboard walls, bus shelters, a park hedge).
  - Open-ground sightlines are down 22%, and the longest is 477 m → 353 m.
  - The `city_fill` limits are tightened to hold that.

## Bugs found and fixed on the way

- Host car sync: parked cars could hang 0.5 m in the air on a client after the Day-start reset, because resting cars were never re-sent. The host now re-sends resting cars every 2 s. This also helps late joiners.
- `voice.gd`: a peer heard only by phone could count as "speaking" in the first 500 ms of the process, so the voice test flaked.
- `stair_walk` sampled the first building per kind even when it had no stair. After the street-props re-lot, the office walk silently dropped out.

## Windows checks before friends join (Claude Desktop or the user)

1. **A real mic on a phone call between two PCs:**
   - P dials, the other side rings in 3D, and P or picking the phone up answers;
   - the far side sounds thin (phone EQ) and comes from the phone;
   - someone 3 m from the far phone overhears it, someone 5 m away doesn't;
   - someone 2 m from your phone isn't picked up;
   - ringback, busy and hang-up sounds are audible and not too loud;
   - the remote caller's handset-to-ear pose looks right.
2. **A pad with Steam Input OFF for Spacewar 480:**
   - D-pad left dials, D-pad left and right pick, A dials and B cancels;
   - D-pad left at the HQ counter still opens the shop;
   - the rules card and action strip show pad glyphs.
   - The crew radio has **no pad binding** (every button is taken), so the strip omits it on pad. Decide whether to bind one.
3. **A two-PC Steam join:** host a Week, the friend joins, then check that parked cars sit on the road for the joiner.
4. `Run Tests.cmd`, then `powershell -File tests\run_net_pair.ps1 -Steps lobby,round,phone`.
5. Draw calls in the worst view (F3) with the new yard dressing and the HQs: 1,600 or fewer.
6. Bump `config/version` (the title still says PLAYTEST 0.8), then run `tools\build_playtest.ps1`.

## Not done (for the lead)

- **Robustness (Phase 2e):**
  - no rejoin / Week restore (Task 3 in `PLAYTEST_0_9_CLOUD.md`);
  - no door or phone snapshot for late joiners beyond the car keyframes;
  - no new join-failure text.
- Task 1 (Lantern Row and Kingsway enterable) was not started.
- HQ lights, signage and hero props (Phase 2d) depend on how far `lead/crew-hq` got. See its PR.
- A pad binding for the crew radio.
