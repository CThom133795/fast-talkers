# Network security and Steam play

Owner: networking. Files: `scripts/net.gd`, `scripts/net_security.gd`, `scripts/steam_transport.gd`,
`scripts/online.gd`, `scripts/lobby_ui.gd`, `tests/net_security.gd`.
Status: the security hardening is done and has headless tests. The Steam layer is written but has
**not been tested**: the cloud box has no Steam client and no GodotSteam, so nothing here has been
checked against real Steam. ENet is still the default transport and works exactly as before.

---

## 1. Threat model (listen server)

- The **host** is peer 1. It plays the game and is also the referee. It is trusted completely: a
  host who cheats can't be stopped in this model. For games with strangers, the fix is a dedicated
  server, which is out of scope.
- **Clients** are untrusted. A modified client can send any RPC with any arguments, at any rate,
  before or after the handshake. It can also try to pretend to be another peer.
- **Network**: plain ENet in Godot is **not encrypted**. Anyone on the path (same Wi-Fi, ISP) can
  read chat and positions, and with more effort could inject packets. Tailscale encrypts the tunnel.
  Steam Networking Sockets (the SDR relay) is encrypted and authenticated, and it hides IP addresses.
- **Identity**: `multiplayer.get_remote_sender_id()` is set by the transport, and with server relay
  **off** a client can only ever reach the host. Sender ids therefore can't be forged, and each
  handler checks that the sender owns whatever it acts on.

## 2. What was fixed (per RPC)

These protections apply to every client→host RPC:
- **Handshake gate** (`_joined`). Only `_host_hello` is accepted until the handshake finishes.
  Anything else sent earlier is dropped and earns a strike.
- **Shared token bucket** per peer (`BUDGET_BURST` 240 messages, refilling at `BUDGET_RATE` 150/s).
  This sits on top of the existing per-kind limits.
- **Strikes** (`NetSecurity.Strikes`). Malformed input, spoofing and impossible input each earn a
  strike. One strike decays every 5 s, and 10 strikes means a kick. The flood kick in `_rate_ok`
  (over 5x the limit for 2 s) still applies.
- `allow_object_decoding = false` (unchanged), and typed RPC parameters.

| RPC | Direction | Checks now |
|---|---|---|
| `_host_hello(name, version)` | client→host | Once per connection. Name cleaned to 24 printable chars with no brackets. **Build tag must match** (`"<PROTOCOL>|<config/version>"`, overridable via `net.build_tag`). On a mismatch the host sends `_hello_refused(reason)` and drops the peer 0.5 s later. A peer that sends no hello within **10 s** is dropped. A repeated hello earns a strike. |
| `_hello_refused(reason)` | host→client (authority) | New. The client leaves and emits `connection_failed("…same game build")`. |
| `_host_request_crew` | client→host | Gate. Crew must exist. Not allowed during a match. Rate-limited. |
| `_state` (snapshot) | client→host, host→all | Clients accept it only from the host. On the host: gate, 40/s, finite values, known weapon, car/seat range, yaw/pitch/flags/health clamped. **Map bounds** (±6 km, y −200…1500; the lead can narrow this with `net.map_half_extent`). **Speed cap**: at most 110 m/s × dt + 18 m slack. An impossible jump is dropped; 10 in a row → resync with a strike. Grace periods for respawn, new phase and match start. Then relayed as `_relay_state`. |
| `_relay_state` | host→client (authority) | New. Same field checks on the client. |
| `_car_state` | client→host, host→all | Gate, 40/s, car index, finite transform/vel, car inside map. **Only the seat-0 holder** may drive a car (the host may drive when nobody is in it). Relayed as `_relay_car`, which also checks the driver. |
| `_shot_fx` | client→host, host→all | Gate, 25/s, finite, known weapon, tracer ≤ 640 m. Relayed as `_relay_shot_fx`. |
| `_host_claim_hit` | client→host | Gate. Must be in the live phase (`accept_hits`). 50/s raw, 25/s accepted. Finite values, amount > 0. Victim ≠ shooter and both alive. Shot ≤ 320 m. Hit point within 3 m of the victim's last snapshot. **New:** the claimed weapon must be the one in the shooter's last snapshot. **New:** the shot origin must be within 30 m of the shooter's last snapshot. **New:** damage is capped per weapon (damage × pellets × headshot × 1.5, never above 250). **New:** optional `net.los_check` hook for line of sight. |
| `_apply_damage` | host→victim (authority) | Finite values, clamped. |
| `_host_report_death` | client→host | The sender is always the victim. 2 s dedupe. **New:** the killer is kept only if the host validated a hit from that killer on this victim in the last 15 s. Otherwise the killer is set to 0, so a client can't fake crew-vs-crew kills to wipe the clean-deal bonus. |
| `_host_request_seat` / `_host_leave_seat` | client→host | Gate, car/seat range. You can only leave a seat you hold (a spoofed leave earns a strike). online.gd checks the seat is free, the player is alive and within 7 m. |
| `_host_car_damage` | client→host | Gate, finite, > 0, capped at 1000. **New (online.gd):** the sender must be within 320 m of the car, and the match must be active. |
| `_glass` | client→host, host→all | Gate, car index, window 0…255. Relayed as `_relay_glass`. |
| `_host_item_request` | client→host | Gate. Action must be pickup/drop/bank. Item range. Finite position (bad input earns a strike). online.gd works from the **host's** copy of the player's position: pickup reach, only the holder may drop or bank, bank only at your own HQ. |
| `_world_event` (doors/lifts) | client→host, host→all | Gate, 10/s. Kind is door/lift, index 0…1023, value −1…255. Relayed as `_relay_world_event`. online.gd bounds the index by `world.interactable_doors.size()` at runtime (door counts change when buildings are added). |
| `_host_chat` | client→host | Gate. Channel ≤ 32 chars and valid. Text cleaned (control, bidi and zero-width characters removed; `[` `]` → `(` `)`, so no BBCode injection) and cut to 160. 3/s. Crew and call routing is done by the host. |
| `_sync_lobby`, `_match_*`, `_peer_gone`, `_player_died`, `_seat_update`, `_car_health`, `_item_update`, `_round_state`, `_grant`, `_chat` | host→clients (authority) | Godot rejects "authority" RPCs from anyone but peer 1. The clients still clean what they get: dictionaries ≤ 64 keys with string/int keys, names and chat cleaned, grants clamped. |

