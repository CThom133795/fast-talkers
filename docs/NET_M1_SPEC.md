# Net M1 spec — first playable online round (0.6)

Owner: tech lead (Claude). This is the contract between the pieces built in parallel. If a piece needs to deviate,
report it; don't silently change an interface.

**Goal:** Caleb and a friend (2–8 players) join over LAN or the internet, pick crews, and play repeated rounds:
buy phase (30 s) → street phase (10:00) → results → next round. The round is one deal: a seller crew holds the
Ledger and a buyer crew holds a cash case. Players can trade them, steal them or crash the deal. **No bots online.**

## 1. Topology
- Godot high-level multiplayer, `ENetMultiplayerPeer`, default port **24650** (UDP), max 8 peers.
- **Listen server:** the host (peer id 1) also plays. `server_relay` stays on (default).
- UPnP port mapping is attempted on host start, in a `Thread`, and never blocks the UI. It is removed on shutdown.
  The result is shown in the lobby ("Port 24650 opened on router" / "Could not open port: forward UDP 24650 or use Tailscale").
- The main scene root is `FastTalkers` (`main.tscn`). The network node is its child named **`Net`**
  (`/root/FastTalkers/Net`), created in `main._ready()`. **All RPCs live on `Net`**, so node paths match on every peer.

## 2. Authority (demo trade-offs are marked DEMO)
| Thing | Authority | Notes |
|---|---|---|
| Own movement, look, crouch, weapon in hand | owning client | DEMO: client-auth, 20 Hz snapshots; receivers interpolate 100 ms behind |
| Hits on players | shooter detects → **host validates** → victim applies | host checks alive, phase, fire-rate cap, range ≤ 320 m, claimed point within 3 m of the host's latest victim position, damage ≤ weapon cap |
| Health, armor, death | victim applies damage sent by host and reports death | DEMO |
| Car simulation | peer in the driver seat; host when no driver | others treat the car as a puppet (physics off, interpolated) |
| Seats | **host** (one winner per request) | |
| Items (Ledger, cash case) | **host** | pickup/drop/bank are requests; host validates distance against its latest known position |
| Round phase and clock, roles, payouts, crew bank | **host** | |
| Wallet for buying gear | owning client | DEMO: the existing local buy menu; host grants payouts via RPC |
| Car glass breaks, shot FX | whoever caused it, broadcast | cosmetic |

## 3. `scripts/net.gd` — `class_name FastNet extends Node` (built by agent A)
**State**
- `const PORT: int = 24650`, `const MAX_PLAYERS: int = 8`
- `var players: Dictionary`: peer_id → `{"name": String, "crew": String, "ready": bool}`. Host-authoritative;
  mirrored on clients.
- `var local_name: String`
- `var upnp_status: String`
- `var in_match: bool`

**Methods**
- `host(port := PORT) -> Error`
- `join(address: String, port := PORT) -> Error`. `address` may include `:port`.
- `leave()`: close the peer, clear state, remove the UPnP mapping.
- `is_online() -> bool` (a peer exists and is connected, or we are hosting).
- `is_host() -> bool`
- `my_id() -> int`
- `request_crew(crew: String)`: client → host; the host applies it and broadcasts.
- `request_start()`: host only. It sets `in_match` and broadcasts `match_started`.
- `local_addresses() -> PackedStringArray`: the host's LAN IPv4 addresses to read out to the friend.

**Signals**
- `lobby_changed()`
- `connected()`, `connection_failed(reason: String)`
- `peer_joined(id: int)`, `peer_left(id: int)`
- `server_closed()`
- `match_started()`
- `upnp_done(status: String)`

**Game RPCs.** Agent A creates these as stubs that emit signals. The lead wires them into main.gd.
- Every `@rpc` must declare its mode explicitly. Snapshots use
  `@rpc("any_peer", "unreliable_ordered", "call_remote", 1)` on channel 1; everything else is reliable.
- Clients never call a `_host_*` handler directly. Wrap each call as `send_x(...)`: it `rpc_id(1, ...)`s, or calls
  locally when we are the host.
- Handlers check `multiplayer.get_remote_sender_id()` against the claimed actor.

