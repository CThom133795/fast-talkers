# Fast Talkers in one page (read this first)

**Fast Talkers is a round-based deal-making game with guns in it. It is not a shooter with deals bolted on.**
Crews of four meet in an ordinary, frozen-in-1999 city to buy, sell, bluff, rob and renegotiate. Gunfire is always
possible, which makes every handshake tense, but the best stories come from conversations: a deal that almost went
wrong, a bluff that worked, a betrayal that got paid back on Thursday.

References for the *feeling*: Sub Rosa and No Big Deal (negotiation under threat), GTA IV (vehicle weight),
Battlefield/BattleBit (responsive gunplay), CS (round buying). Nothing is copied from them.

## The shape of a match: one Week of five Days

- A **match is a Week**; a **round is a Day**, Monday to Friday. Money carries across the Week. Survivors keep their
  gear; the dead restart with the free pistol. **Friday is always the Dead Drop**, the climax.
- Typical lobby: 12 players, 3 crews of 4. Large: 24 players, 4 crews of 6.
- Crews win the Week on **banked money**, not kills. There is **no kill reward anywhere**.
- Grudges, favours and reputations carry from Day to Day inside a Week, and reset at the next Week.

## A Day, from a player's seat

1. **Morning at HQ (lineup and buy, about 1 min).** The HQ phone rings. Today's contract: "You're selling the Ledger.
   Sol Negro wants it, Kingsway might too." You buy a pistol and armour and argue with your crew about the price. The
   crew phone sits on the table in the spawn; there's no Boss, so your crewmate grabs it first and calls Sol Negro.
   They offer $4,000 and want to meet "behind the burger place on Motor Mile".
2. **The street (about 9 min).** Doors open.
   - You drive the case across town while a crewmate scouts the meeting spot from the parking garage roof with
     binoculars.
   - A payphone rings on a corner: a voice promises cash stashed in the garage. Maybe real, maybe nothing. Kingsway
     heard a payphone too, and now two crews are drifting toward the same block, each suspicious of the other.
   - You don't take the bait. Your crewmate with the phone calls Sol Negro back and moves the meet to the motel
     walkway.
   - Face to face, hands up, proximity voice: "Open the bag." They count the cash. You check it isn't counterfeit.
     Handshake.
   - Or someone draws, and the chase starts: cars, alleys, the club's back door.
3. **Settle (about 20 s).** What's inside your HQ safe is banked. The board shows who honoured deals and who broke them.
4. **Overnight.** Collateral pays back, grievances ring the phone ("Sol Negro wants a sit-down"), and tomorrow's
   contract is a little bigger.

Meetings can happen **anywhere**. There are no official deal zones. "Meet me behind the diner" should be natural talk.

## Phones: two kinds, and no Boss

- **The crew phone** sits in each crew's HQ spawn. **There is no Boss role.** Whoever grabs the phone makes the calls
  to the other crews, and the crew sorts out who talks. It is a physical object: it can be carried, dropped, stolen
  or handed over. It rings with the day's contract, sit-down offers and other crews' calls.
- **Street payphones are distractions,** not a reliable lead system. They ring around the city to stir unrest: a
  voice promising a stash, a rumour, a lure. Their job is to **pull crews across each other's paths** and create
  encounters, bait and paranoia. Answering one is a gamble; ignoring one is a choice. They must never become the
  dependable way to win or catch up.

## Inventory: weapons, one trade item, the phone

Proposed by the user (2026-09-30); **not built yet**. Each player carries three independent things:
- **Weapons:** unchanged. Primary and sidearm slots, the buy menu and the locker all work as today.
- **One trade item, and only one:** a briefcase (cash or anything in it), the Project (the contract Ledger) or a
  cash bundle. Picking up a second trade item is refused ("hands full") until you drop the first. Two items can't
  be stacked into one carry.
- **The crew phone:** its own slot, separate from the trade item. One per crew, grabbed from the HQ spawn.

Each drops **independently**:
- **G (D-pad down) drops the trade item.** This key already drops the contract case today; keep it.
- **K (hold D-pad down) drops the phone.** K is currently unbound; check the pad mapping for conflicts.
- Dropped items are server-owned world objects with IDs and contents. Anyone can pick them up, including rivals.
  On death, both the trade item and the phone fall where you died.
- **Hand-over:** dropping the item at someone's feet is the physical trade. The optional handshake trade in
  `docs/MULTIPLAYER_DESIGN.md` §5 swaps two players' trade items atomically.
- **HUD:** show both slots (for example "CASE" and "PHONE"), so everyone knows what they're holding. What a rival
  holds stays visible on their model (a briefcase in hand, the phone at the ear during a call), never as a map marker.
