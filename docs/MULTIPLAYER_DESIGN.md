# Fast Talkers — Multiplayer Design

Version 2 · 2026-09-29 · Claude. Status tags: **[BUILT]** exists in the offline prototype,
**[PARTIAL]** exists offline but needs network authority, **[PLANNED]** not built.
Nothing tagged PLANNED works yet. The shipped build is an offline single-player prototype.

**Changes in version 2 (prototype 0.4, with 0.5 work in progress).**
- Crews renamed: **Morris Mafia** (was Famiglia Varano) and **Kojimoto893** (was Aogiri-kai).
- Rounds open with a CS-style **buy phase** at your HQ, and survivors keep their gear.
- **13 weapons**, five **vehicle types** with gunner seats, and **street tips**. The 0.5 map pass
  reduces canals, removes the corner-island layout and adds Midtown interiors.
- Grounded character art is the target; the procedural models still need a larger asset pass.

The research behind these changes is in `docs/LOOP_ANALYSIS.md`.

---

## 0. One-paragraph pitch

Four crews run Port Halcyon, a sodium-lit late-90s harbour city: the Morris Mafia, the Kingsway Royals
(street gang), Cártel Sol Negro and Kojimoto893 (yakuza).
Each round they compete to broker or steal a contract item: a ledger, cash, or a courier package. Every
other character in a match is a real player. Trading fairly is usually worth more than shooting, but
betrayal is always possible. The game rewards reading people, clean gunplay and good driving. It does not
reward exploiting physics or randomness.

## 1. Pillars

1. **Multiplayer only. No AI in a real match.** Every other person in the city is a player. No NPC guards,
   couriers, pedestrians or traffic (details in §9).
2. **Skill and interaction beat jank.** Outcomes come from decisions, aim, driving and talking. They should
   not come from ragdolls, random damage rolls or fumbling fiddly controls.
3. **Readable intent.** You can tell a drawn gun from a holstered one, a crew from its silhouette and
   colour, and a fair trade from a stick-up before the first shot.
4. **Every death costs something; no kill pays.** Violence is a tool with a price, never a scoreboard.
5. **Tension through trust tools.** Deception must be possible, and skilled players must be able to detect it.
6. **Striking sixth-generation look.** It should be recognisable in one screenshot and clearly different
   from Sub Rosa and No Big Deal.

## 2. Reference teardown

