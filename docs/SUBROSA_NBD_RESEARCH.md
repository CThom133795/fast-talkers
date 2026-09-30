# Sub Rosa and No Big Deal: second research pass and gap list

Overnight pass, 2026-09-30. This complements `LOOP_ANALYSIS.md`, `REFERENCE_RESEARCH.md` and `MULTIPLAYER_DESIGN.md` and does not repeat them. Everything here is a reading of public descriptions and community pages. No assets, names, text or code from either game were used. Every Fast Talkers feature named below is an original implementation.

**What I could and could not read.**
- This pass used web search results only.
- Direct fetches of the Steam store page and the No Big Deal Fandom wiki were blocked by the research sandbox's network proxy.
- The claims below come from the search-result summaries of these sources:
  - the Steam store page and Steam community discussions,
  - the Cryptic Sea development blog and a Toribash community guide,
  - the Game Developer interview with Alex Austin,
  - the No Big Deal Roblox page and the Miraheze/Fandom/Namu wiki pages.
- Treat details as leads to verify in play, not as specifications.

## 1. What the sources add

**Sub Rosa (Cryptic Sea, Steam).**
- **Round end is physical.** Items (cash, disks) must be carried into the safe room in your base, and the round ends when every item is in a safe. The objective is always a thing someone is holding.
- **The briefcase is a tool, not a menu.** With an open case equipped, number keys move individual inventory items into or out of it, and left-click opens or closes it. Contents are only proven at the handover.
- **Mission shapes:**
  - Transaction: two teams broker a deal and the third team tries to kill them.
  - Three-way: all three teams hold something to trade, and one team can take both items by force.
- **Communication:** each corporation has one shared phone for calling other corporations, plus local voice.

What players love:
- The "right server": negotiated deals, betrayals and car chases.
- World-mode role-play groups.

What players complain about:
- Rounds collapse into clumsy first-person deathmatch when people won't or can't communicate.
- Griefing and spawn killing on the few active servers.
- Glitchy voice chat and input lag.
- Very few servers, and no updates for years.

**No Big Deal (Roblox).**
- **Round structure:** a five-round work week, with a team-selection phase, a negotiation/purchase phase in HQ (phones live, buy gear), a day phase with the mission, and a closing phase.
- **Spectating:** players can choose to spectate during team selection. Spectating players outside your team is restricted until your whole team is dead. So death leads to watching your own crew, not to scouting enemies.
- **Negotiation happens by phone** during the negotiation phase. The game encourages role-play and warns that newcomers find it confusing.
- **Mission terminals:** the sources mention negotiation terminals that must be worked while exposed. This is a "stand still to finish, risk getting shot" beat.

## 2. How Fast Talkers compares (from the design docs and `main.gd`)

Already built:
- A buy phase with locked HQ doors.
- Physical Ledger and cash cases with pickup, drop and bank.
- Crews with armbands and car colours.
- Chat channels for crew calls.
- A clean-deal bonus and no kill bounty.
- Street tips from ringing payphones.
- Vehicles with gunner seats.
- Round results with carry-over.

Planned but not built:
- Inspectable and counterfeit contents.
- A handshake trade.
- Portable phones.
- Weapon discipline: "guns are holstered in HQs and during handshakes … people can read intent before shots are fired" (`MULTIPLAYER_DESIGN.md` §5).

The references' biggest recurring failure is **deathmatch when intent can't be read**. Both games lean on voice to fix it. Fast Talkers has no native voice yet, so non-verbal, readable intent is the cheapest high-value lever.

## 3. Prioritised gap list