| RPC | Direction | Args | Emits |
|---|---|---|---|
| `_state` | owner → all | `pos: Vector3, yaw: float, pitch: float, flags: int, weapon: String, car: int, seat: int, health: float` | `remote_state(id, dict)` |
| `_shot_fx` | shooter → all | `origin: Vector3, end: Vector3, weapon: String, quiet: bool` | `remote_shot(id, origin, end, weapon, quiet)` |
| `_host_claim_hit` | shooter → host | `victim: int, amount: float, head: bool, origin: Vector3, point: Vector3, weapon: String` | host: validated → `_apply_damage` rpc_id(victim) |
| `_apply_damage` | host → victim | `amount: float, source: Vector3, attacker: int` | `damage_received(amount, source, attacker)` |
| `_host_report_death` | victim → host | `killer: int, pos: Vector3` | host → `_player_died` to all |
| `_player_died` | host → all | `id: int, killer: int, pos: Vector3` | `player_died(id, killer, pos)` |
| `_host_request_seat` | client → host | `car: int, seat: int` | host → `_seat_update` to all |
| `_host_leave_seat` | client → host | `car: int, seat: int` | host → `_seat_update` |
| `_seat_update` | host → all | `car: int, seat: int, peer: int` (0 = empty) | `seat_update(car, seat, peer)` |
| `_car_state` | driver → all | `car: int, xform: Transform3D, vel: Vector3, steer: float, speed: float, flags: int` | `remote_car(car, dict)` |
| `_host_car_damage` | any → host | `car: int, amount: float` | host → `_car_health` |
| `_car_health` | host → all | `car: int, health: float, disabled: bool` | `car_health(car, health, disabled)` |
| `_glass` | any → all | `car: int, index: int` | `remote_glass(car, index)` |
| `_host_item_request` | client → host | `action: String` (pickup/drop/bank), `item: int, pos: Vector3` | host → `_item_update` |
| `_item_update` | host → all | `item: int, data: Dictionary` | `item_update(item, data)` |
| `_round_state` | host → all | `data: Dictionary` (phase, time_left, round, roles, bank) | `round_state(data)` |
| `_grant` | host → one | `amount: int, reason: String` | `grant(amount, reason)` |
| `_chat` | any → host → targets | `channel: String, text: String` | `chat(from_id, channel, text)` |

`flags` bits for `_state`:
- 1 crouch
- 2 aiming
- 4 dead
- 8 firing
- 16 carrying the Ledger
- 32 carrying the cash case
- 64 sprint

**Lobby UI (agent A: `scripts/lobby_ui.gd`, a `Control`).** A self-contained panel that main adds under its HUD
canvas and shows from the title menu:
- **Before connecting:** a player name field (saved to `user://net.cfg`), **HOST GAME**, and an address field
  (remembered) with **JOIN**.
- **In the lobby:** the player list with crews, and a crew picker (the four crews from `factions.gd`). Two players
  may share a crew. Host only: **START MATCH** (enabled at 1+ players; one player is allowed for solo testing).
  Also shows the host's LAN IPs, the UPnP status and a one-line Tailscale hint, plus **LEAVE**.
- Full pad navigation (focus), matching main's menu style: dark panel, gold/teal accents.
- Signals: `back_requested()`. Match start comes through `net.match_started`.

## 4. `scripts/remote_player.gd` — `class_name FastRemote extends CharacterBody3D` (agent B)
- **Body.**
  - `peer_id: int`, `crew: String`, `display_name: String`.
  - Built with a `CharacterModel` (`build(crew, true)`: the armed sidearm prop) and a name tag `Label3D` above
    the head, in crew colour, visible within 40 m.
- **Hitbox.** A capsule, radius 0.34, height 1.8, standing; `collision_layer = 4` (layer 3), `collision_mask = 0`.
  Local players and cars collide with layer 3 because the lead adds bit 4 to their masks.
  - `hit_zone(at: Vector3) -> String`: `"head"` if `at.y - global_position.y > 1.5` standing (> 1.0 seated),
    else `"body"`.
  - `take_damage(amount, source)` hits by cars or explosions; emits `struck(amount, source)` and never changes
    health locally. `apply_remote_health(health)` updates the value shown.
- **Interpolation.** `push_state(time: float, state: Dictionary)` buffers snapshots stamped with the local
  receive time. `_process` renders 100 ms behind using linear interpolation (lerp position, lerp_angle yaw).
  It extrapolates at most 150 ms, then holds, and snaps if the error is over 8 m.
- **Animation.** `CharacterModel.animate(delta, velocity_estimate, aiming)`, where velocity is estimated from
  the buffered positions. Crouch lowers the model and shortens the capsule. Pitch tilts the head/chest a little.
  - Dead: `set_dead(true)` plus a fall tween like `guard.gd`'s; collision off.
- **Seated.** `seat_in(car: Node3D, eye_local: Vector3, bike: bool)` parents the visuals to follow the car each
  frame, sets `model.seated` and `riding`, switches the capsule to seated (height 1.1) on
  `collision_layer = 8` (layer 4, rays only), and adds a collision exception with the car. `seat_out()` reverses it.
