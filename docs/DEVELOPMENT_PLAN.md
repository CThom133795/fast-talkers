# Project Fast Talkers — production direction

## Design contract

An original small-team social shooter about profitable deals and fragile trust. A gunfight should
be a costly interruption to a deal, not the only source of progress. Roads make travel, interception,
escape and vehicle ownership matter. There are three companies of four in standard matches;
the large format has four companies of six. Both counts are targets, not supported modes yet.

Reference roles are separate: Sub Rosa / No Big Deal inform human negotiation and physical trade;
GTA IV informs vehicle inertia and readable weight; Battlefield / BattleBit inform responsive aiming
and feedback; Reforger informs grounded stances and movement; CS2 informs equipment commitment
and round economy. We will evaluate each against explicit tests instead of claiming parity.

## Original direction to test

Working fiction: late-1990s contractors exchange confidential corporate documents in an industrial
district. A briefcase has different value to different companies. The tension comes from discovering
who needs what, negotiating prices, verifying a case, and deciding whether to trust the handover.
Future ideas include receipts, escrow and public contract outcomes. None is implemented in 0.1.
Start with one document type, one sedan and one district until the human interaction is fun.

## Milestones and exit criteria

### 0 — Offline handling laboratory (this build)

Buy, walk/aim/fire, drive, complete paid and hostile routes, lose and restart. Tune from hands-on
feedback. Done means the loop is reproducible and has no blocking physics/input bugs; it does not
mean driving, weapon balance or art are final. Automated integration checks cover state and physics;
human testing must assess feel and clarity.

### 1 — Authoritative two-client LAN slice

Server owns round clock, money, purchases, weapon inventory, damage, car seats and briefcase owner.
Clients send bounded input and requests, not final balances or damage. Add predicted local movement,
reconciliation, remote interpolation, sequenced weapon commands and a carefully limited hit-history
window. A reliable event stream covers purchases and objective transfers; snapshots carry motion.

Exit: two clients can join, buy, drive, trade, shoot and finish a round. Simultaneous pickup/seat
requests have exactly one winner; double submission never duplicates cash or items; reconnect and
disconnect release occupied seats/cases. Invalid requests are rejected. Test delayed/lost packets.
Offline menus must stop pausing the whole simulation once network sessions exist.

### 2 — Twelve-player social test

Three companies, distinct color/silhouette, proximity voice with push-to-talk and mute controls,
team communication, useful negotiation UI, one objective economy, spectator flow and rematch.
Avoid general procedural destruction or ragdoll-driven locomotion while responsiveness is unresolved.

Exit: full matches with 12 people remain understandable and stable; trade beats farming kills;
players can hear nearby negotiations and reliably distinguish team members. Gather consent-based
playtest observations and local performance metrics, not unnecessary personal data.

### 3 — Driving and combat refinement

Replace the kinematic car with a tuned custom suspension/tire model only if it improves the feel.
Tune weight transfer, damping, grip curves, steering input, collision energy, braking and low-speed
curb handling on a dedicated test track. Keep collision prediction and correction in the design.
Tune ADS timing, sight alignment, sprint transitions, recoil, cadence, hit feedback, muzzle obstruction
and reload readability. Build authored animation and audio only after the mechanic is validated.

Exit: repeated slalom, braking, corner-entry, curb and collision tests produce stable readable outcomes.
At 60 FPS, input and visual feedback have consistent timing. Network correction does not destroy feel.

### 4 — Twenty-four-player stress test and low-end tuning

Four companies of six, larger objective placement and sufficient routes/cover. Profile client CPU/GPU,
server frame time, bandwidth, voice cost and memory. Batch static geometry and cap audio/particles.
Use occlusion and distance detail where measurements justify them. Validate 12 first; 24 is not a
free player-count switch when the map, voice and economy need to remain readable.

### 5 — Steam release candidate

Create an original final name/identity and audit asset licenses. Prepare a complete store page,
Windows build, controls/help, settings persistence, supported-hardware matrix, crash reporting choice,
community/abuse tools, privacy disclosures for any online services, and tested install/update behavior.
Add Steam lobbies/invites and chosen transport only after LAN authority is reliable. Review current
Steamworks onboarding, store/build review and release requirements at that time. No account creation,
purchase, store publication or release submission has been performed in this task.

## Performance targets, not tested minimum requirements

Start at 1280×720, 60 FPS target, Compatibility renderer, 8 GB RAM target, modest integrated GPU
with OpenGL 3.3. Keep post-processing simple, one shadowed sun, short shadow range, low material
counts and no real-time global illumination. Aim for <1 GB packaged content early; benchmark before
advertising minimum specs. A 3080 render check only proves this build renders on that machine.

## 75 GB development storage allocation

| Category | Ceiling |
|---|---:|
| Engines, Blender and essential tools | 5 GB |
| Editable game source and original assets | 10 GB |
| Import/build caches | 8 GB |
| Recent test/release builds | 7 GB |
| Version history and local recovery copies | 10 GB |
| Playtest recordings/reference captures | 5 GB |
| Unallocated headroom | 30 GB |

These are budget ceilings. The current procedural build is far smaller. Avoid downloading large
asset packs, all-platform SDKs or multiple engine versions casually. Keep captures short; delete only
verified generated caches/archive copies, never unique source or uncommitted work. Off-device backups
remain desirable once original assets accumulate. Git LFS is an option for large source art later.

## Immediate human playtest questions

1. Is the sedan too slow to turn, too slippery, too light or too stable? Test one change at a time.
2. Are walking, sprinting, crouching and ADS comfortable, and is there unwanted input delay?
3. Can a new player locate the car, deal and delivery without instructions from the developer?
4. Is peaceful profit enough to make paying interesting when robbery remains possible?
5. Which part feels most like the intended game, and which most urgently breaks the illusion?

Claude's multiplayer design should refine the first network milestone while Codex incorporates
handling feedback. Keep shared contracts and file ownership explicit in CLAUDE_HANDOFF.md.
