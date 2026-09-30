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
   Sol Negro wants it, Kingsway might too." You buy a pistol and armour and argue with your crew about the price. Your
   Boss calls Sol Negro on the phone. They offer $4,000 and want to meet "behind the burger place on Motor Mile".
2. **The street (about 9 min).** Doors open.
   - You drive the case across town while a crewmate scouts the meeting spot from the parking garage roof with
     binoculars.
   - A payphone rings on the way. Someone tells you Kingsway is watching Motor Mile.
   - You call Sol Negro back and move the meet to the motel walkway.
   - Face to face, hands up, proximity voice: "Open the bag." They count the cash. You check it isn't counterfeit.
     Handshake.
   - Or someone draws, and the chase starts: cars, alleys, the club's back door.
3. **Settle (about 20 s).** What's inside your HQ safe is banked. The board shows who honoured deals and who broke them.
4. **Overnight.** Collateral pays back, grievances ring the phone ("Sol Negro wants a sit-down"), and tomorrow's
   contract is a little bigger.

Meetings can happen **anywhere**. There are no official deal zones. "Meet me behind the diner" should be natural talk.

## The core loop

**Contract, then call, then choose a place, then travel, then meet, then inspect, then trade (or betray), then escape,
then bank.** Every system should serve one of those verbs:
- **phones:** call a crew, answer a tip, get the sit-down;
- **physical items:** cases, cash, counterfeit, the Ledger;
- **readable intent:** hands up, holstered weapons, voice;
- **places with approaches and exits:** interiors, garages, alleys, parks with railings;
- **vehicles:** getaway, escort, the courier.

## What keeps it a deal-making game (the design test)

Before building a feature, ask:
1. **Does it make a conversation more interesting, or more necessary?** Phones, tips, inspection and collateral do.
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
street news, tips for the hungry crew, the audit call, and honour paying on Friday.

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
  - one contract case, with the payphone street tip;
  - the listen-server multiplayer (hardened), with an optional Steam path that is untested;
  - proximity voice with a crew radio;
  - the hands-up gesture.
- **Not built yet:**
  - the **Week itself** (no weekday state, carry-over or standings in code);
  - cash, counterfeit and briefcase items;
  - inspection;
  - physical phones for crew-to-crew calls (text chat channels exist);
  - the deals board;
  - every trust proposal.

That is the next big body of work. See `CLAUDE_HANDOFF.md` and `docs/CLAUDE_DESKTOP_PICKUP.md`.
