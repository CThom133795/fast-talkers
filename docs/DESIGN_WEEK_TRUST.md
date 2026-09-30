# The Week without the mid-week collapse: trust, repair and reasons to keep your word

Interim lead proposal, 2026-09-30 (cloud session). **Design only. None of this is implemented.** The user asked for
brainstormed incentives and player-facing tools. The earlier "no economy / reputation / restitution systems" rule
covered the overnight code pass, and these ideas need the user's approval before code. Companion documents:
`docs/SUBROSA_NBD_RESEARCH.md` (reference facts and gap list), `docs/REFERENCE_RESEARCH.md` (earlier proposals),
`docs/MULTIPLAYER_DESIGN.md` §4–5 (the Week, contracts, the street line, trust tools).

## 1. What the references show

Source quality: the proxy blocked direct fetches of the developer interview, wiki pages and review sites tonight, so
this relies on search-result summaries of those pages (listed at the end). Treat quotes as paraphrase.

- **Sub Rosa (Cryptic Sea).** The designer built the game to get players *not* to shoot each other despite automatic
  weapons. His tools:
  - briefcases you must open to verify, which make empty or fake-topped cases possible;
  - one 80s cellphone per corporation, so deals are negotiated before anyone meets;
  - money that decides standings across a five-day "work week", with money reset every five rounds on week servers.

  Reviews praise the tension of "not knowing whose side anyone is on". They blame a community that ignores the point,
  plus poor communication, for rounds that decay into "poorly controlling first-person deathmatch". Toxicity toward
  newcomers is a recurring complaint.
- **No Big Deal (Roblox).**
  - Five rounds, Monday to Friday, with a new mission each day. Friday is always a Dead Drop.
  - Three of five companies play each week, each with a quota. Companies that miss it go bankrupt and are replaced.
  - The stated goal is "the most capital through deals, dirty deals, backstabbing, deathmatching", and betrayal,
    blackmail and looting are "virtually normal".
  - Voice is recommended. Votekick exists.

## 2. Why the week collapses by Wednesday (diagnosis)

We don't have their telemetry, so these are design inferences, ordered by how much they probably matter:

1. **Grievance with no outlet.** A Tuesday betrayal becomes a Wednesday vendetta. The only tool for settling a score is
   a gun, so every betrayal spawns more violence and the fight outlives the deal.
2. **Honest trade loses value after the first betrayal.** Nobody will trade with the betrayer, and trading carries risk
   for everyone else too. Violence has no such decay, so it becomes the cheaper strategy by default.
3. **Hopeless standings.** Once a crew can't reach the quota or first place, it has nothing to lose. Burning the week
   down, kingmaking and pure killing become rational. NBD's quota is judged on Friday, but the outcome is obvious
   by Wednesday.
4. **The gear snowball.** Survivors keep gear (as in our CS-style rule), so late-week fights favour whoever has
   already won fights.
5. **Violence is quiet and cheap.** No kill is paid, but none costs anything beyond the round either. Gunfire reveals
   nothing that a secret deal would have kept hidden.
6. **Friction and norms.** No voice (or bad voice), newcomers who don't know the etiquette, and griefers.

## 2b. Phones: two kinds, and no Boss

- **The crew phone** sits in each crew's HQ spawn. **There is no Boss role.** Whoever grabs the phone makes the calls
  to the other crews, and the crew sorts out who talks. It is a physical object: it can be carried, dropped, stolen
  or handed over. It rings with the day's contract, sit-down offers and other crews' calls.
- **Street payphones are distractions,** not a reliable lead system. They ring around the city to stir unrest: a
  voice promising a stash, a rumour, a lure. Their job is to **pull crews across each other's paths** and create
  encounters, bait and paranoia. Answering one is a gamble; ignoring one is a choice. They must never become the
  dependable way to win or catch up.

## 3. Pillars (what any fix must keep)

- **Betrayal stays legal, possible and sometimes smart.** Without the possibility of a double-cross there is no tension.
  We never block a shot, force a truce or grant invulnerability.