- **Weapon prop.** Long guns (`FastPlayer.is_primary(id)`) show a simple long-gun box prop on the right hand;
  otherwise the sidearm. It is visible only while aiming or firing (holster rule).
- `flash_hit()`: brief red tint, like `guard.gd`.
- No networking code inside: the lead feeds it data.

## 5. Two-process test harness (agent C)
- `tests/net_pair.gd`: an `extends SceneTree` script that reads `OS.get_cmdline_user_args()`:
  - `--role=host|client`
  - `--port=N`
  - `--script-steps=lobby` (later: `round`)

  It instantiates `main.tscn` and drives `game.net`.
  - **Host:** hosts, waits for the client, checks `players.size() == 2`, requests crews, starts the match, then
    waits for the `done` signal or a timeout.
  - **Client:** joins `127.0.0.1`, checks `connected`, requests a crew, and checks the mirrored lobby.
  - Each writes `NET PAIR <role> RESULT: n checks, m failures` and exits 0/1.
- `tests/run_net_pair.cmd` and a bash equivalent `tests/run_net_pair.sh`: start the host in the background and
  the client 1 s later. Each process uses `timeout`. The logs go to `work/net-host.log` and `work/net-client.log`,
  and the script prints both RESULT lines and exits non-zero if either failed.
- Design the step list so the lead can append round steps later (a `match` on the steps string).

## 6. main.gd integration (lead)
- Title gains **PLAY ONLINE**, which opens the lobby UI.
- `match_started` calls `_start_online_round()`: a variant of `_start_round()` with no guards, no tips, the host
  clock and the roles board.
- `FastRemote` nodes are spawned per peer under a `Remotes` node and fed from `remote_state`.
- `_on_shot` routes hits on a `FastRemote` to `net.send_claim_hit`, and broadcasts `_shot_fx`.
- Seats: when online, `_enter_vehicle` asks the host and enters on `seat_update`. The driver sends `_car_state`;
  non-owned cars get `net_puppet = true` (a new car.gd flag: skip physics and interpolate).
- Items: the Ledger and cash case are world nodes with ids 1 and 2. Their visuals follow the holder.

## 7. Round rules (lead; host code)
- **Roles.** The seller crew and the buyer crew are the first two distinct crews among the players, rotating
  every round. Any other crews are third parties. With one crew only (a solo test), it is both roles.
- **Spawns.** The Ledger spawns at the seller HQ's doorstep and the cash case ($6,000) at the buyer HQ's.
- **Banking.** An item is banked by carrying it within 4.5 m of your own HQ door and pressing interact.
  - Ledger banked by the buyer crew: buyer +$9,000.
  - Ledger banked by a third crew: that crew +$9,000.
  - Ledger banked by the seller: nothing; the round can still end.
  - Cash case banked by any crew other than the buyer: that crew +$6,000.
  - Clean-deal bonus: buyer banked the Ledger **and** the seller banked the cash **and** neither crew killed the
    other that round. Both crews get +$1,500.
- **Ending.** The round ends when both items are banked or the 10:00 clock runs out.
- **Settling.** 15 s of results, then the next round (the host keeps the clock running).
- **Death.** You drop what you carry at your body. You respawn at HQ after 10 s with the P9 (gear lost, CS rule).
- **Money.** Payouts go to every member of the crew (`_grant`), capped at $16,000 per player.

## 8. Security rules (every networked change must follow them)
- `SceneMultiplayer.allow_object_decoding = false`. Never use `bytes_to_var_with_objects`, `get_var(true)`, or
  load `.pck`, scripts or resources received over the network or from user-writable folders. This closes the
  classic "send an object, run code" vector.
- **Typed RPC parameters only.** Every handler sanitises its input:
  - finite floats only;
  - clamped string lengths;
  - ids range-checked;
  - enums (crew, weapon, channel) checked against a whitelist.
- **Sender identity.** Check `get_remote_sender_id()` in every handler. A peer can only speak for itself, and
  only the seated driver can move a car.
- **Rate limits.** The host rate-limits each peer and disconnects flooders.
- **The host decides outcomes.** Money, items, hits, seats and the clock. The DEMO shortcuts in §2 (client-side
  movement and wallet) are cheat risks, not code-execution risks. They must move to the host before any public
  matchmaking.
- **Release transport:** Steam Networking Sockets through GodotSteam. It is encrypted, relayed through Steam and
  hides players' IP addresses. For LAN or direct IP, use ENet with DTLS when we leave friend testing.
- Keep the engine on the latest 4.x patch release.
