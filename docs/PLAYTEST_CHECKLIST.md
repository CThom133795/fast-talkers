# Playtest checklist — prototype 0.4 (read this section first)

Thirty minutes. Tick what works; one line per "feel" question. Numbers beat adjectives.

## 0.4 — what changed and what to judge

1. **Controller in menus.**
   - [ ] On the title, pause, buy and settings menus: D-pad or stick moves, **A** selects, **B** goes back,
     and **LB/RB** switch buy tabs.
2. **Buy phase** (Contract).
   - [ ] 25 s at your HQ, doors locked, gun holstered. B opens the buy menu.
   - [ ] Buy, sell back, and swap a gun in a slot. Too short or too long? ____ s feels right.
   - [ ] Survive a round and your gear carries over; die and you restart with the P9. Does that feel fair?
3. **Weapons.** In Free Roam, press 1–5 and then the same key again to cycle models.

| Weapon | Sights on target? | Recoil too much / right / too little | Sounds distinct? | Would you buy it? |
|---|---|---|---|---|
| P9 / .45 / .357 | | | | |
| VK-5 / MAC-11 / Tommy | | | | |
| M4 / KV-47 | | | | |
| 870 / Sawn-off / Auto-12 | | | | |
| M700 / BR-58 | | | | |

   - [ ] Does the KV-47 feel like a harder-hitting, harder-to-control rifle than the M4?

4. **Vehicles.**
   - [ ] Drive each type: sedan, coupe, SUV, pickup and motorcycle. Which handles best and which worst?
   - [ ] **F** on a car you are next to: ride as a gunner. The practice wheelman drives the ring road.
     - Shoot from the window, the pickup bed and the back of the bike.
     - Are the fire arcs sensible?
   - [ ] At the wheel, hold RMB (pad: LB) to lean out, and fire with LMB (pad: RB). Is steering while shooting
     manageable?
   - [ ] Shoot a parked car until it smokes and dies. Crash a bike hard and see if you get thrown.
5. **Map.**
   - [ ] Press M. Does the island city with bridges read clearly?
   - [ ] Drive HQ → Exchange → HQ for your crew: ____ s.
   - [ ] Do the bridges feel like real chokepoints?
6. **Characters.**
   - [ ] The title lineup, the bots and the drivers: are they still too cartoonish? What would push them
     further?
7. **Street tips.**
   - [ ] A payphone rings in a contract round. Answer it, grab the stash, bank it. Worth the detour?

Performance: note FPS in Midtown, at the beach and while driving: ____ / ____ / ____

---

# Playtest checklist — prototype 0.2 (older)

Twenty-minute session. Tick what works, and jot one line per "feel" question. Numbers beat adjectives:
"the SMG climbs about a head-height per second" is more useful than "the SMG feels off".

## 1. First boot (2 min)

- [ ] Title screen shows a slow orbit of the district; menu text fits without scrolling on your screen.
- [ ] Esc > Controls & Settings: change volume, sensitivity, FOV, shadows. Quit and relaunch: settings stuck.
- [ ] F11 toggles fullscreen; F3 shows FPS. Note your FPS at the armory and while driving: ____ / ____

## 2. Free Roam — the arsenal (8 min)

For each weapon, fire from the hip, then aim down sights, at the 12 m dummies.

| Weapon | Sights line up with impacts? | Recoil too much / right / too little | Sound punchy? | Notes |
|---|---|---|---|---|
| 1 Pistol | | | | |
| 2 SMG | | | | |
| 3 Carbine | | | | |
| 4 Shotgun | | | | |
| 5 Marksman (scope) | | | | |

- [ ] Swapping weapons (1-5, wheel, Q) feels quick; ammo in each magazine is remembered.
- [ ] Shotgun reload loads one shell at a time; pulling the trigger mid-reload fires.
- [ ] Plate rack: best time ____ s. Did plates fall/reset clearly? Too fast / too slow to reset?
- [ ] Long range (street south of the yard): can you hit the 67 m plate with the marksman? Scope sensitivity OK?
- [ ] Hit markers: white = hit, gold = head shot, red = kill/drop. Readable?
- [ ] Walking/sprinting/crouching: any input delay or floatiness? Head-bob or sway distracting?

## 3. Free Roam — security (4 min)

- [ ] Walk up to the exchange: guards watch you but stay calm.
- [ ] Shoot one: the squad raises weapons, strafes, returns fire; red arcs show where shots come from.
- [ ] Taking cover or crouching makes you noticeably harder to hit. Fights feel fair? Too easy / too hard?
- [ ] Die on purpose: you respawn at the armory and security stands down.

## 4. Cars (4 min)

- [ ] Get into each colour of sedan (E). The mouse orbits the camera and it recentres.
- [ ] Engine note rises and shifts gear; brake lights glow; handbrake leaves tyre marks and smoke.
- [ ] Hit a wall at speed: crash sound and camera shake. Car ever stuck, launched or clipping?
- [ ] Handling (from the development plan): too slow to turn / too slippery / too light / too stable?

## 5. Contract mode (2 min)

- [ ] Buy a primary; keys 1-5 switch between it and the pistol only.
- [ ] Pay route and robbery route both complete; payouts match the result screen.
- [ ] The armory rack refuses to rearm during a contract.

## 6. Open questions for the next pass

1. Which single weapon feels best, and which feels worst? Why?
2. Should free-roam security be tougher (more damage, longer range) or is "neutral until provoked" right?
3. Anything that broke the illusion (floating objects, pops, text overlap, sounds that grate)?
4. What would you most like next: more city, better driving, the first multiplayer slice, or negotiation UI?

## Later — networked playtests (not built yet)

Not applicable until the authoritative LAN slice exists (see DEVELOPMENT_PLAN.md milestone 1). When it does,
repeat sections 2–5 with two clients at 0 ms, then with 100 ms latency and 2 % packet loss, and check:
simultaneous pickups/seat entries have one winner; hits and money never duplicate; a disconnect frees the
car seat and the briefcase; remote players move smoothly; your own aim and movement never rubber-band.