Other changes:
- **Server relay off**. Before, a client's `_state.rpc()` went straight to the other clients through
  the host's relay, **skipping every host check**. Now clients send to the host only, and the host
  re-broadcasts what it validated.
- **Oversized strings**. `clean_text` looks at no more than `max_len × 4` characters, so a 1 MB chat
  line costs the host almost nothing. Wire strings like weapon and channel have length caps.
- **ENet compression**: `COMPRESS_RANGE_CODER` on both ends. A build without it can't connect at all,
  which is fine because builds must match anyway.
- **Max players**: `create_server(port, 8)`, and the 9th peer is disconnected on connect (unchanged).
- **refuse_new_connections**: deliberately **not** set when the match starts, because online.gd
  supports late joiners. Late joiners still go through the handshake, and the cap still applies.

### What remains (known, not fixed)
1. **Client-authoritative movement and health.** Each peer moves itself, and the victim's own
   client applies damage. A hacked client can ignore damage (god mode) or speed-hack up to the
   110 m/s cap. A full fix is a server-side health ledger or server simulation, which is a design change.
2. **Hit claims come from the client** (the shooter says what it hit). The host checks range,
   position, weapon, rate and damage, but there is **no line-of-sight check** until the lead sets
   `net.los_check` (see hooks). Aimbots can't be stopped in this model.
3. **The host is trusted.**
4. **ENet traffic is unencrypted.** DTLS is not enabled (see §3). Use Steam or Tailscale over the internet.
5. Door and glass events are cosmetic-plus-cover. Any joined peer can toggle any door index (up to
   10/s). There is no distance check yet, because door positions live in world.gd.
6. The build tag doesn't include a world hash. If two builds share `config/version` but generate a
   different world, they would still connect. Bump `NetSecurity.PROTOCOL` or `config/version` on
   every release, or let the lead add a hash (hooks).

## 3. DTLS for ENet (not implemented, by choice)

Godot can encrypt ENet with `peer.host.dtls_server_setup(TLSOptions.server(key, cert))` on the host
and `peer.host.dtls_client_setup(hostname, TLSOptions.client(...))` on the client. The key and cert
can come from `Crypto.generate_rsa(2048)` + `Crypto.generate_self_signed_certificate(...)`.

Why it isn't turned on:
- With a self-signed cert, the client either has to skip verification
  (`TLSOptions.client_unsafe()`), which stops eavesdroppers but not man-in-the-middle attacks, or pin
  the host's cert. Pinning means the host has to share a fingerprint out of band. That is more
  friction than typing an IP, and Steam already provides encryption with no setup.
- `ENetMultiplayerPeer.create_client` connects right away. Whether a `dtls_client_setup` call made
  afterwards still wraps the handshake would need a two-process test, and it couldn't be done safely
  in this session.

If it's wanted later: add `var dtls := false` to net.gd. The host generates a key and cert once
(saved in `user://`) and shows the SHA-256 fingerprint. The client uses TOFU (trust on first use):
it stores the fingerprint per host address and refuses if it changes. Add a `--dtls` mode to
`tests/net_pair.gd`.