- **Honesty should compound across the week.** It should pay more on Thursday than on Monday.
- **Repair is an act, not an eraser.** Restitution restores the possibility of trade. The record of the betrayal stays.
- **Everyone stays in contention until Friday,** helped by information and opportunity, never free cash for losing.
- **Violence has economic and informational weight, not moral scoring.** No karma meter judging individual kills.
- **Everything runs through physical, diegetic tools:** phones that ring, cases, cash, boards on walls. No modal
  "trade UI" forced on anyone.

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

   The user wasn't sure what was being asked, so the default is the **Loan Shark**, because it fits the phone-driven
   crime tone. Confirm with the user when D is built.

## 4. Proposals

Each has a one-line pitch, how it works, why it resists the collapse, and how it could be abused.

### A. The Sit-Down call (repairing trust)
When a crew is betrayed (a handshake broken, counterfeit paid, a trading partner killed within 10 s of a trade), **both
crews' HQ phones ring at the start of the next day**. The Commission, an unseen voice on the line, offers a sit-down.
- The betrayer can offer **reparations by phone**: cash, return of an item, or a promise of worse terms tomorrow
  (for example, 10% off the next deal). It goes into host-held escrow.
- The wronged crew **accepts or refuses**.
  - If it accepts, the reparations transfer, and both crews get a **Truce Ticket** for that day. Completing any deal
    together that day pays both a bonus from the house. The betrayal stays on the board, marked "settled".
  - If it refuses, nothing happens. That is their right, and vengeance stays legal.

*Why:* it turns "revenge or nothing" into "revenge, or get paid and make money together tomorrow".
*Abuse:* two crews staging betrayals to farm Truce bonuses. Counter: the bonus comes only from a real completed deal,
caps at once per crew pair per week, and the reparations must exceed the bonus.

### B. Collateral held overnight (tie the week together)
Either side of a deal can ask for **collateral**: both crews deposit an agreed sum by phone, held by the Exchange
**until 9:00 the next morning**.
- If the deal completes honestly, both get their collateral back plus a small interest the next morning.
- If one side breaks the deal (as the server defines it: killed the partner in the handshake window, or paid
  counterfeit), that side's collateral goes to the victim.

*Why:* it makes keeping your word *today* pay out *tomorrow*, a direct counter to the Wednesday slide. It's
voluntary, so bluffing players can decline, and declining is itself a tell.
*Abuse:* collusion to launder money. Counter: interest is small, and the collateral cap scales with the day's contract
value.

### C. Noise is news: gunfire becomes information (violence has weight)
Sustained gunfire in a district raises that district's **Heat**. Payphones near loud districts start ringing with the
rumour, for example "shooting at Motor Mile, a case was seen leaving north". Whoever answers is pulled toward the fight.
- Quiet deals keep their secrets. Loud fights advertise the loot to the third crew.
- Fits the payphones' job as distractions that pull crews together. No NPC police are needed.

*Why:* it doesn't forbid violence; it makes violence expensive to the shooter by inviting vultures.
*Abuse:* baiting fake fights to pull crews somewhere. That's fine. It's deception, which is on theme.

### D. A lifeline for the hungry (comebacks through risk, not free cash)
Mid-week, the last-place crew's **crew phone** gets a **Loan Shark call**: cash now, repaid with interest on Friday.
If it isn't repaid, the shark takes a cut of Friday's payout. Payphones are **not** a catch-up channel. They stay
distractions for everyone.

*Why:* a trailing crew can re-arm and stay in the Week instead of spoiling it. The loan is a risk, not a gift.
*Abuse:* sandbagging for a loan. Counter: interest makes the loan a bad deal unless you actually come back.

### E. The audit call (soft cap on runaway leaders)
On Wednesday morning the leading crew's phone rings: **"The Board raised your quota."** The leader's Friday target rises
by a share of its lead. A crew that finishes the week above its raised quota earns a "Preferred Vendor" line on the
board next week.

