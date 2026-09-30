# Project Fast Talkers

**Offline playable prototype 0.4.** An original crime and negotiation shooter set in Port Halcyon.

History:
- 0.1 (Codex): the handling lab and round loop.
- 0.2 (Claude): Free Roam, the armory range and procedural audio.
- 0.3 (Claude): the city, crews, attachments and controller support.
- 0.4 (Claude), the user's brief:
  - an island city that is no longer a square;
  - 13 weapons (M4 and KV-47 rifles and more);
  - five vehicle types with gunner seats and drive-bys;
  - a real pre-round buy phase;
  - controller support in menus;
  - grounded, less cartoonish characters;
  - street tips;
  - the renamed Morris Mafia and Kojimoto893.

This is not the finished multiplayer game.

## Play now

Open the sibling `play-fast-talkers` folder and double-click **Fast Talkers.exe**.
- No engine installation or account is required.
- Windows x64, with OpenGL 3.3-capable graphics.
- For editing, use **Open in Godot.cmd** in this folder. The portable Godot 4.4.1 editor is in this task's
  `work/tools/godot` folder, so keep the current directory layout.

### Free Roam: armory, range and motor pool (demo mode)

No clock and no wallet. You spawn at the armory firing line carrying one weapon of each class, with unlimited
reserve ammo.

**Weapons**
- **1–5** pick a class: pistol, SMG, rifle, shotgun, marksman.
- **Press the same number again** to swap in the next model: P9 → .45 M1911 → .357 revolver, M4 → KV-47, and
  so on.
- **B** at the rack opens the gunsmith. Its **Arsenal** page lists all 13 weapons.

**The range**
- A plate rack at 8 m (timed), dummies with damage numbers at 12 m, and a moving plate.
- A long-range lane on the street south of the yard.

**Vehicles**
- The motor pool on the main road has a bike, a coupe, an SUV and a pickup. More are parked all over the city.
- **E** drives. **F** rides as a gunner.
- Ride as a gunner in an empty vehicle and a practice wheelman drives you round the ring road so you can
  shoot from the window.

**Practice bots**
- Exchange security is neutral until provoked.

### Contract / round mode

1. **Buy phase (25 s) at your crew's HQ.** The doors are locked and your weapon is holstered.
   - Press **B** (D-pad right) for the buy menu. Tabs cover pistols, SMGs, rifles, shotguns, marksman, gear and
     mods; LB/RB or 1–5 switch tabs.
   - You carry one primary and one sidearm. Anything bought this round sells back at full price until the
     doors open.
   - **READY** leaves early.
2. **Street.** Drive to the Exchange in Midtown (amber). Pay $800 or take the case by force, then bring it home
   to your HQ (teal).
3. **Street tip.** Sometime in the round a payphone nearby rings (blue on the radar).
   - Answering reveals a stash at a neutral spot, with 75 s to grab it.
   - Bank it at your HQ for $900. Die with it and it's gone.
4. **Next round.** If you survive, your weapons, attachments and armour carry over (CS rules). If you die, you
   start again with the free P9. A failed contract pays a capped recovery allowance.

## Controls

| Input | On foot | Driving | As a gunner (passenger, pickup bed, pillion) |
|---|---|---|---|
| WASD / left stick | Move | Throttle, brake/reverse, steer | — |
| Mouse / right stick | Look | Orbit the chase camera | Aim within your seat's arc |
| LMB / RT | Fire | Throttle (pad) | Fire |
| RMB / LT | Aim down sights | **Hold to lean out and shoot** (pad: hold **LB**, fire **RB**) | Aim |
| 1–5, wheel, Q | Weapon class, cycle, last weapon | — | Same |
| R / X | Reload | — | Reload |
| E / Y | Interact, enter as driver, deliver, answer a payphone | Exit below 8 km/h | Exit (asks a practice wheelman to pull over) |
| F / D-pad right | Ride as a gunner | Change seat | Change seat |
| B / D-pad right | Buy menu (buy phase), gunsmith (free roam) | — | — |
| Space / A | Jump | Handbrake | — |
| Shift / L3, Ctrl or C / B | Sprint, crouch | Horn (L3), H on keyboard | — |
| M / View, Esc / Menu | Map, pause | Same | Same |