| # | Gap | Value | Size | Status |
|---|---|---|---|---|
| 1 | **Readable non-verbal peace signal.** Without voice, there is no way to say "don't shoot, I'm here to talk". | High: attacks the main complaint of both references | Small (one sync bit) | **Built this pass: hands up (X)** |
| 2 | **Scouting a meeting before committing.** Both games are about approaching a meeting under uncertainty; today, looking is the same as aiming a gun. | High | Small, local only | **Built: binoculars (hold Z)** |
| 3 | **Round-end clarity.** Players should know what happened: time, shots, hits, whether the documents moved. | Medium | Small | **Built: round report line** |
| 4 | Spectate your own crew after death (No Big Deal style: own team only, until the whole team is dead). | Medium to high online | Medium: camera plus online state; needs the net owner | Proposed |
| 5 | Case-carrier clarity: HUD and world cues for who carries the Ledger or cash. Shows your own crew's carrier; enemies see only a physical case in hand. | Medium | Small to medium: the flags already carry LEDGER/CASH bits | Proposed (next pass) |
| 6 | More gestures (wave, point, "follow me") on a small radial menu. | Medium | Small each, one sync field | Proposed; hands up is the template |
| 7 | Inspect-then-accept handover of cases (the design's handshake trade and inspection). | High, but touches deal and trust rules | Large | **For the user to decide** (excluded from this pass) |
| 8 | Portable crew phone as a carried, droppable item. | High | Medium to large, needs net | Planned in the design; not touched |
| 9 | Flashlight for dusk and interiors. | Low to medium | Small, but should replicate as a visible beam | Proposed |
| 10 | Anti-turtling timer (No Big Deal speeds the clock when most players hide in spawn). | Medium | Small | Round rule change: **for the user to decide** |

Explicitly out of scope, per the user:
- NPCs and traffic
- voice chat and matchmaking
- economy, reputation, apology or restitution systems
- new deal-incentive or trust rules

Items 7 and 10 stay proposals.

## 4. What shipped this pass

- **Hands up (X, toggle).**
  - The weapon is put away and firing, aiming and reloading are blocked. Other players see both arms raised and the sidearm hidden (`CharacterModel.hands_up`).
  - This makes the signal *credible*: you really are disarmed while showing it, and lowering the hands is visible before you can shoot.
  - The hands drop automatically on death or respawn. Hands up is not available while driving.
  - Replication: one bit (128) in the existing state flags, added by the network owner in `online.gd` and `remote_player.gd`.
- **Binoculars (hold Z).**
  - A 16° view, with mouse sensitivity scaled to the zoom. The weapon is lowered and cannot fire while they are up. Not available at the wheel.
  - Local only: others simply see you not aiming.
- **Round report.** The contract result screen adds one line: time on the clock, shots, hits, and whether the documents were delivered, lost or not moved.
- **Settings: POTATO MODE (low-end PCs).** Calls `world.set_potato_mode(enabled)` and is saved as `video/potato_mode`.
- **Audio hooks** from `AUDIO_PASS.md`:
  - Guard shots are distance-aware (`play_shot_at`).
  - Indoor/outdoor reverb comes from building footprints that declare `interior_half`.
  - Occasional distant dog or siren, from a local seeded RNG (audio only).
  - A slide rack after a pistol reload, and a holster sound when switching.
  - Car door open/close and engine start, cash riffle and bundle, briefcase open, payphone pickup and hang-up.

## 5. Proposals left for the user

1. **Spectate own crew on death.** Before building it, decide: free camera, or follow crewmates only, and whether spectators see the crew's map markers.
2. **Carrier cues.** Should enemies ever see who carries the Ledger beyond the physical case in hand? The recommendation is no: only your own crew gets a HUD marker.
3. **Gesture set.** Hands up is in. Should wave, point and follow come next, on a radial menu? The rule would be that any gesture that disarms you must really disarm you.
4. **Handshake/inspection trade** (design §5): the biggest remaining gap to the references, but it is a deal-rule change.
5. **Anti-turtling clock.** No Big Deal-style clock acceleration when most players sit in HQ late in a round.

## Sources

- [Sub Rosa on Steam](https://store.steampowered.com/app/272230/Sub_Rosa/). Search summary only; a direct fetch was blocked.
- [Steam discussions: "If you're thinking of buying sub rosa, read this"](https://steamcommunity.com/app/272230/discussions/0/3816291531980828198/) and ["Is this game worth it?"](https://steamcommunity.com/app/272230/discussions/0/3111416678598102146/)
- [Creating the "right" kind of player in Sub Rosa (Game Developer)](https://www.gamedeveloper.com/design/creating-the-right-kind-of-player-in-the-weird-fps-i-sub-rosa-i-)
- [Cryptic Sea blog: Sub Rosa 0.05](https://crypticsea.blogspot.com/2012/06/sub-rosa-005.html) and the [Toribash community guide](https://forum.toribash.com/showthread.php?t=464497)
- [No Big Deal on Roblox](https://www.roblox.com/games/18112334178/No-Big-Deal)
- [No Big Deal gameplay (Miraheze)](https://nobigdealunofficial.miraheze.org/wiki/Gameplay), [No Big Deal Wiki (Fandom)](https://no-big-deal.fandom.com/wiki/Gameplay) and [NamuWiki](https://en.namu.wiki/w/No%20Big%20Deal)