---

## 4. Steam play (Spacewar test app, App ID 480)

### Is it feasible?
Yes, this is the usual route for Godot 4. **GodotSteam** (GDExtension) provides the `Steam`
singleton. Its multiplayer peer, **`SteamMultiplayerPeer`**, is a `MultiplayerPeer` that runs over
Steam Networking Sockets. Steam lobbies handle invites. Valve's relay (SDR) handles NAT traversal,
so no port forwarding and no Tailscale are needed. Traffic is encrypted and players' IPs are hidden
from each other.

About **App ID 480 ("Spacewar")**:
- It is Valve's shared developer test app. It's fine for **private testing with friends**.
- **Every PC needs the Steam client running and logged in.** Friends see you "playing Spacewar".
- Lobbies are shared with every other developer testing on 480. Our lobbies are tagged
  `game=fast_talkers` and `build=<build tag>`, and joins check both (`check_lobby_data`). We only
  use friends-only lobbies and invites, never a public lobby browser.
- **Not for release.** A public release needs your own App ID (the Steam Direct fee, per title), a
  depot, and `steam_appid.txt` removed from the shipped build.

### How it's wired (scripts/steam_transport.gd + net.gd)
- Nothing names GodotSteam statically: `Engine.has_singleton("Steam")`,
  `ClassDB.class_exists("SteamMultiplayerPeer")`, `ClassDB.instantiate`, `.call()`, and signals
  connected by name. **The project parses and runs with no extension installed.**
- `net.steam_unavailable_reason()` returns "" or a plain reason: "Steam add-on not installed",
  "Steam not running", "Steam not logged in", "Steam needs an update".
- `net.host_steam()` initialises Steam with app 480 (and sets the `SteamAppId` env var). It creates
  a **friends-only** lobby, tags it, makes a `SteamMultiplayerPeer` and calls `create_host(0)`,
  attaches it through the same `_attach_peer` as ENet, and **opens the Steam invite overlay**
  (`activateGameOverlayInviteDialog`).
- A friend accepts the invite, or right-clicks the host in the Steam friends list and picks
  **Join Game**. Steam fires `join_requested`, and the game calls `net.join_steam(lobby_id)`. It joins
  the lobby, checks the tags, and calls `create_client(owner_steam_id, 0)`. online.gd opens the lobby
  screen by itself (`steam_join_started`). If the game wasn't running, Steam launches it with
  `+connect_lobby <id>`, and `net.steam_autostart()` (called from `online.setup`) joins that lobby.
- Once the peer is attached, **everything in §2 applies unchanged**: handshake, build check, rate
  limits, strikes, relay.
- Lobby UI: a **HOST ON STEAM (INVITE FRIENDS)** button appears only when Steam is usable. Otherwise
  there is one plain line, "Steam play unavailable: <reason>." While hosting on Steam, the lobby shows
  **INVITE STEAM FRIENDS** and hides the IP and port text. ENet **HOST GAME** / **JOIN** are unchanged.
- Version differences: `steamInitEx` is called with whichever signature the installed GodotSteam
  exposes (`(retrieve_stats, app_id, embed)` in older 4.x, `(app_id, embed)` in newer).
  `create_host` / `create_client` are called as `(0)` and `(steam_id, 0)`. **If the installed
  version's `SteamMultiplayerPeer` API differs, fix it in `steam_transport.gd` only**: the functions
  `_on_lobby_created` and `_on_lobby_joined`.

### How to play with friends on Steam (for players)
1. Open Steam and sign in, on every PC.
2. Start Fast Talkers and choose **Play Online**.
3. The host clicks **HOST ON STEAM**, and Steam's invite window pops up. Pick your friends.
4. Friends click **Accept** on the Steam invite. If the game isn't open yet, Steam starts it and
   drops them into the lobby.
5. Everyone picks a crew and the host clicks **START MATCH**.

If the button isn't there, the menu shows why (for example "Steam not running"). Plain HOST GAME /
JOIN still works.

### Developer install steps (Claude Desktop on Windows)
1. **Get GodotSteam for Godot 4.4.** Go to https://godotsteam.com or
   https://github.com/GodotSteam/GodotSteam/releases and pick the **GDExtension** release whose
   release notes list **Godot 4.4** compatibility. Check the notes rather than trusting a version
   number here. You need the **MultiplayerPeer** too: recent GDExtension releases bundle
   `SteamMultiplayerPeer`, but older ones ship it as a separate "GodotSteam MultiplayerPeer" download.
   The Godot Asset Library ("GodotSteam GDExtension 4.4") is the other route.
