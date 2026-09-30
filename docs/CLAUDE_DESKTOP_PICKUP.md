# Claude Desktop pickup: overnight heavy lift

Paste the block below into Claude Desktop, opened in the user's Windows checkout of `fast-talkers`. It
recreates the overnight cloud session's lead and sub-agent split, so each workstream continues from where it stopped.
The cloud session could not run Windows, a GPU, real Steam, a microphone or real players. Those checks are the first job.

---

```text
You are the lead for Project Fast Talkers (Godot 4.4.1, GDScript): a round-based DEAL-MAKING game with guns in it
(not a shooter with deals). A match is a five-Day Week; crews win on banked money, never kills. Continue the cloud
session's overnight heavy lift.

GOAL FOR THIS SESSION (the user's words, 2026-09-30): multiplayer playtest TOMORROW EVENING with 2 or possibly more
players. Aim for AS MANY WORKING FEATURES FOR MULTIPLE PLAYERS as possible, and ship them as an easy .zip:
- Stability beats scope. Every feature in the zip must work over the network for 2+ players: joining, crews, the buy
  phase, driving, shooting, doors and lifts, voice (open-mic proximity plus crew radio), hands up, and the contract case.
- Deliver `Fast Talkers Playtest.zip`: the exported exe and pck, the GodotSteam DLLs, steam_appid.txt (480) beside the
  exe, and a one-page `HOW TO PLAY WITH FRIENDS.txt`:
  1. Install and run Steam, and log in.
  2. Unzip and run Fast Talkers.exe. Steam shows you as playing "Spacewar"; that is expected.
  3. Host: PLAY ONLINE, then HOST ON STEAM (INVITE FRIENDS), and pick friends in the Steam overlay.
  4. Friends: accept the Steam invite (or right-click the host in Steam, then Join Game).
  5. Use a headset. Talk normally (open mic); hold Y for crew radio.
  Also include a fallback section for direct IP / ENet if Steam misbehaves. Everyone must run the SAME zip.
- Order: (1) get Steam host, invite and join working on 2 PCs (sub-agent B); (2) run every suite and a 2-PC round;
  (3) build and smoke-test the zip; (4) only then add features, smallest and most multiplayer-visible first.
  Candidates: the one-trade-item plus phone inventory with independent drops, and the crew phone at HQ spawn. The Week
  structure is next if time allows. Nothing risky goes in the zip unless it is tested on 2 PCs.

MODELS: run the lead (you) on Opus 5.5 at high effort, and switch to the highest effort only for hard Steam, network or
merge debugging. Run sub-agents on Sonnet 5.5 (`model: "sonnet"`) for scoped work: captures and test runs, audio
tuning, props and dressing, docs, and the zip and walkthrough. Keep B (Steam/voice/net security) and any host-authority
code on Opus, or review it yourself before committing.

USER DECISIONS (binding; details in CLAUDE_HANDOFF.md "The user's decisions"):
- Carrying a trade item (briefcase, Project or cash) limits you to the SIDEARM until you drop it (G).
- BUILD ALL the trust systems in docs/DESIGN_WEEK_TRUST.md (W0 Week foundation first, then A-I in T0-T5 order) once
  the playtest zip is stable. Host-validated, tested, with the abuse counters as written.
- FRIDAY IS ALWAYS A BLOODBATH: the Dead Drop has no truce rules; trust only pays out on Friday.
- Comeback lifeline D defaults to the Loan Shark phone call (not a pawn shop); confirm with the user when building it.

SETUP (do these yourself, in order):
1. Preserve local Windows-only changes: run `git status`; commit or stash anything local before switching branches.
2. `git fetch origin` then `git checkout cloud/overnight-heavy-lift` (draft PR #2 targets cloud/map-integration).
   Never edit or merge master. Never export over the user's exe until local validation passes.
3. Read, in order: docs/GAME_VISION.md (what this game is: a round-based deal-making game, Week = match,
   Day = round; use its five-question design test on every feature), CLAUDE_HANDOFF.md (newest entry at the end: "Overnight heavy lift"), docs/CLAUDE_DESKTOP_PICKUP.md,
   docs/NETWORK_SECURITY_AND_STEAM.md, docs/VOICE_CHAT.md, docs/AUDIO_PASS.md, docs/OVERNIGHT_CITY_PERF.md,
   docs/VEHICLE_TIDY_HANDOFF.md ("Overnight pass"), docs/SUBROSA_NBD_RESEARCH.md.
4. Take over `Run Tests.cmd`: add the suites city_audit, building_landmarks, sfx_audio, social_features,
   net_security and voice (keep CRLF line endings), then run it plus `tests/run_net_pair.ps1 -Steps 'lobby,round'`.
   Record exact pass/fail counts. Fix real failures before anything else.

USER DIRECTION (binding):
- Performance target: 60+ fps on the user's RTX 3080. POTATO MODE (settings) serves minimum-spec PCs and must never
  remove anything with collision.
- Mood: "a world paused in time (late 1999), ripe for deals and deceptions". Original art/text only.
- Guns gritty and boomy, no childish beeps. Voice: open-mic proximity is the default and the intended way to play;
  push-to-talk for local is optional; the squad/crew key mutes the talker in proximity so only crew hear them.
  People inside a building can hear each other; passers-by outside cannot.
- Steam play with friends must be as simple as possible for the end user (host -> invite -> accept).
- No Boss: one crew phone sits in each HQ spawn and whoever grabs it makes the calls. Street payphones are
  DISTRACTIONS that stir unrest and pull crews across each other's paths, not a reliable tip or catch-up system.
- A match is a WEEK and a round is a DAY (Monday-Friday; Friday is always the Dead Drop). The Week structure does
  not exist in code yet: read the "Week and Day mindset" section of CLAUDE_HANDOFF.md and docs/DESIGN_WEEK_TRUST.md.
  Use Week/Day vocabulary in UI, code and tests.
- Deal/round rule changes (docs/DESIGN_WEEK_TRUST.md A-I, inspect-trade, anti-turtling, crew spectate, carrier cue)
  are proposals: present them to the user, then build the Week foundation (W0) and the approved items in order.
- No NPCs or traffic. Keep deterministic world generation (seeded _rng, stable parked_vehicles order) and the
  existing multiplayer APIs.

SUB-AGENTS: spawn these in parallel with the Agent tool. One owner per file: no two agents edit the same file.
Each agent must not commit; you review and commit per workstream. Tell each agent the others' file ownership so
they can message each other (SendMessage) instead of editing each other's files. Give each a deadline.

A. "windows-validation" (owns: nothing; read-only + running tests/captures): run every suite and
   tests/capture_perf.gd windowed on the RTX 3080 (vsync off) with and without POTATO MODE; run
   tests/capture_interiors.gd, tests/capture_cabins.gd, tests/capture_map06.gd -- only=detail; report fps and draw calls
   per view vs the software-GL numbers in docs/OVERNIGHT_CITY_PERF.md, and list visual problems with coordinates.
B. "steam-voice" (owns: scripts/net.gd, scripts/online.gd, scripts/lobby_ui.gd, scripts/steam_transport.gd,
   scripts/net_security.gd, scripts/voice*.gd, scripts/remote_player.gd, net/voice tests, the two docs):
   install GodotSteam for 4.4.1 per docs/NETWORK_SECURITY_AND_STEAM.md (steam_appid.txt = 480 next to project
   and exe), run the 2-PC Steam checklist with the user, fix create_host/create_client argument mismatches,
   then validate voice with real microphones: open mic, optional local PTT, squad key muting proximity,
   indoor/outdoor occlusion. Keep ENet working as the fallback.
C. "audio" (owns: scripts/sfx.gd, tests/sfx_audio.gd, docs/AUDIO_PASS.md): listen to work/audio/*.wav (regenerate
   with SFX_DUMP=1 ... tests/sfx_audio.gd), tune the gun profiles (drive/sub/grit, GUN_TRIM_DB) by ear with the user,
   then add surface-aware footsteps once a surface lookup exists (coordinate with D).
D. "gameplay-week" (owns: scripts/main.gd, scripts/player.gd, scripts/character_model.gd, tests/social_features.gd,
   tests/integration.gd, tests/free_roam.gd, NEW tests/week_flow.gd; coordinate online.gd changes with B):
   build the Week foundation (W0 in docs/DESIGN_WEEK_TRUST.md: host-owned week_state, weekday HUD, morning recap,
   CS gear carry-over, Friday Dead Drop, END OF WEEK standings, rejoin restores state), then the user-approved
   trust items in T0-T5 order. Include the inventory in docs/GAME_VISION.md: weapons unchanged, ONE trade item
   (briefcase / Project / cash bundle) and a separate crew-phone slot, each dropped independently (G = trade item,
   K = phone), server-owned objects with host-validated pickup, drop and hand-over (coordinate with B for sync);
   also wire remaining audio hooks and gamepad binds for hands-up/binoculars.
E. "city" (owns: scripts/world.gd, scripts/city_detail.gd, scripts/mesh_merge.gd, scripts/interiors.gd,
   scripts/retro_textures.gd, tests/city_detail.gd, tests/city_audit.gd, tests/map_06.gd, capture scripts for the city):
   fix the remaining city_audit REPORTs, the Strip ring vs beach rocks step at (24, 400), bus shelters, avenue
   planters, manholes and grates, CRT TVs in shop windows, sign text drawn into a texture if the signs cost too much, and use the GPU numbers from A to decide further draw-call work.
F. "landmarks" (owns: scripts/buildings/*, tests/building_landmarks.gd, tests/capture_interiors.gd):
   investigate the gun store roof not rendering (see CLAUDE_HANDOFF.md known issues), raise the lot props that
   sit 16 cm into plinths (use world.surface_height), then build the next pieces:
   hotel guest floors + lift/stair, motel drained pool (needs plot space, ask E), high-rise floors 3+ / roof.
   Every new floor needs walk/lift tests like building_landmarks.gd.
G. "vehicles" (owns: scripts/car.gd, scripts/vehicle_kit.gd, tests/vehicle_art.gd, tests/capture_cabins.gd):
   the leftovers in docs/VEHICLE_TIDY_HANDOFF.md (dash-top map, bike mirror stalks, kick panels) after A's GPU review.

FINISH: re-run everything, update CLAUDE_HANDOFF.md with exact results, push the branch, and let the user decide on
exporting and merging into cloud/map-integration (never master).
```

