# Project Fast Talkers

**A round-based deal-making game with guns in it.** Crews meet in a frozen-in-1999 harbour city to buy, sell, bluff,
rob and renegotiate. A match is a **Week**; each round is a **Day**, Monday to Friday. Friday is always the Dead
Drop. Crews win on banked money, never kills. Godot 4.4.1, GDScript, all art and sound procedural.

**Current build: 0.7 (playtest).** Online play for 2+ players over Steam (the Spacewar test app) or direct IP, with
proximity voice and crew radio, the Week, crew phones and one trade item per player.

## Start here

| You are | Read |
|---|---|
| Anyone, first | `docs/GAME_VISION.md` (what the game is, and the user's binding decisions) |
| Designing | `docs/LEAD_DESIGN_DECISIONS.md` (how we improve on No Big Deal and Sub Rosa), `docs/DESIGN_WEEK_TRUST.md` (the trust systems, in build order) |
| Committing anything | `docs/WORKFLOW.md` (branches: PRs go to `dev`; `master` moves only when the user merges), `docs/AGENT_BRIEF.md` (file map, conventions) |
| Claude Cloud | `docs/CLOUD.md` |
| Resuming a session | the newest entries at the end of `CLAUDE_HANDOFF.md` and `CODEX_HANDOFF.md` |
| Networking or Steam | `docs/NETWORK_SECURITY_AND_STEAM.md`, `docs/VOICE_CHAT.md` |

## Play

- **With friends:** build the zip with `powershell -ExecutionPolicy Bypass -File tools\build_playtest.ps1`, and send
  `..\Fast Talkers Playtest.zip`. The steps for players are in `tools/playtest/HOW TO PLAY WITH FRIENDS.txt`. In
  short: Steam running, then PLAY ONLINE, then HOST ON STEAM, and friends accept the invite with the game already
  open.
- **Alone:**
  - **SOLO WEEK** on the title screen runs the real Week on one PC.
  - **FREE ROAM** is the armory, the range and every vehicle.
  - **CONTRACT** is the offline practice round with bots.
- **Editing:** `Open in Godot.cmd`. The portable Godot 4.4.1 lives in `..\..\work\tools\godot`, so keep the folder
  layout.

## Tests

- **Windows:** `Run Tests.cmd` runs 19 headless suites, then
  `powershell -ExecutionPolicy Bypass -File tests\run_net_pair.ps1 -Steps lobby,round` runs a two-process online round.
- **Linux or cloud:** `bash tests/run_all.sh`.
- Every suite must stay green. The Week has its own suite: `tests/week_flow.gd`.

## Layout

- `scripts/`: the game.
  - `main.gd`: the offline game, the HUD and input.
  - `online.gd`: the host-validated Week, items and phones.
  - `net.gd`: transport, security and relays.
  - `steam_transport.gd`, and `voice*.gd`.
  - `world.gd` and `city_detail.gd`: the city; `buildings/`: the landmark interiors.
  - `car.gd` and `vehicle_kit.gd`: vehicles; `sfx.gd`: procedural sound.
- `tests/`: headless suites (`extends SceneTree`, exit 0 on pass) and windowed capture scripts.
- `addons/godotsteam/`: the GodotSteam 4.22.1 GDExtension (win64 and linux64). `steam_appid.txt` is 480 (Spacewar),
  for development only.
- `docs/`: design, research, handoffs and captures. `docs/.gdignore` keeps the images out of the Godot import.

All meshes, textures and sounds are original procedural content. No reference-game assets, names or code are used.
Godot and GodotSteam licence notices ship with the executable.