*Why:* it keeps second and third place in contention without taking money away. The leader chooses between playing it
safe and pushing.

### F. Honour pays on Friday (the week's arc)
Every honoured deal Monday to Thursday earns **Insider Info for Friday's Dead Drop**. The first honoured deal gives a
district hint 30 s early; three honoured deals give the exact site 30 s early.

*Why:* Friday stays the chaotic climax the genre loves, and trust earned during the week buys a real Friday edge.
Chaos on Wednesday costs you Friday.

### G. The Broker's joint job (a reason to trust a rival)
Some days two crews' **crew phones** ring with the same **two-crew job**: a vault that needs two keys held by different crews, or a heavy
crate that needs two carriers and a car. The payout is split, and only paid if both halves are banked.

*Why:* cooperation is the only way to get this money, so one betrayal doesn't cost just a deal. It costs the job.
*Abuse:* betraying at the vault. Legal, but it forfeits the payout. Keep the payout large enough to tempt cooperation.

### H. Readable intent (small, cheap, high value)
- **Already built:**
  - hands up (X), with the weapon really holstered;
  - binoculars;
  - voice: proximity by default, with a crew radio that mutes proximity, and walls that block passers-by.
- **Next:**
  - a **handshake gesture** that starts the optional atomic trade;
  - **caller ID on phones** showing the caller's board marks (for example, "Welsh ×1, settled");
  - a public **Deals Board** in each HQ listing honoured, broken and settled deals this week;
  - a speaking icon over talkers.

### I. Conduct floor (anti-grief, not anti-betrayal)
- HQ spawn protection during the buy phase (already partly there with locked doors).
- Votekick, as NBD has.
- A crew member who kills their own crew twice in a week gets "**fired**": they spectate the next day and can
  rejoin on Friday.
- Friendly fire stays on; only repeat offences are handled.

## 4b. The Week and Day mindset (foundation for everything above)

A **match is a Week**, and each **round is a Day**, Monday to Friday. As of this branch, **no Week structure exists in
code**: `main.gd` and `online.gd` run standalone rounds, with no weekday names, no carry-over state and no week standings.
Design is in `docs/MULTIPLAYER_DESIGN.md` §4 and `docs/DESIGN_WEEK_TRUST.md`. Suggestions to align everything with it:

- **Vocabulary everywhere.** Say "Week" and "Day" (not match and round) in the UI, docs, test names and code comments
  going forward:
  - the HUD shows "TUESDAY, DAY 2 OF 5" and a clock;
  - the result screen is "END OF DAY";
  - after Friday comes "END OF WEEK" with standings.
- **One server-owned `week_state`:**
  - day index, crew banks, carried gear per player (CS rule: survivors keep gear, the dead restart with the free
    pistol), the deals board;
  - overnight escrow/collateral, grievances and settlements, quota and audit, loans.

  The host owns it; clients get snapshots. It must survive a player disconnecting and rejoining mid-week (match by
  Steam ID or name plus crew).
- **Day rhythm is a ritual:**
  - morning lineup: the HQ phone rings with the day's contract, any sit-down offers and the audit call;
  - buy phase, then street, then settle;
  - "the morning paper": a 10–15 s recap card between days (yesterday's honoured and broken deals, who got robbed,
    which district got loud).

  The recap turns yesterday into today's grudges and offers.
- **Days differ on purpose.**
  - Monday is low stakes: a smaller contract that teaches the roster who is who.
  - Wednesday is the pivot: audit call, standings shown, loan offers.
  - Thursday sets up Friday: insider info is earned.
  - Friday is always the Dead Drop climax.

  Contract value should rise through the week, so honesty early is cheap and betrayal late is expensive.
- **Consequences cross the night.**
  - Collateral releases and interest pay "at 9:00 next morning".
  - Reputation marks and settlements last the whole Week and reset for the next Week.
  - Nothing persists past the Week except cosmetics and stats.
