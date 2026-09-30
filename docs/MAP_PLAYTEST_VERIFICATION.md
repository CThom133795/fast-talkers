# Expanded map playtest verification

Built September 29, 2026, from the existing Fast Talkers project on `cloud/map-integration`. The branch retains multiplayer master `b6d4a06` and map source commit `420f7e7`. The original exported game is unchanged.

| Check | Result |
|---|---|
| Contract integration | 66/66 |
| Free roam | 137/137 |
| Map gameplay wiring | 18/18 |
| Map/interiors | 97/97 |
| Map 0.6 acceptance/determinism | 150/150 |
| Vehicle art | 52/52 |
| Vehicle behavior/settings | 24/24 |
| Remote player | 71/71 |
| Chat | 46/46 |
| Network lobby | 84/84 |
| Two-process online lobby/round | host 67/67, client 62/62 |
| Chaos soak | 6,000 frames, completed without script errors |
| Windows export | completed |
| Exported executable startup | completed, exit 0 |
| Render review | aerial and gun-store exterior/interior/mode views inspected |

Total: 874 passing assertions plus the soak, export and startup checks. The vehicle save/load assertions first failed because the restricted test process could not write its temporary settings file. A rerun with that access passed all 24 checks. Several restricted Godot runs logged a non-fatal root-certificate-store error; they still completed their checks.

GPU sampling on this machine found approximately 73–125 fps in sampled street views. The planned draw-call limit (~1,550) is not met everywhere: Midtown 1,744; north long view 2,044; Motor Mile 1,694; gun store 1,591; Exchange interior 1,695. These are local samples, not a performance guarantee for other PCs.

Most new landmark interiors are M1 placeholders. Working M2 lifts, native voice and public matchmaking are not included. Trust/restitution suggestions are documented separately and not implemented. Real internet play and more than two human players remain playtest tasks.

Executable SHA-256:
2364CBD81D0C19C06C83691C135C4C3E497AC255D3776E3533438637765B3835