- **Decided:** carrying a trade item limits you to the sidearm (see the user's decisions below). The weapons system
  itself stays as is.

## The user's decisions (2026-09-30, binding)

1. **Carrying a trade item limits you to your sidearm.** While holding a briefcase, the Project or a cash bundle you can
   draw and fire only the sidearm slot; the primary is slung. Dropping the item (G) restores the primary.
2. **Build all trust systems that make logical sense and keep players engaged.** In `docs/DESIGN_WEEK_TRUST.md` terms,
   that means all of them:
   - W0, the Week foundation, first;
   - then A (Sit-Down call), B (overnight collateral), C (noise is news), D (the comeback lifeline), E (the audit call),
     F (honour pays on Friday), G (Broker joint jobs), H (readable intent: handshake, caller ID, deals board) and
     I (conduct floor);
   - in the T0–T5 order after the playtest zip is stable;
   - each host-validated, with a `week_flow` or trust test, and with abuse counters as written.
3. **Friday is always a bloodbath.** The Dead Drop has no truce rules. Trust systems pay out on Friday (F gives early
   intel; collateral from Thursday settles Friday morning) but never restrain Friday's violence.
4. **The comeback lifeline (D)** was an open choice between two versions:
   - a **Loan Shark** phone call: borrow cash mid-week, repay with interest on Friday;
   - a **Pawn Shop**: sell your carried gear for quick cash.

   **Decided: build the Loan Shark.** The user finds it a fun way to keep the pace going. Keep the Pawn Shop on the
   table as a possible later addition (it could sit alongside the loan shark), but don't build it now.

## The core loop

**Contract, then call, then choose a place, then travel, then meet, then inspect, then trade (or betray), then escape,
then bank.** Every system should serve one of those verbs:
- **phones:** the crew phone at HQ (anyone can grab it) for calls between crews and the sit-down; street payphones
  as distractions that stir unrest and pull crews across each other's paths;
- **physical items:** cases, cash, counterfeit, the Ledger;
- **readable intent:** hands up, holstered weapons, voice;
- **places with approaches and exits:** interiors, garages, alleys, parks with railings;
- **vehicles:** getaway, escort, the courier.

## What keeps it a deal-making game (the design test)

Before building a feature, ask:
1. **Does it make a conversation more interesting, or more necessary?** Crew phones, inspection and collateral do; payphones create encounters.
   A kill streak does not.
2. **Does it keep betrayal possible, but give honesty a reason?** Never block a shot or force peace. Make keeping your
   word pay more as the Week goes on.
3. **Does it keep every crew in the Week until Friday?** Catch-up comes from opportunity and information, never free
   money for losing.
4. **Is it physical and readable?** A diegetic phone, a case you must open, a gun you can see holstered. No modal
   trade windows.
5. **Is it fair and server-authoritative?** Anything that moves money or items is validated by the host.

The known failure mode of the genre: **by mid-week, grudges and hopeless standings turn Days into sandbox deathmatch.**
`docs/DESIGN_WEEK_TRUST.md` is the plan against it: the Sit-Down call, collateral held overnight, gunfire that becomes
street news, a risky lifeline for the last-place crew, the audit call, and honour paying on Friday.

## Not this game

- No NPCs or traffic.
- No official meeting zones or safe zones.
- No kill rewards.
- No copied art, names or maps.
- Not a battle royale, and not a deathmatch with cases.

## Tone

- A late-1999 city **paused in time**: faded posters, Y2K notices, pagers, payphones, CRTs, clocks stopped at 11:59.
- Ordinary places that invite a deal: diner, motel, garage, club, hotel lobby, office tower, gun store.
- The look: PS2 / Xbox / GameCube-era low-poly, readable silhouettes, original everything.
- Performance: 60+ fps on the user's RTX 3080, with a POTATO MODE setting for minimum-spec PCs.

## Where things stand (end of the overnight cloud session)

- **Built:**
  - the city and its landmark interiors;
  - vehicles and gunplay, and the buy phase;
  - one contract case, and a street payphone that rings with a stash lure;
  - the listen-server multiplayer (hardened), with an optional Steam path that is untested;
  - proximity voice with a crew radio;
  - the hands-up gesture.
- **Not built yet:**
  - the **Week itself** (no weekday state, carry-over or standings in code);
  - cash, counterfeit and briefcase items, and the one-trade-item plus phone inventory;
  - inspection;
  - physical phones for crew-to-crew calls (text chat channels exist);
  - the deals board;
  - every trust proposal.

That is the next big body of work. See `CLAUDE_HANDOFF.md` and `docs/CLAUDE_DESKTOP_PICKUP.md`.
