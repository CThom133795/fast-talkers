# Lead design decisions: improving on No Big Deal and Sub Rosa

Claude Desktop, lead, 2026-09-30. The user delegated these choices ("make some choices on how to improve upon the
systems presented in No Big Deal and Sub Rosa"). They are **binding for all agents** until the user overrides one.
Where the user already decided something (`docs/GAME_VISION.md`, "The user's decisions"), this file builds on it
and never contradicts it. Research facts come from `docs/SUBROSA_NBD_RESEARCH.md` and `docs/DESIGN_WEEK_TRUST.md`.

Each decision gives the reference behaviour, what goes wrong there, and what we do instead. Status tags: **[DEMO]**
is in the playtest build; **[NEXT]** comes next, in this order; **[LATER]** is decided but scheduled after the trust
systems.

---

## 1. The Week is the match, and it tells a story [DEMO]

- **References.** No Big Deal runs five rounds, Monday to Friday, with Friday always the Dead Drop. Sub Rosa week
  servers reset money every five rounds.
- **What goes wrong.** Both treat the days as five copies of the same round. By Wednesday the standings are obvious,
  so trailing crews stop trading and start killing.
- **What we do.**
  - **Contract values rise through the Week:** Monday ×0.6, Tuesday ×0.8, Wednesday ×1.0, Thursday ×1.25,
    Friday ×1.6. An honest Monday is cheap and a Thursday betrayal is expensive, so the Week has a shape.
  - **Friday, the Dead Drop,** is always a bloodbath (the user's rule):
    - the contract lands at one neutral spot, announced when the doors open;
    - there is no seller or buyer: whoever banks it is paid;
    - no clean-deal bonus and no truce rules.
  - **"The morning paper".** Each buy phase opens with yesterday's results: who delivered, who stole, who got hurt.
    The recap turns yesterday's events into today's grudges and offers.
  - **END OF WEEK** after Friday: crew standings on banked money, a winner, then a new Week or back to the lobby.
    Money and gear reset between Weeks.
  - **The host sets the Week length** in the lobby: 5 Days by default, 3 for a quick session. With 3 Days they are
    Wednesday, Thursday and Friday, so the Dead Drop always ends the Week.
  - **SOLO WEEK** on the title menu runs this same Week on one PC (a localhost host, no bots), for demos and for
    the user's solo contract-test path (CLAUDE_HANDOFF.md, "test ladder"). It is the same state machine, not a
    separate mode.
  - A Day ends early once both goods are banked. 10:00 is the hard cap, not the expected length.

## 2. One phone per crew, and it is a real object [DEMO]

- **References.** Sub Rosa gives each corporation one shared phone. No Big Deal negotiates by company phone during the
  negotiation phase.
- **What goes wrong.** The phone is a menu, not a thing. Nobody can steal it, so intercepting a deal is impossible,
  and the phone never creates a scene.
- **What we do.**
  - **Only the player holding the crew phone can call other crews.** In chat, TAB cycles to `call:<crew>`. Everyone
    can still use crew and proximity chat.
  - **The phone sits on the HQ table at spawn. There is no Boss:** whoever grabs it is the crew's voice.
  - **K drops the phone.** It falls on death, and a rival can pick it up.
  - **A stolen phone calls as its owning crew.** Pick up Kingsway's phone and your calls read "KINGSWAY (phone)".
    Impersonation becomes a real play. The other crew's radio still tells them that their phone went missing.
  - **Improvement over Sub Rosa:** interception, impersonation and "who has the phone?" become stories, and it all
    costs one small server-owned item.

## 3. One trade item, sidearm only [DEMO]

- **References.** In Sub Rosa and No Big Deal, anyone can carry everything, and the carrier fights like everyone else.
- **What goes wrong.** One armed player can scoop the whole deal and shoot their way out, so escorts and roles never
  emerge.
- **What we do.**
  - You carry **one trade item** at most: a briefcase, the Ledger or a cash bundle. A second pickup is refused with
    "hands full".
  - **While carrying, only the sidearm works** (the user's rule).
  - The carrier is therefore the weakest player on the street. The crew has to escort, scout with binoculars and
    drive, and **roles emerge without a Boss or class system**.
  - G drops the trade item, as it does today.

## 4. Readable intent before the first shot [DEMO, built overnight]

- **What goes wrong in the references.** The biggest complaint about both games is that rounds collapse into
  deathmatch because nobody can read intent.
- **What we do.**
  - Hands up really disarms you, and lowering them is visible before you can fire.
  - Binoculars let you look at a meeting without aiming a gun at it.
  - Open-mic proximity voice is the default, with a crew radio that mutes you in proximity.
- **[DEMO]** A speaking cue: a rival's name tag reads "(( NAME ))" while their proximity voice reaches you. Crew
  radio never shows, so a whispered radio call stays secret.
- **[DEMO]** A carried crew phone is visible on the carrier's belt, banded in the owning crew's colour.
- **[NEXT]** The handshake gesture that starts the atomic trade.

## 5. Death costs the Day, not the Week [DEMO]

- **References.** Sub Rosa takes 10% of your net worth on death. No Big Deal loses carried money.
- **What goes wrong.** Flat death taxes punish newcomers most, and they feel arbitrary.
- **What we do.** CS rules:
  - survivors keep their gear into tomorrow;
  - the dead restart the next Day with the free pistol;
  - whatever you carried falls where you died.

  Death's price is readable ("I lost my rifle and the case") and it never touches the crew bank.
- Respawn at HQ after 10 s stays for the demo. **[LATER]** From Wednesday, the respawn delay grows by 5 s per Day, so
  late-week fights carry more weight without eliminating anyone.

## 6. Spectating: your crew only [NEXT]

- **Reference.** No Big Deal restricts spectating to your own team until the whole team is dead.
- **What we do.** While dead, you follow crewmates only. You see what they see, with no enemy markers, and you
  talk on crew radio. It keeps the dead in the conversation ("he's behind the van") without leaking intel to other
  crews.

## 7. No anti-turtling clock; the contract gets impatient instead [NEXT]

- **Reference.** No Big Deal speeds up the clock when players hide in spawn.
- **What goes wrong.** A faster clock is invisible and feels unfair.
- **What we do.** If nobody has touched the contract item by 4:00 on the clock, the HQ phones of both contract crews
  ring: "The client is getting nervous." The item's value then falls 10% per minute until someone picks it up. The
  pressure is diegetic, readable and never lethal.

## 8. Carrier cues: physical only [DEMO]

- Rivals never see a map marker for who carries a case. The case is visible in the carrier's hand, and the
  on-ground item shows on everyone's radar, as it does today.
- Your own crew's HUD shows which crewmate carries it.

## 9. Inspection and counterfeits [NEXT, after the trust log]

- **Reference.** Sub Rosa lets you fake-fill a briefcase and No Big Deal has counterfeit cash, but the only defence
  in either game is to shoot first.
- **What we do.**
  - **Hold E on a dropped case to open it.** It takes 2 s, you are exposed, and everyone within 4 m sees the contents.
  - **A counterfeit bundle has a learnable tell:** a slightly wrong band colour, visible when the case is open.
  - **Banking counterfeit pays nothing, and the host logs it as a broken deal.** That entry feeds the trust systems
    in `DESIGN_WEEK_TRUST.md` (Sit-Down call, collateral).

## 10. Trust systems order [NEXT, the user's decision]

W0 (this file, §1) comes first. Then T0 telemetry, T1 the deals board with caller ID and the server-side definition
of a "broken deal", T2 the Sit-Down call plus overnight collateral, T3 noise-is-news plus the **Loan Shark**, T4
honour pays on Friday plus the audit call, and T5 Broker joint jobs. Every step is host-validated and has abuse
counters, as `DESIGN_WEEK_TRUST.md` specifies.

Clarifications I made:
- **A "broken deal"** means either of these, as seen by the host: a kill of the partner crew within 10 s of either
  crew picking up the other's item, or counterfeit banked. The host infers it from real events and never takes a
  client's word for it.
- **Loan Shark.** It rings the last-place crew's phone on Wednesday morning. The offer is $4,000 now, and $6,000 is
  taken from Friday's bank. If Friday's bank can't cover it, the crew ends the Week at a negative balance, shown in
  red on the standings.
- **Conduct floor (I).** Two team-kills in a Week and the player is "fired" and spectates the next Day. Votekick
  needs a majority of the other crews.

## 11. What we will not copy

- No AI courier car, and no NPCs of any kind.
- No random damage, no bullets leaving the barrel instead of the crosshair, no ragdoll escapes, and no Receiver-style
  fumbling.
- No public lobby browser on the shared Spacewar app: friends-only lobbies and invites.