- **Pad in menus:** D-pad or left stick to move, **A** to select, **B** to go back.
- **Weapons in the saddle:** from a driver's seat or on a motorcycle, only one-handed guns work (pistols,
  MAC-11, sawn-off).
- **Saved settings:** volume, mouse and pad sensitivity, invert Y, vibration, FOV, fullscreen, shadows,
  lighting, film grade, FPS counter and crew.

## What exists

- **Port Halcyon.**
  - Four crew islands linked to the neutral core by two bridges each, with capes round each HQ.
  - Harbor basins and a moored freighter.
  - Halcyon Beach with Ocean Drive, a pier and a Ferris wheel.
  - The canal, the rail yard and the ferry pier.
- **Crews.** Morris Mafia (Morris Park, SW), Kingsway Royals (Kingsway, SE), Cártel Sol Negro (Solana Heights,
  NE) and Kojimoto893 (Lantern Row, NW). Rules are identical; identity only.
- **Characters.** Procedural skinned humans on a 17-bone skeleton with realistic proportions, a painted face,
  crew garments, hats and an armband, animated by springs (walk, strafe, aim, sit and ride, flinch, fall).
- **Weapons.** 13, each with its own model, sound and handling, sight-aligned irons, and per-weapon
  attachments (optic, muzzle, underbarrel, magazine).
- **Vehicles.**
  - Sedan, coupe, SUV, pickup and motorcycle, each with seats, doors and fire arcs.
  - Window gunners, bed gunners and a pillion gunner; drive-bys.
  - Windows roll down; the hull is open at the windows.
  - Vehicles take damage and wreck; a hard crash throws you off a bike.
- **Buy phase.** A CS-style live buy phase with sell-back and carry-over; street tips; controller support in
  play and in menus; radar and a full map.

## Deliberate prototype limits

- **Not built:** multiplayer, proximity voice, player-to-player trades and Steam services.
- **Practice-only AI.** Exchange security and the free-roam wheelman are the only AI, and match builds will
  have none.
- **Security** holds a post rather than pathing.
- **Vehicles** are kinematic handling models with cosmetic suspension.
- **Characters** are procedural, not authored art. The next visual step is sculpted and motion-captured
  characters (see `docs/MULTIPLAYER_DESIGN.md` §13).
- **Numbers** for recoil, damage and prices are first-pass.
- **Hardware:** minimum specs are not validated.

## Develop together

- **Agent coordination** lives in two files at this folder's root: **CLAUDE_HANDOFF.md** (Codex → Claude) and
  **CODEX_HANDOFF.md** (Claude → Codex). Read both before editing, and append to your own file rather than
  editing the other agent's.
- **Match targets:** typical multiplayer is **12 players in 3 companies of 4**; large is **24 in 4 companies
  of 6**.

**Tests and captures.**
- **Run Tests.cmd** runs Codex's contract integration suite, the free roam / vehicles / buy-phase suite, and a
  chaos soak.
- The windowed capture scripts (`tests/capture_*.gd`) save review screenshots to `work/captures`:
  - `capture_guns` for all 13 weapons at hip and ADS;
  - `capture_vehicles` for the lineup and gunner views;
  - `capture_city` for every district and the map;
  - `capture_characters` and `capture_rig`.

**Docs.**
- `docs/MULTIPLAYER_DESIGN.md`: the game design.
- `docs/LOOP_ANALYSIS.md`: the Sub Rosa and No Big Deal research and our loop.
- `docs/PLAYTEST_CHECKLIST.md`.

## Sources informing the foundation

- [Godot Windows downloads](https://godotengine.org/download/windows/) and
  [4.4 system requirements](https://docs.godotengine.org/en/4.4/about/system_requirements.html).
  The Compatibility renderer was chosen for the low-end target; actual hardware support needs profiling.
- [Godot high-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html).
  The future network architecture must validate authority, transactions and inputs on the server.
- [Steamworks application documentation](https://partner.steamgames.com/doc/store/application).
  Steam integration and submission remain future milestones.

All game meshes, textures and sounds are original procedural content. No reference-game assets or source were
imported. Godot engine and third-party component notices accompany the executable.