Sources: [Sub Rosa on Steam](https://store.steampowered.com/app/272230/Sub_Rosa/),
[Cryptic Sea Sub Rosa page](http://www.crypticsea.com/subrosa/),
[Game Developer interview on Sub Rosa's design](https://www.gamedeveloper.com/design/creating-the-right-kind-of-player-in-the-weird-fps-i-sub-rosa-i-),
[Sub Rosa RDM discussion](https://steamcommunity.com/app/272230/discussions/0/1488866813759583939/),
[No Big Deal wiki: Gameplay](https://nobigdealrblx.miraheze.org/wiki/Gameplay),
[Weapons](https://nobigdealrblx.miraheze.org/wiki/Weapons), [Items](https://nobigdealrblx.miraheze.org/wiki/Items),
[Companies](https://nobigdealrblx.miraheze.org/wiki/Companies), [Controls](https://nobigdealrblx.miraheze.org/wiki/Controls),
[Map & Landmarks](https://nobigdealrblx.miraheze.org/wiki/Map_%26_Landmarks),
[GTA III gangs](https://www.gtabase.com/gta-3/gangs/), [GTA SA gang warfare](https://gta.fandom.com/wiki/Gang_Warfare_in_GTA_San_Andreas).

| Area | Sub Rosa | No Big Deal (Roblox) | Fast Talkers answer |
|---|---|---|---|
| Teams | 3 corporations (more in World Mode) | 3 companies × up to 5; 2 more teased | 4 crews; 12 players = 3 crews × 4, 24 = 4 × 6 |
| Round shape | World, Round (5-day week), Eliminator modes | 5-round week; phases 1:00 / 2:00 / 10:00 / 0:30 | 5-round week, 4 phases (§4), shorter planning |
| Objectives | Disks; Acquisition uses an **AI-driven car** | Project disks, dead drops, transactions | Player-only contracts (§4); a player replaces the AI courier |
| Communication | 80s phones with numbers, voice (PTT/open) | Company phone, voice recommended | Proximity voice, crew radio, switchboard phones, quick-chat wheel |
| Deception | Fake-filled briefcases; opening reveals contents | $10 counterfeit stacks | Counterfeits kept, **with learnable tells and verification tools** |
| Trade execution | Drop items, hope | Drop items, hope | Optional atomic **handshake** plus neutral **escrow** (§5) |
| Death deterrent | Lose 10% net worth on death | Carried money lost; spawn money worth half | Drop carried items plus 10% personal cash; no kill reward; **Street Rep** |
| Gunplay | Receiver-style manual reloads, bleeding, momentum | Bullets leave the barrel not the crosshair; damage ±15% random | Crosshair-true hitscan, deterministic damage, learnable recoil |
| Movement | Heavy momentum, crashes through windows | Lean, "stumble", ragdoll to avoid fall damage | Grounded and responsive: lean and crouch, no ragdoll escapes |
| Vehicles | Cars, a train | 5-seat company cars, flip-car key | Weighty but predictable sedans; no flip exploits needed |
| Griefing | Persistent RDM complaints; "absolute freedom" servers | Anti-turtling timer; exploit-heavy strategies | Systemic deterrents (§7) plus server tools |
| Input | KB/M | KB/M, no rebinding | Full rebinding **and full controller support** (§12) **[BUILT: pad]** |
| Look | Flat-shaded, untextured, grey city | Roblox engine look | PS2/GC/Xbox-era textures, dusk and neon, crew colour blocking (§13) |

**What they get right:** a phone call before a meeting creates stories; the briefcase is a great object of
suspicion; a week-long round arc gives comebacks; NBD's map clusters mission sites in neutral areas
between HQs; NBD's anti-turtling timer.

**Where they drift into jank:** fumbling Receiver-style handling and bleeding make fights random, not
skilful. Random damage and barrel-origin bullets make aim unreliable. Ragdoll and physics escapes turn
tension into slapstick. The AI courier car is a target nobody negotiates with. Deception has no counterplay
beyond "always shoot first", which feeds random deathmatch.

**A player guide as a loop check.** In [SimpleBusiness's No Big Deal beginner guide](https://www.youtube.com/watch?v=ORed1pRNQO0),
the described sequence is: learn whether your crew has cash or the project, call another crew, choose a
meeting place, inspect or bluff with portable cash and a case, then bring the project home to bank it
(0:34–2:16, 4:46–5:37). The guide also describes diversion calls, third-party alliances and hiding the
project (6:03–8:27). These are the memorable decisions: **who to trust, where to meet, how much to show,
who covers the exits, and when to leave**. The map should provide named landmarks without forcing a deal
at any of them; phones and items should make the bluff visible and contestable.

The same guide calls counterfeit bills visually obvious (1:27–1:53) and warns that its crosshair, moving
fire and body-part damage can mislead players (3:51–4:45). Fast Talkers should use a reliable aim ray,
deterministic damage and understandable movement penalties. A counterfeit should have a learnable tell
that takes close inspection, so it creates a real risk decision rather than a novelty that only fools new
players. Its item example that pays **both** crews after delivery (5:38–6:03) suggests a useful original
contract pattern: the best offer can leave both sides richer, while an ambush may forfeit that shared
bonus. This is a design inference from the creator's account, not a claim that those systems are built.

## 3. Crews (factions)

All four crews play by **identical rules**: same weapons, prices and movement. They differ in identity
and in where their HQ sits, not in power. Names are original; the archetypes follow crime fiction.

| Crew | Archetype | Crew colour | Silhouette cue | Wardrobe | District |
|---|---|---|---|---|---|
| **Morris Mafia** | Mafia | Crimson `#C4283F` | Fedora | Charcoal suit, cream shirt, crimson tie | Morris Park |
| **Kingsway Royals** | Street gang | Teal `#19C2B8` | Ball cap | Teal tracksuit, white sneakers, chain | Kingsway (SE) |
| **Cártel Sol Negro** | Cartel | Gold `#E8A21A` | Cowboy hat | Ivory linen shirt, gold chain, dark denim, boots | Solana Heights (NE) |
| **Kojimoto893** | Yakuza | Violet `#8E5CF0` | Swept pompadour | Black suit, loud violet print shirt, shades | Lantern Row |

- Colours sit about 90° apart on the hue wheel. Hat silhouettes differ, so crews read even for
  colour-blind players. Every character wears a crew-colour **armband** visible from all sides. **[BUILT offline]**
- Standard 12-player matches draw three crews by lobby vote or rotation. 24-player matches use all four.
- Crew identity also appears in car paint, HUD accent, HQ architecture and district neon. **[BUILT offline]**

## 4. Match structure

**The Week:** five rounds, Monday to Friday. Money carries over between rounds. **Equipment follows CS rules:**
- If you walk away alive, your weapons, attachments and armour carry into the next round.
- If you die, you start the next round with the free P9 pistol.

Friday is always a Dead Drop.

**Buy phase [BUILT offline]:**
- Every round opens with a **30 s** buy period at the crew HQ, in practice and in matches.
- During it you can look around, walk the HQ yard and take phone calls; weapons stay holstered.
- The buy menu (B / D-pad left) has tabs: pistols, SMGs, rifles, shotguns, marksman, gear, mods. LB/RB or
  1–5 switch tabs on a pad.
- You carry one primary and one sidearm. Buying another gun for a slot sells this round's purchase back, or
  leaves a carried gun in the HQ locker.
- Anything bought this round can be sold back at full price until the doors open.
- The HQ supply counter stays open during the street phase. Players can return and buy equipment if they
  have cash, but **nothing can be refunded after the 30 s buy period**. Leaving a gun in the locker or
  replacing an attachment never credits cash mid-round. A live purchase requires physical presence at the
  counter; the server validates the distance, phase and cash.

| Phase | Time | What happens |
|---|---|---|
| Lineup | 0:30 | Crews spawn in their HQ safe room; contract briefing; Boss role assigned |
| Buy phase | 0:30 | Buy guns, attachments, armour, tools; phones are live; HQ doors locked **[BUILT offline]** |
| Street | 9:00 | Doors open; deals, ambushes, chases |
| Settle | 0:20 | Items in HQ safes are banked; results shown; no damage |

- **Anti-turtling:** if at least 60% of living players are inside HQs after 6:00, the clock runs double speed
  (adapted from NBD).
- **Roles:** a crew may designate a **Boss** to coordinate calls and spending, but every member can propose,
  accept and complete a deal. The phone is a physical item; the Boss does not have exclusive access to
  escrow or to a meeting. If the phone carrier dies, the device drops and another player can take it.

**Contracts** (all player-driven, assigned per round):

**Meetings can happen anywhere.** The mission points create reasons to move, but they never prescribe a
meeting site. Players choose a café, apartment, street corner, moving car, rooftop or an improvised neutral
spot and can change it during a phone call. No deal action, trade, price or clean-deal bonus depends on
standing in an official zone. Even the Union Exchange is just one possible place to meet.

1. **Transaction.** A seller crew holds the Ledger; a buyer crew holds cash. The third crew profits by
   intercepting either side or by brokering a better offer.
2. **Dead Drop.** The Ledger spawns at one of the neutral mission sites (§8), revealed to all crews at
   2:00. Race, fight, or strike deals over it.
3. **Double Ledger.** Two sellers hold rival Ledgers and one buyer can afford only one. Undercutting and
   verification matter most here.
4. **Courier.** This replaces Sub Rosa's AI car. One crew must drive a marked package car from a pickup
   point to a destination. The others can intercept, or sell the courier protection by escorting it.

Payouts reward completion: sale price, delivery bonus, and a small **clean deal** bonus when both sides of a
trade finish alive. There is no kill reward anywhere.

**Street tips ("the line") [BUILT offline, one-crew version PLANNED]:**
- During the street phase, street payphones ring. A tip goes to one crew and marks a stash, a hot car or a
  drop at a neutral landmark, with a deadline.
- The crew can race for it, sell the information to another crew by phone, or use it as bait. Information
  becomes currency, and every crew always has a reason to be on the street.
- Offline: a nearby payphone rings 35–80 s into the round. Answering reveals a stash with 75 s to grab it.
  Banking it at your HQ pays $900; dying with it loses it.

## 5. Deal system (the core)

**Items [PARTIAL]:** The offline prototype has one visible contract case and the street-tip stash.
Physical cash stacks, counterfeit stacks, portable briefcases and phones below are **PLANNED** for the
multiplayer slice.

Reference details: [Sub Rosa's own instructions](https://crypticsea.com/subrosa/) describe cash blocks,
openable briefcases that hold inventory, and company cellphones for cross-team calls. In an
[interview with developer Alex Austin](https://www.gamedeveloper.com/design/creating-the-right-kind-of-player-in-the-weird-fps-i-sub-rosa-i-),
he describes empty cases and large bills covering smaller bills as readable deception.
The [No Big Deal item catalogue](https://no-big-deal.fandom.com/wiki/Items) lists company phones,
briefcases and worthless counterfeit stacks sold as a fraud tool. These are mechanical references;
Fast Talkers uses its own items, visual language and values.

| Fast Talkers item | Why a player carries it | Verification and counterplay |
|---|---|---|
| Ledger case | Holds the round's physical objective | Open and inspect its seal and unique document ID; a decoy can match the outside silhouette |
| Cash bundle | Physical consideration for a deal | Count/inspect banded denominations, or accept an offered amount on trust |
| Counterfeit bundle | Sell an apparent payout that banks for $0 | Different serial run and printing; a close inspection or UV pen exposes it |
| Empty or decoy case | Bluff about possessing the Ledger, split an escort, or bait an ambush | Weight/sound is a weak tell; opening the latches is conclusive but leaves hands occupied |
| Portable phone | Call a crew contact privately before or during a meeting | The device can be dropped, stolen or traded; possession never grants a map-wide position reveal |
| Crew radio | Coordinate with your own team while moving | Push-to-talk, with an audible local transmit cue; no enemy team channel by default |

Every cash bundle and case is a server-owned world object with a persistent ID and contents. The server
validates every insert, removal, drop, handover and deposit. Buyers can request to see a case open, inspect
bundles individually, or walk away; a seller may refuse. No modal UI forces both sides into a trade.

**Trust tools [PLANNED]:**
- **Inspect (free):** hold interact on a stack for 1.5 s. Counterfeits have visual tells, such as a wrong
  band colour or serial repeats, that a careful player can learn. Inspecting leaves you exposed, which is
  the skill trade-off.
- **UV penlight ($300 item):** confirms authenticity instantly, but it occupies your hand.
- **Optional handshake trade:** two players who are close enough can both confirm a specific pair of
  items, **at any location**. The server swaps the items atomically if both still own them and remain in
  range. Drawing a weapon, breaking range or changing contents cancels it. Players can also exchange by
  physically dropping items, accepting the added risk. No designated deal zones exist.
- **Optional remote escrow:** a phone-mediated offer can hold a named item and an agreed amount until both
  parties confirm or a short deadline expires. The exchange can settle wherever the parties stand; a small
  fee buys certainty, but neither the Union Exchange nor any other building is required. It conveys no
  invulnerability or forced peace.
- **Receipts and Street Rep:** every completed or broken deal is logged on the public board. A crew that
  kills a trading partner within 10 s of a handshake, or pays with counterfeits, gets a *Welsh* mark for
  the Week. Marks raise that crew's escrow fees and show next to its name when it phones others.
  Betraying is legal, but it has a reputation cost.
- **Weapon discipline:** guns are holstered in HQs and during handshakes. Drawing takes 0.35 s, is audible
  and is visible on your character. People can read intent before shots are fired.

## 6. Combat and movement

- Hitscan from the camera with spread cone. Crosshair and impact agree. **[BUILT]**
- Damage is deterministic: no random rolls. Zones: head ×1.5–2.5 by weapon, torso ×1, limbs ×0.75.
  **[BUILT head/body]**
- Recoil climbs predictably and recovers when you stop firing. Hip fire has a spread cone and bloom; aiming
  down sights tightens it. **[BUILT]**
- Weapons: 13 across five classes, each with its own model, sound, handling and attachment list **[BUILT]**.
  Names are original; the "pattern" column is the real-world archetype.

| Class | Weapon | Pattern | Identity |
|---|---|---|---|
| Pistol | P9 Service (free) | 9 mm service pistol | 12 rounds, quick follow-ups |
| Pistol | .45 M1911 ($350) | .45 single-stack | 8 heavy rounds: 3 to the body, 2 to the head |
| Pistol | .357 Revolver ($650) | magnum revolver | 2 to the body or 1 to the head; slow |
| SMG | VK-5 ($1,000) | roller-delayed 9 mm | accurate and controllable |
| SMG | MAC-11 ($800) | open-bolt machine pistol | 1,200 rpm, one-handed, useless past 20 m |
| SMG | Chicago Typewriter ($1,400) | drum-fed .45 | 50-round drum, heavy, slow reload |
| Rifle | M4 Carbine ($1,600) | 5.56 mm carbine | low, predictable recoil; two headshots |
| Rifle | KV-47 ($1,500) | Kalashnikov-pattern | **one unarmoured headshot kills**; kicks and wanders |
| Shotgun | 870 Pump ($1,100) | pump action | 9 pellets, shell-by-shell reload |
| Shotgun | Sawn-off ($700) | cut-down double | two barrels, one-handed, break-action reload |
| Shotgun | Auto-12 ($1,500) | semi-automatic 12 ga | 7 shells as fast as you pull |
| Marksman | M700 ($2,200) | bolt-action | scoped; one-shot head at any range |
| Marksman | BR-58 ($1,900) | battle rifle | semi-auto, 20 rounds, one-shot head |

- **One-handed** weapons (pistols, MAC-11, sawn-off) are the only ones usable from a driver's seat or a
  motorcycle saddle **[BUILT]**.
- **Attachments [BUILT offline]:** four slots, and every option has a trade-off (§6.1). Attachments are
  visible on the gun, which gives opponents information.
- Movement: walk, sprint (stamina), crouch, low jump. Planned: lean (Q/E), vaulting low cover,
  and a single-button dismount from cars. No ragdoll escapes and no bleeding slow-down. Health plus armour,
  with no regeneration in matches. **[BUILT except lean/vault]**

### 6.1 Attachment system [BUILT offline]

Each weapon lists the parts it takes (`mods` in `player.gd`). The sawn-off takes none, the revolver takes a
reflex sight, a laser and a speed loader, and so on.

| Slot | Option | Effect | Cost (match) | Fits |
|---|---|---|---|---|
| Optic | Reflex sight | Red-dot sight picture, −2° ADS FOV | $300 | Pistol, SMG, carbine, shotgun |
| Optic | 2× Holo | 2× zoom, ADS 15% slower | $450 | SMG, carbine |
| Optic | 4× Scope | Scoped view, ADS 30% slower | $600 | Carbine (marksman has it by default) |
| Muzzle | Suppressor | Quieter, no muzzle flash, hidden tracer; falloff starts 20% sooner | $500 | Pistol, SMG, carbine, marksman |
| Muzzle | Compensator | Vertical recoil −25%; louder and brighter | $300 | Pistol, SMG, carbine |
| Muzzle | Choke | Pellet spread −35% | $250 | Shotgun |
| Underbarrel | Foregrip | Horizontal recoil −40%, hip spread −15%, ADS 5% slower | $250 | SMG, carbine, shotgun |
| Underbarrel | Laser | Hip spread −30%; beam and dot visible to everyone | $300 | Pistol, SMG, carbine, shotgun |
| Magazine | Extended | +50% capacity, reload 15% slower | $300 | Pistol, SMG, carbine, marksman |
| Magazine | Speed | Reload 25% faster | $350 | Pistol, SMG, carbine, shotgun, marksman |

The laser and suppressor are deliberate *interaction* attachments: one gives your position away, the other
hides it.

### 6.2 Vehicles and gunner seats [BUILT offline]

| Type | Seats | Character |
|---|---|---|
| Sedan | driver + 3 | the baseline (Codex's tuned handling) |
| Coupe | driver + 1 | fastest car, fragile |
| SUV | driver + 3 | slow, tall, the toughest |
| Pickup | 2 in the cab + 2 kneeling in the bed | bed gunners fire all round, exposed |
| Motorcycle | rider + pillion | quickest; a hard crash throws you off |

- **Seats:** every seat has a door and an eye point. The camera can turn 360° and look up and down from
  every seat, including the driver. Bodywork and people block shots physically; the pillion can look toward
  the rider but cannot fire through them.
- **Drive-bys:** the driver uses the same 360° interior camera while driving. Holding aim (RMB / LB) raises
  a one-handed gun and LMB / RB fires, so the triggers keep driving. The driver can inspect the cab and
  look through any window; the roof, pillars and lower body block shots. Simulated glass penetration and
  breakage are still planned.
- **Controls:** E / Y takes the driver's seat. F / D-pad right rides as a gunner, or changes seat.
- **Hull:** the collision hull is open at the windows, so gunners can shoot out and be shot. The doors are
  cover. A gunner's window rolls down.
- **Damage:** bullets and crashes wear a vehicle down until the engine dies. It still gives cover but will
  not drive.
- **Practice wheelman (offline free roam only):** ride as a gunner in an empty vehicle and a practice bot
  drives a loop, so solo players can test passenger fire. This is an AI and is never in matches (§9).

## 7. Deterrents to random killing (systems, not rules)

1. Death drops everything carried and 10% of personal cash as a pickup. Your crew then has to decide whether
   to recover it.
2. No kill money, ever.
3. HQ safe rooms: no weapons can be drawn inside, spawn protection lasts 5 s after leaving the door, and HQ
   doors cannot be camped because they open onto private courtyards.
4. **Heat:** killing an unarmed player who is not carrying an objective raises your personal Heat. High Heat
   makes you glow on everyone's minimap for 60 s. Anyone can hunt you, and it costs your crew Street Rep.
5. Friendly fire is on for grenades later, but off for bullets by default (server option).
6. Server tools: vote-kick, host kick/ban, per-player mute, report log with the last 60 s of events.

## 8. Port Halcyon (the city) **[0.5 redesign in progress]**

The 0.4 build has a harbour city with four corner islands and a west canal. That map is playable, but the
user found the repeated channels, four corner HQs and two-bridge exits too restrictive. The next map pass
keeps the coast and harbour as a physical identity while joining most districts by continuous land.

- **Shape and routes.** The coast can be asymmetrical. The streets should respond to docks, older blocks,
  slopes and plazas, with some gentle curves and offset intersections. Keep several broadly even routes
  from each HQ to Midtown; measure travel time by both car and foot. Avoid a strict full-length grid.
- **Crew placement.** Morris Mafia, Kojimoto893, Kingsway Royals and Sol Negro operate from distinct
  neighborhoods around the city, **not four isolated corners**. HQs can face commercial streets and have
  multiple entries. A district is a social identity and set of landmarks, not a sealed map cell.
- **Open public ground.** Plazas, forecourts, market squares, park edges and broad junctions let people
  gather, spot approaching vehicles and negotiate in public. They do not grant immunity or formal deal
  status. A tight alley, interior or rooftop is equally valid for a meeting.
- **Water.** Concentrate it at the coast, harbour and perhaps one short canal with a clear reason for
  being there. Do not wrap every neighborhood in a channel or force every route over a bridge.
- **Midtown interiors.** A substantial majority of signed businesses get useful ground-floor interiors.
  The room, props and layout should match the exterior sign. Doors, windows and walls should support
  believable sight and sound behavior and player-selected meetings. Background buildings may stay shut.
- **Collision.** A visible parapet stops a low shot. A standing player should be able to shoot over it;
  a thin rail should not have a tall invisible bullet-blocking box. Test it from both sides.
- **Shared geometry.** Road and land data drive both the world and radar/full map; the map should show
  genuine routes and the doors of major enterable buildings.

The 0.4 world still contains its old four-corner layout until the delegated `world.gd` pass is integrated
and verified. The target above defines the 0.5 map, not a feature already shipped.

## 9. The no-AI rule

- "AI" means any agent that makes decisions: NPC guards, couriers, pedestrians, traffic.
  **None of these exist in a match build.**
- Deterministic scripted movers are allowed if we want them: timetabled trains, doors, lifts. They make no
  decisions. *(Needs your confirmation.)*
- What replaces AI: player couriers, dead drops, and player-staffed deals.
- The offline build keeps **practice bots** only in Practice modes (Free Roam range, Contract Drill).
  They are labelled as practice bots. They are excluded from the server build by an export feature tag
  (`server` builds strip `guard.gd`) and disabled whenever a network session exists. **[PLANNED: tag]**

## 10. Network architecture

**Authority:** a dedicated or listen server simulates everything that matters: movement results, hits,
health, money, purchases, inventory, item ownership, car seats and physics, round clock, trades.
Clients send inputs and requests, never outcomes.

**Transport:**
- M1 development: Godot `ENetMultiplayerPeer` over LAN or IP, with a headless dedicated server export.
- Release: Steam Networking Sockets via GodotSteam (relay, NAT traversal, Steam lobbies and invites).
  A transport shim keeps game code the same on both.

**Rates:** server simulation at 60 Hz (the physics tick already used). Snapshots at 30 Hz, reduced to
15 Hz for far entities through relevancy. Client input at 60 Hz, sent in 30 Hz packets carrying the last
three input frames for redundancy.

**Player movement:**
- Client-side prediction of the local player using the same `FastPlayer` physics code.
- Server reconciliation by input sequence number.
- Remote players are interpolated about 100 ms behind (2 snapshots plus a jitter buffer).

**Shooting:** the client sends the shot command (sequence, weapon, origin, direction, client tick).
The server rewinds hitboxes to that tick (at most 200 ms), re-traces, and applies damage. The client shows
predicted muzzle flash, tracer and sound immediately. Hit markers wait for server confirmation, which is
within an RTT, as in most competitive shooters.

**Vehicles:** the server owns them. The driver's client predicts its own car with the same kinematic model
(`car.gd` is deterministic apart from input) and reconciles. Passengers and others interpolate. Seat
requests go through the server and exactly one requester wins.

**Transactions:**
- Reliable ordered channel. Every request carries a client request id and the server de-duplicates.
- The server validates range, line of sight, phase, funds and ownership, then either replies with an event
  or rejects with a reason.
- Purchases, pickups, drops, handshakes, escrow and banking all use this path. This gives the "no duplicate
  cash" guarantee the prototype tests already enforce offline.

**Voice:**
- Steam Voice (or Opus over ENet for LAN).
- Proximity voice is spatial, about 30 m in unobstructed air. The server decides who receives each talker,
  based on distance and the current room/door/window topology, then the client places and filters the voice.
- Rooms inside one building form an acoustic group. People in the same room hear clearly; across an interior
  wall they hear a lower, muffled voice if a door or hall connects the rooms. A person outdoors does **not**
  hear normal conversation through a sealed exterior wall, even if the players' coordinates are close.
- Open doors and windows act as sound portals. Someone just outside an open door can hear a nearby speaker
  inside, with attenuation that rises rapidly as either person moves away from that opening. Closing the
  door restores heavy muffling. Glass transmits a faint voice but should not reveal every word on the street.
- Compute a cheap room/portal path first, then confirm a few raycasts around the head height for close
  listeners. Blend attenuation and low-pass over about 0.2 s when a door opens/closes; avoid abrupt cuts.
  The server updates audibility at about 10 Hz and never trusts a client to report its own room or open door.
- Crew radio uses push-to-talk and ignores walls but announces itself with a local transmit cue. Portable
  phones are point-to-point, can be dropped or traded, and likewise ignore walls only for the call's
  participants. Muting and per-player volume remain local controls.
- Playtest with two speakers in the same room, adjacent rooms, opposite sides of a closed exterior wall,
  and 0–4 m either side of an open door, including at 100 ms latency and packet loss. Speech should be
  intelligible only in the cases a person on site would expect.

**Disconnects:**
- The dropped player's items fall where they stand and their car seat is freed immediately.
- A 90 s rejoin window restores that slot's crew and personal cash.
- The Boss role passes on after 10 s.

**Bandwidth budget (estimates to verify in M1):**

| Size | Players | Down per client | Server up total |
|---|---|---|---|
| Standard | 12 | ~15–20 KB/s | ~0.25 MB/s |
| Large | 24 | ~30–40 KB/s | ~0.9 MB/s |

Player state is about 24 bytes quantised. Voice adds about 3 KB/s per audible speaker.

**Anti-cheat baseline:**
- Server authority as above.
- Rate limits on requests; sanity checks on movement speed and fire rate.
- No client-trusted damage, money or hits.

## 11. Mapping the prototype onto the network

| Offline function | Becomes |
|---|---|
| `main._purchase`, `_pay_deal`, `_finish`, `_collect_case` | Server transaction handlers |
| `main._on_shot` | Server hit resolution; client gets a predicted-FX version |
| `player._physics_process` | Shared by client prediction and the server simulation |
| `player.shot_fired` / `weapon_fired` | Client → server shot command; local FX |
| `car._physics_process` | Server simulation plus driver prediction |
| `guard.gd` | Practice-only; never spawned on the server |
| HUD / menus in `main.gd` | Client-only view layer (split into `hud.gd` in M1) |

## 12. Controller support and Steam Input **[BUILT: native pad; PLANNED: Steam Input API]**

**Built:**
- Every action works on an XInput or SDL gamepad through Godot's joypad layer. Steam Input drives this
  automatically when the game is launched from Steam.

| Input | On foot | In car | Menus |
|---|---|---|---|
| Left stick | Move | Steer | Navigate |
| Right stick | Look (curve + edge boost) | Look freely from any seat | — |
| RT / LT | Fire / aim | Throttle / brake-reverse | — |
| A | Jump | Handbrake | Accept |
| B | Crouch (hold) | — | Back |
| X | Reload | — | — |
| Y | Interact / enter / exit | Exit | — |
| RB / LB | Next / previous weapon | Driver: fire / enable one-handed fire | Switch buy tabs |
| L3 | Sprint | Horn | — |
| D-pad up / down | Quick swap / drop case | — | Navigate |
| D-pad left | Buy at HQ (contracts), rearm (free roam) | — | — |
| D-pad right | Gunsmith or ride as a gunner (free roam), ride as a gunner (contracts) | Change seat | — |
| Start / Back | Pause / map | Pause / map | — |

- Prompts show Xbox names or PlayStation names by detected device, and switch live between keyboard and pad.
- There are settings for stick sensitivity, invert Y, and vibration (fire, damage, crash).
- Menus are fully navigable by pad, with focus on open and B to go back. **0.4 fix:** Godot 4.4's built-in
  `ui_accept` and `ui_cancel` have no joypad buttons, so in 0.3 the D-pad moved focus but A never pressed a
  button. `main.gd` now binds A and B to them. This is covered by a synthetic-joypad test.

**Planned:**
- Steam Input API through GodotSteam, with action sets OnFoot, InVehicle, Menu and Trade.
- Official glyph images and a default Steam Input config shipped with the game.
- The Steam on-screen keyboard for text chat.
- Steam Deck: letterboxed at 16:10 today. Target a 1280×800 HUD anchor pass for Deck Verified.
- **Aim assist policy:** none by default in PvP, because it conflicts with the skill pillar. Pad players get
  a tuned response curve instead. A server option for mild slowdown only (no rotation, no magnetism) is up
  for discussion after playtests.

## 13. Art direction — "Port Halcyon at dusk" **[BUILT offline, second pass]**

**0.4 decision: grounded, not cartoon; the engine stays Godot.**
- **The ask.** The user still found the characters too cartoonish and asked whether to change engines.
- **The cause was the construction, not Godot:** capsule-and-sphere limbs, heroic heads and hands, and ink
  outlines.
- **The fix.**
  - Characters are now procedural **skinned** humans: one continuous mesh on a 17-bone skeleton, 1.8 m with
    about 7.5-head proportions, a sculpted head with a painted face, and garments with overlay shirt fronts,
    ties and lapels.
  - Outlines are gone from characters, guns and vehicles.
- **Why not switch engines.** Godot 4 renders skinned, realistic characters well. Switching would mean
  rewriting ~9,000 lines and would still leave the real long-term need: **authored character art** (Blender
  sculpts, or CC0 bases such as MakeHuman exports) plus motion-captured or hand-keyed animation. Nothing has
  been downloaded yet; that needs the user's go-ahead.

Target era: sixth-generation consoles (PS2, GameCube, original Xbox). These are touchstones for mood only,
and we copy nothing:
- the neon-and-sodium cities of that era's open-world crime games;
- *Jet Set Radio Future*'s colour confidence;
- *killer7*'s graphic boldness;
- *The Getaway* and *True Crime*'s wet-street moodiness;
- *Yakuza*'s dense entertainment district.

**Look pillars:**
1. **Dusk and neon.** A low orange sun, a violet-to-amber sky, sodium street lamps and lit windows. Each
   crew's neon hue owns its district.
2. **Chunky low-res textures.** Procedural 64×64 textures (brick, stucco, asphalt, concrete tiles, planks,
   corrugated metal) with nearest-neighbour filtering and world-space triplanar mapping. This alone
   separates us from Sub Rosa's flat untextured look and NBD's Roblox materials.
3. **Crew-readable characters.** Realistic proportions (0.4). Crew colour on the armband, hat and garment,
   and a distinct hat silhouette per crew.
4. **Era post-filter** (toggleable): 5-bit-per-channel posterise, 4×4 ordered dither, a warm grade and a
   soft vignette.

**Performance guardrails:** Compatibility renderer, a single shadowed sun, 8 or fewer dynamic lights, merged
static meshes per district, HUD text without drop shadows.

## 14. Milestones and acceptance criteria

1. **M1: LAN slice (2–4 clients).**
   - Join, buy, drive, trade by handshake, shoot, finish a round.
   - Double submissions never duplicate cash or items. Simultaneous pickups and seat entries have exactly one winner.
   - A disconnect frees the seat and the item.
   - Holds at 100 ms latency and 2% packet loss.
   - **Test:** automated two-headless-client scenarios in CI plus a human session.
2. **M2: 12-player week.**
   - Three crews, all four contract types, phones, proximity voice, Street Rep, escrow.
   - **Test:** full Week with 12 people; no RDM complaints dominate feedback; median deal attempts ≥ 3 per round.
3. **M3: Feel pass.** Gunfeel, attachments and car tuning from playtest data.
   - **Test:** repeatable handling test track; recoil spray variance within target.
4. **M4: 24-player stress.** Four crews; profile server tick time under 8 ms and bandwidth within budget.
5. **M5: Steam release candidate.**
   - Steam lobbies and relay, Steam Input action sets, glyphs, Deck pass, achievements.
   - Store page, privacy disclosures for voice, crash reporting.

## 15. Open questions for you

1. Are timetabled trains, lifts and doors OK under the no-AI rule, or should the city have zero moving
   scripted objects?
2. Friendly fire on or off by default?
3. Should the Boss role be fixed for the Week (a stronger identity) or rotate each round?
4. Should controller aim assist stay at "none" permanently, or be a community-server option?