- **Everyone plays to Friday.** Risk-based catch-up (the loan shark), a quota raise for the
  leader, and no elimination before Friday. At most, a crew that misses its quota is "restructured" (NBD-style
  replacement) at the Week's end.
- **Tests should speak Week.** Add a `week_flow` headless suite: run 5 days quickly (short timers), assert that money
  and gear carry correctly, that the dead restart with a pistol, that Friday forces the Dead Drop, that the standings
  are right, and that a rejoining player gets their state back. Extend `net_pair` with a two-day step.
- **Settings and lobby.** The host picks the Week length (5 days default; 3 for a quick session) and day length (9:00
  street default). Store both in the week state so every peer agrees.

## 5. Recommended order (for Claude Desktop, after user approval)

| Step | What | Why first | Size |
|---|---|---|---|
| W0 | **The Week itself:** week_state, weekday HUD, morning recap, carry-over, Friday Dead Drop, `week_flow` tests | Nothing in §4 works without Days that remember | M |
| T0 | **Telemetry per day:** deals proposed, honoured and broken; shots fired before the first deal; kills per crew pair; phone calls placed and answered | Can't tune what we can't see | S |
| T1 | **Deals Board, plus caller ID with marks (H), plus a server-side definition of "broken deal"** | Every other proposal needs this record | M |
| T2 | **Sit-Down call (A), plus collateral held overnight (B)** | Directly attack grievance and the slide; both use phones and escrow | M |
| T3 | **Noise is news (C), plus the lifeline (D)** | Cheap; reuse the payphone ring and crew phone | S–M |
| T4 | **Honour pays on Friday (F), plus the audit call (E)** | Shape the week's arc | S |
| T5 | **Broker joint jobs (G)** | Biggest content cost; do after the loop is proven | L |

Server authority: every transfer, bonus and board entry is host-validated through the existing `net_security` path.
No client-reported "betrayal". The host infers it from real events: a handshake, a kill within the window, and
counterfeit detected at banking.

## 6. How we'll know it works (playtest targets)

Run a full week with 9–12 players, with and without T1+T2:
- **Deals honoured per day stays flat or rises from Monday to Thursday.** This is the anti-collapse metric.
- Median deal attempts ≥ 3 per day.
- Time from the street opening to the first shot does not fall below Monday's by more than 30% on Wednesday.
- At least one sit-down offered and one accepted per week.
- Exit survey: "Would you trade with the crew that betrayed you on Tuesday?" More "yes, after they paid" than "never".

## 7. Decisions for the user

1. Approve, reject or reorder A–I and T0–T5.
2. Does Friday stay a free-for-all Dead Drop, or does honour (F) shape it?
3. Is a Loan Shark (D) too gamey for the late-1999 tone? The alternative is a pawn shop that buys gear for cash.
4. Should repeat team-killers be "fired" (I), or is votekick enough?

## Sources (search summaries; direct fetches were blocked)
- [Game Developer: "Creating the right kind of player in the weird FPS Sub Rosa"](https://www.gamedeveloper.com/design/creating-the-right-kind-of-player-in-the-weird-fps-i-sub-rosa-i-)
- [Sub Rosa on Steam](https://store.steampowered.com/app/272230/Sub_Rosa/) and [Steam Community](https://steamcommunity.com/app/272230)
- [Indie Games Plus review](https://indiegamesplus.com/sub-rosa-review/), [Backloggd reviews](https://backloggd.com/reviews/everyone/eternity/liked/sub-rosa/), [Metacritic](https://www.metacritic.com/game/sub-rosa/)
- [No Big Deal on Roblox](https://www.roblox.com/games/18112334178/No-Big-Deal)
- [No Big Deal gameplay (Miraheze)](https://nobigdealunofficial.miraheze.org/wiki/Gameplay), [Fandom gameplay](https://no-big-deal.fandom.com/wiki/Gameplay), [NamuWiki](https://en.namu.wiki/w/No%20Big%20Deal)