2. Unzip so the addon lands at `res://addons/godotsteam/` (the `.gdextension` file plus `win64/`
   DLLs, including `steam_api64.dll`). Open the project in the Godot 4.4.1 editor once so it imports
   the extension, then restart the editor.
3. Create **`steam_appid.txt`** containing only `480`. Put it in the project root (for editor runs)
   and **next to the exported exe** (for dev builds). Don't commit it to a release depot.
4. **Export**: the Windows export has to ship the extension's DLLs (`libgodotsteam*.dll` and
   `steam_api64.dll`) **next to the exe**. Godot copies GDExtension libraries on export when the
   `.gdextension` lists them. Check that the export folder contains them.
5. Check it: start Steam, run the game, open Play Online. The **HOST ON STEAM** button should show.
   Look in the console for `[steam] init failed: …` if it doesn't.
6. Suggested: add `addons/godotsteam/` binaries and `steam_appid.txt` to `.gitignore`, or commit
   them on purpose, but that's the lead's call.

### Manual 2-PC test checklist (needs two Steam accounts that are friends)
- [ ] Both PCs: Steam running and logged in, and the same build (same `config/version`).
- [ ] PC A: Play Online shows **HOST ON STEAM**. Click it; the invite overlay opens and the lobby
      screen says "You are hosting on Steam."
- [ ] PC A: invite B. PC B (game running): accept, and it lands in the lobby. Both player lists show 2.
- [ ] PC B with the game closed: accept an invite, and Steam launches the game straight into the lobby
      (`+connect_lobby`).
- [ ] PC B: right-click A in the friends list > **Join Game** works the same way.
- [ ] Crew change, START MATCH, driving, shooting, a kill and a respawn, chat on all channels. The
      numbers should look like ENet.
- [ ] Different builds: bump `config/version` on one PC. The join should fail with "different version
      of the game" (lobby tag) or the handshake refusal.
- [ ] Close Steam on PC A mid-match. PC B gets "The host closed the match".
- [ ] No Steam or no add-on: the button is hidden, the reason line shows, and ENet HOST/JOIN still work.

## 5. Tests
- `tests/net_security.gd` (headless, `NET SECURITY RESULT: N checks, M failures`) covers two layers.
  Pure validators: text and BBCode, 1 MB strings, NaN/INF, map and speed bounds, weapon damage caps,
  dict caps, token bucket, strikes, the Steam lobby filter. Host handlers: handshake and version,
  hello timeout, spoofed seat release, snapshot / car / fx / world-event fields, teleport resync and
  respawn grace, hit claims (weapon, origin, line-of-sight hook, phase), death attribution, budget
  flood, strike kick, and Steam reporting "add-on not installed" with the button hidden.
  It also runs a **real-socket end-to-end section**: one process, four ENet peers on 127.0.0.1, each
  FastNet under its own `SceneMultiplayer`. It checks the mismatched build is refused with a
  message, two good clients join, Bob receives Alice's snapshot relayed by the host under Alice's id,
  an out-of-map snapshot is not relayed, and a peer that skips the hello and spams is kicked.
- `bash tests/run_net_pair.sh [port] lobby,round` still passes: the two-process round with seats,
  driving, a lethal hit and a respawn at HQ, now through the host relay and the speed checks.
- State flag 128 = hands-up gesture (online.gd sends it, remote_player.gd shows it).

## 6. Lead hooks needed
1. **tests/run_all.sh**: add `net_security` to `ALL` (e.g. after `net_lobby_ui`). It's a normal
   headless suite: `NET SECURITY RESULT: N checks, M failures`.
2. **Line of sight for hit claims** (main.gd, after `online.setup`):
   `net.los_check = func(a: Vector3, b: Vector3) -> bool: var q := PhysicsRayQueryParameters3D.create(a, b); q.collision_mask = <world-only mask>; return get_world_3d().direct_space_state.intersect_ray(q).is_empty()`
   Use a mask that excludes players and cars, and test that it doesn't reject real hits through
   glass or thin props before shipping.
3. **Map bounds**: after the world is built, `net.map_half_extent = <half the city's extent + margin>`.
4. **World hash** (optional): `net.build_tag += "|" + str(<world seed or count of doors/cars/items>)`,
   so builds that generate a different world can't join each other.
5. **project.godot**: no change is needed for ENet. For Steam, GodotSteam's `.gdextension` is picked up
   from `res://addons/godotsteam/` on its own; no autoload is required, because
   `steam_transport.gd` runs `Steam.run_callbacks()` itself.
6. `docs/CLOUD.md`: new `class_name NetSecurity`. Tests preload the file, so no re-import is needed,
   but `--headless --import` refreshes the class cache.
