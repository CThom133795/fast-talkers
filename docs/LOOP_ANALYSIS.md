# Loop analysis: Sub Rosa, No Big Deal, and the Fast Talkers loop

Claude, 2026-09-29, for prototype 0.4; Codex 0.5 research and design update. Status tags as in `MULTIPLAYER_DESIGN.md`: **[BUILT]** exists in the
offline prototype, **[PLANNED]** does not exist yet.

**How this was researched.** The 0.4 pass used video titles and summaries, the Roblox page, community
guides, Cryptic Sea's Sub Rosa page and a developer interview. For 0.5, I inspected the auto-caption
transcript of [SimpleBusiness's No Big Deal beginner guide](https://www.youtube.com/watch?v=ORed1pRNQO0)
against its YouTube page. I have not verified every example visually; captions can mishear names and
numbers. The other creator videos below remain title/description leads, not footage analysis.

Sources are at the end. Treat the "what creators highlight" section as a reading of titles and summaries,
not of footage.

---

## 1. Sub Rosa (Cryptic Sea, 2014–)

**Loop.**
- Three corporations share a city. In Round mode they play a five-day work week.
- Each day every team gets a mission. In *Acquisition*, everyone tries to intercept an **AI-driven car**
  carrying a disk. In *Transaction*, two teams try to broker a deal while the third tries to kill them.
- The day ends when all disks and cash are in base safes.
- Each team has an 80s cellphone to call other teams and agree a drop point. Local voice chat carries whispers
  and shouts.

**Tools of deception.**
- Briefcases can be filled with fake cash, a few real notes over blanks, or nothing at all.
- Opening the case reveals the truth, but only after the handover.

**Anti-violence by friction.** The developer's stated intent was to make shooting a bad deal:
- Killing pays nothing, and dying costs 10% of your net worth.
- The phones exist to stop "itchy trigger fingers" before a deal is set.
- Guns use Receiver-style two-handed handling with manual magazine management, and bleeding. Fights become
  "chaotic, clumsy, quick things."

**What went wrong.** The developer said it himself: online, "if there's an exploit, people are going to abuse
it." His answer was server settings, from hardcore (lose 100% on death) to action servers (lose 0%). Player
culture therefore varies by server, and random deathmatch complaints persist.

## 2. No Big Deal (Roblox, 2024–)

The Roblox page calls it a "round based business-negotiation shooter", openly inspired by Sub Rosa. Its
players are there to "raise the most capital through deals, ambushes, negotiations, and trying not to shoot
anyone."

**Loop.** A work week of five rounds, Monday to Friday. Friday is always a Dead Drop. Each round has four
phases:

| Phase | Time | What happens |
|---|---|---|
| Team selection | 1:00 | Pick one of three companies (up to 5 players each) |
| Negotiation | 2:00 | Buy weapons and items, coordinate with rivals by phone |
| Day | 10:00 | Missions in the city |
| Closing | 0:30 | Round ends |

- **Objectives:** Transaction (buy or sell), Double Disk, Acquisition, Dead Drop.
- **Disks** are worth $2,000–$5,500. Five companies rotate: the winner stays and the losers go bankrupt.
- **Economy:** unspent money carries over; purchased equipment does not.
- **Anti-turtling:** the timer speeds up if at least 60% of players are in their spawn rooms after 8:00, and
  the round ends early if only one team is left alive inside its spawn.

**Map.**
- Three HQs are spread out (upper-west downtown, upper-east, bottom-right).
- Dead drops and acquisitions spawn at named landmarks in the neutral spaces between them: a club, a
  forge, a dockside warehouse, the port cranes, storage units, a train station.

**Gunplay, by design.**
- Bullets leave the **barrel, not the crosshair**. Damage **varies randomly** between 85% and 115%.
- Arms are non-lethal, and moving wrecks accuracy.
- A Korean wiki summary calls the gun system "deliberately terrible", with a long time-to-kill.

**Culture.**
- Voice chat and role-play are encouraged. The page warns the game is "highly confusing for those
  uninitiated."
- Betrayal, blackmail and looting between companies are normal, and player-made "mafia" groups appear.

## 3. What creators and clips highlight

Video titles are the clearest signal of what people find worth sharing:
- *Company Betrayal!*
- *the mafia in roblox*
- *Small Deals*
- *My NEW Favorite Roblox Game*
- *Aggressive Negotiations*
- *Greedy Shoot-outs*
- *Sub Rosa: The Deal*
- *Guns Guns Guns*

The recurring beats are:
1. **The handover.** A deal is set up on the phone and walked into, then either honoured or betrayed. That
   moment of trust is the core clip.
2. **Greed and escalation.** Somebody decides the disk is worth a war, and a clean deal turns into a
   shoot-out.
3. **Social roles.** Players invent structures (mafias, protection, bodyguards) that the rules don't
   require.
4. **Chaos as comedy.** Clumsy guns, ragdolls and physics make many clips funny *because* control is lost.

Beats 1–3 are the game. Beat 4 is where the user wants us to differ: the laughs come from the jank, and so do
the unfair outcomes and the random-deathmatch culture.

**What one creator actually teaches.** [SimpleBusiness's guide](https://www.youtube.com/watch?v=ORed1pRNQO0)
explains a complete player loop: learn which crew has cash or the project, phone a rival, agree on an amount
and a meeting place, travel there, exchange or bluff, then deliver the project to your HQ to bank it
(0:34–2:16). Later it describes diversions, third-party alliances and hiding the project (6:03–8:27).
This supports an important map rule: players need distinctive landmarks they can name on a call, plus
enough entrances and exits to choose their risk. They do **not** need official meeting zones.

The guide calls fake cash easy to spot (1:27–1:53) and says that moving fire, barrel/crosshair mismatch
and segmented body damage make gunfights hard to read (3:51–4:45). Fast Talkers should make counterfeit
quality a meaningful inspection contest, and should preserve its reliable crosshair and deterministic
damage. Its portable phone, cash, briefcase and project examples (4:46–5:37) show how a few physical items
create many player-made plans. The guide also describes an item that pays **both** crews if delivered
(5:38–6:03); an original shared-payout contract could make cooperation a profitable choice without
preventing betrayal. That is a design inference, not an implemented mechanic.

## 4. Where they lose skill and interaction

| Problem | Cause | Effect on play |
|---|---|---|
| Fights decided by randomness | Barrel-origin shots, ±15% damage, clumsy reloads, bleeding | Skilled players can't reliably win the fights they choose, so violence stays a lottery |
| Betrayal without counterplay | Contents unknown until after handover; no atomic trade | The "right" move is to shoot first, which feeds random deathmatch |
| Dead time | 1–2 min selection and negotiation, long days, turtling | Clips are the 5% in between; the rest is waiting |
| Confusion | Many objective types, rules learned from others | New players are prey |
| Sparse opportunities | One contract per round, fixed roles | If your crew has no stake in this round's deal, you wait or rob someone |

## 5. The Fast Talkers loop: keep the stories, remove the jank

**Design sentence:** *Anything can happen in Port Halcyon, but what happens is decided by what you chose,
where you went, and how well you shot or drove.*

| Principle | System | Status |
|---|---|---|
| Crisp, learnable fights | Crosshair-true hitscan, deterministic damage, learnable recoil, visible attachments | [BUILT] |
| Guns with identities you choose | 13 weapons, e.g. KV-47 one-headshot kill vs M4 control, MAC-11 drive-by, sawn-off off the back of a bike | [BUILT] |
| Commitment before the street | 30 s CS-style buy phase at your HQ; sell-back; survivors keep their gear; HQ purchases later with no refunds | [BUILT offline] |
| A second skill: driving | Five vehicle types, free-look seats, one-handed drive-bys, passenger gunners, wrecks | [BUILT offline]; vehicle art pass underway |
| Readable geography | Fewer canals, multiple approaches per district, named plazas and broadly fair routes to Midtown | [PLANNED in 0.5 map pass] |
| "Anything can happen" | **Street tips**: a payphone rings mid-round; answering reveals a stash with a deadline | [BUILT offline] |
| More street events | Hot cars for the chop shop, dead-drop reveals, courier runs, tips you can *sell* to another crew | [PLANNED] |
| Betrayal with counterplay | Handshake atomic trade, escrow, counterfeit tells, UV penlight | [PLANNED] (§5 of design doc) |
| Consequences, not rules | No kill money; death drops what you carry; Heat and Street Rep for killing the unarmed | [PARTIAL]: drops built offline |
| No dead time | Buy phase is live (look, walk the yard); street phase 8–9 min in multiplayer; anti-turtling clock | [PARTIAL] |

**The round, in multiplayer (target):**
1. **Buy phase (0:30) at your HQ.** Buy, plan, and take phone calls from rival crews. HQ doors are locked.
2. **Street (8:00–9:00).** The contract is the spine: deal, rob, broker or escort. Around it, tips ring on
   street payphones:
   - A tip goes to **one crew** and marks a stash, a hot car or a drop somewhere neutral.
   - That crew can race for it, sell it over the phone, or use it as bait for an ambush.
   - Information becomes currency, and it gives every crew a reason to be on the street every round.
3. **Settle (0:20).** Items in HQ safes bank, and the Week's ledger updates.

**Why this stays skill-based.**
- Every chaotic moment starts from a player decision: answering the phone, betraying the handshake, taking a
  side street instead of the plaza, riding pillion with a sawn-off.
- Every resolution uses a skill: aim, recoil control, driving lines, seat choice, reading intent.
- Randomness only chooses *where* opportunities appear, never who wins a fight.

## 6. What changed in 0.4 because of this

- **Street tips** in contract rounds [BUILT offline]:
  - A payphone near you rings 35–80 s in.
  - Answering gives 75 s to reach a stash at a neutral landmark.
  - Banking it at your HQ pays $900; dying with it loses it.
  - Offline this stands in for "another crew got the call".
- **Buy phase and carry-over** [BUILT]: the round opens in a real, CS-style buy phase, and survival matters
  because your gear carries over.
- **Map** [BUILT]: islands, bridges and neutral hubs follow No Big Deal's spread-out mission sites and the
  PS2-era GTA island cities. Chokepoints make ambushes and escorts readable.
- **Vehicles as a verb** [BUILT]: the clips people love are chases and escapes, so every seat now does
  something.

## 7. Open questions for playtests

1. Should tips go to one crew, or ring publicly so any crew can race for them? One crew makes information
   tradeable; public makes chaos.
2. Is $900 right beside a $2,600 contract? Tips should be worth leaving your post for, but not worth
   abandoning the deal.
3. Does the 30-second buy phase give a new player enough time to compare prices and return a purchase?
4. With survivors keeping gear, does the Week snowball? Watch round-5 cash spreads.

## 8. The 0.5 correction

The 0.4 islands made district access too predictable and channelled crews through bridges. The active
0.5 map pass replaces that geometry with more continuous, asymmetric land, a less rigid street network,
open plazas and multiple approaches to Midtown. A good meeting can be set at a café, home, garage, street
corner or moving vehicle. The only fixed geography is the mission pickup and crew HQs; neither is a
mandatory meeting site. The pre-round buy time is now **30 seconds**, and the HQ counter remains available
later with **no refunds**.

## Sources

- Sub Rosa: [Steam store page](https://store.steampowered.com/app/272230/Sub_Rosa/),
  [Cryptic Sea](http://www.crypticsea.com/subrosa/), [Game Developer, "Creating the right kind of player in the
  weird FPS Sub Rosa"](https://www.gamedeveloper.com/design/creating-the-right-kind-of-player-in-the-weird-fps-i-sub-rosa-i-),
  [community guide (Alpha 0.25)](https://steamcommunity.com/sharedfiles/filedetails/?id=301242646).
- No Big Deal: [Roblox page](https://www.roblox.com/games/18112334178/No-Big-Deal),
  [wiki: Gameplay](https://nobigdealrblx.miraheze.org/wiki/Gameplay),
  [wiki: Weapons](https://nobigdealrblx.miraheze.org/wiki/Weapons),
  [wiki: Map & Landmarks](https://nobigdealrblx.miraheze.org/wiki/Map_&_Landmarks),
  [NamuWiki summary](https://en.namu.wiki/w/No%20Big%20Deal) (via search summary only).
- Creator guide inspected via auto-caption transcript: [SimpleBusiness, The Ultimate No Big Deal Beginners Guide](https://www.youtube.com/watch?v=ORed1pRNQO0).
- Other creator videos (titles and search summaries only):
  - No Big Deal: [My NEW Favorite Roblox Game](https://www.youtube.com/watch?v=b5GbvH4ibgA),
    [COMPANY BETRAYAL!](https://www.youtube.com/watch?v=-iblRq2mjfU),
    [the mafia in roblox](https://www.youtube.com/watch?v=r52kESval9A),
    [Small Deals](https://www.youtube.com/watch?v=KVJUR_MqpyM).
  - Sub Rosa: [Aggressive Negotiations](https://www.youtube.com/watch?v=RNTt-00UahA),
    [GREEDY SHOOT-OUTS](https://www.youtube.com/watch?v=-_LGggfzvao),
    [Sub Rosa: The Deal](https://www.youtube.com/watch?v=o7mt-eV5rDI),
    [GUNS GUNS GUNS](https://www.youtube.com/watch?v=3PmcJl0y0ik).
