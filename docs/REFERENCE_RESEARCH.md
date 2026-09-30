# Social negotiation shooter — reference notes

Reviewed September 29, 2026. Complements `LOOP_ANALYSIS.md`, `MULTIPLAYER_DESIGN.md` and the map plan. No published internal design document was located for either reference. The sources below are a creator interview and an official game description; older community-derived mechanical details in our existing notes still require separate verification.

## What the sources establish

In a [2015 interview with Sub Rosa creator Alex Austin](https://www.gamedeveloper.com/design/creating-the-right-kind-of-player-in-the-weird-fps-i-sub-rosa-i-), he describes using communication, inspectable briefcases and economic consequences to create uncertainty around transactions. He wanted players to have reasons to hesitate before shooting. Calls let opposing groups negotiate before meeting; a case can hide misleading contents. This is historical design intent, not verification of today's Steam build.

[No Big Deal's official Roblox description](https://www.roblox.com/games/18112334178/No-Big-Deal) presents a round-based business-negotiation shooter where coworkers cooperate to gain capital through deals, ambushes and negotiation. It encourages roleplay and voice communication, and warns that unfamiliar players may find the game confusing. It does not publish a complete economy, mission specification or trust system.

## Application to Fast Talkers

Our interpretation: the genre is a social negotiation shooter. The gun changes the terms of a conversation; it need not be the preferred solution to every problem. Valuable physical objectives, transport, inspection, communication and banking give a meeting its stakes. Reliable controls and understandable consequences should let the funny stories come from people.

The current code already has physical Ledger/cash cases, buyer/seller roles, case pickup/drop/banking, crew calling through chat channels, vehicles, no direct kill bounty, and a clean-deal bonus. Preserve those foundations. This map pass adds fair travel distances and alternative approaches; it does not add new deal economics or trust mechanics.

## Proposed only: reasons to trade and ways to recover trust

The user explicitly requested suggestions, not implementation. None of the ideas below is shipped in this playtest.

- **A positive-sum reliable trade.** Both sides can profit from an honest exchange. Model robbery's expected payoff against transport risk, deaths, recovery costs and future partners; simply making the bonus huge could reward farming arranged trades. Existing clean-deal behavior is the baseline to measure.
- **A bounded restitution offer.** A crew can offer funds, return an item, or voluntarily take worse terms on a subsequent transaction. The recipient explicitly accepts or refuses. Settlement is host-verified and cannot create money or undo mission results.
- **Remember acts, not a magical trust score.** A match-only history can record that a crew broke an agreement, paid restitution, and subsequently honored a deal. Compensation is evidence of repair, not a reset of the betrayal. Avoid inferring intent from every kill or making the record a global permanent blacklist.
- **Earn credibility with a limited commitment.** A deposit or small joint task can let rivals test cooperation without trusting everything at once. Parties select the arrangement. It should not automatically make ambushes impossible.
- **Keep a comeback affordable.** A bad round should hurt without making a crew irrelevant for the rest of the session. Assess recovery alongside survivor gear, wages and the current bank values before changing numbers.

Measure whether honest trade is attractive before introducing reputation penalties. A design that punishes all conflict removes the uncertainty the game needs; one that pays almost exclusively for betrayal becomes deathmatch with cases. Restitution should restore possibilities for conversation while preserving the other team's right to remain suspicious.

## Next human playtest

Play one honest transaction and one contested transaction, choosing different meeting places/routes. Ask each player what they owned, what they wanted, how they arranged the meeting, and why they chose cooperation or betrayal. Then ask whether an in-game compensation offer would have changed their next choice. This tests the design before adding a system.

Use an external voice call for this build: native proximity voice and public matchmaking are still open work. Validate the feeling of another round with a small group before optimizing for public discovery or a Steam launch.