---

## Where each overnight workstream stopped

| Workstream | Last state on the branch | Next step |
|---|---|---|
| Landmarks | Club, strip club, hotel lobby floor, garage (drivable), high-rise (2 lifts, 2 stairs), motel upper floor, burger drive-through; `building_landmarks` 188/0 | Sunk lot props; hotel guest floors; motel pool; high-rise upper floors |
| City and performance | Draw calls about −30% (software GL); `city_audit` 69/0; potato mode; 1999 dressing; Coast Road rerouted round the gun store | GPU numbers; the Strip ring step; texture tiling |
| Vehicles | `vehicle_art` 110/0; footwell, seats, wheels, arches and z-fighting fixed | GPU cabin review; small leftovers |
| Audio | 110 procedural sounds; guns rebuilt; `sfx_audio` 321/0; nothing listened to yet | Listen and tune; surface footsteps |
| Network | Host-validated relays; handshake; rate limits; `net_security` 91/0; Steam transport written, untested | GodotSteam install and a 2-PC test |
| Voice | Open-mic proximity by default, optional push-to-talk on N, crew radio on Y (mutes proximity), building walls block passers-by; `voice` 87/0 including a real four-peer ENet run | Real-mic and 2-PC validation; jitter pre-buffer; echo; a mute-player menu; Steam voice API later |
| Interior props | Gun wall (72 display guns) and trade props in every business; potato-hidden; `building_landmarks` 204/0 | Gun-store palette material; the gun store roof rendering issue |
| Outdoor anti-slop 2 | Park rails that stop cars (44 runs, 5 parks), 98 street signs, texture variation; `city_detail` 217/0, `city_audit` 72/0 | Bus shelters, avenue planters, manholes; sign text into a texture |
| Gameplay | Hands up, binoculars, round report, potato toggle, audio hooks; `social_features` 29/0 | Gamepad binds; decisions on the proposals |
