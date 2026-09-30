# How we work: branches, owners and handoffs (Claude Desktop, Codex, Claude Cloud)

Set up by Claude Desktop (lead), 2026-09-30, at the user's request ("a clean working path for You/Codex/Claude
Cloud in GitHub"). Every agent reads this before its first commit. Repo: private `CThom133795/fast-talkers`.

## Branches

| Branch | What it is | Who writes to it |
|---|---|---|
| `master` | Stable. It only moves when **the user** merges a tested `dev` into it. | The user only. Agents never push, merge or open PRs into `master`, except the single standing `dev → master` PR described below. |
| `dev` | The integration branch. Every PR targets `dev`. Playtest builds are cut from it. | Claude Desktop (lead) merges reviewed PRs. |
| `cloud/<task>` | One Claude Cloud task (a Linux sandbox; no Windows, GPU, Steam or export). | That cloud session. |
| `codex/<task>` | One Codex task. | Codex. |
| `lead/<task>` | Claude Desktop's own work, when it is too big to commit straight to `dev`. | Claude Desktop. |

- Branch from the tip of `dev`: `git fetch origin && git switch -c cloud/<task> origin/dev`.
- One task per branch, small commits, then a PR into `dev` whose body has:
  - what changed;
  - the files touched;
  - the test summary (`bash tests/run_all.sh`, or on Windows `Run Tests.cmd`).
- Before a PR, merge `origin/dev` into your branch so the lead gets no conflicts. Never rebase a branch someone
  else has pulled.
- **Retired branches** (all merged into `dev`; kept for history; the lead may delete them once the user says so):
  - `cloud/map-m1`
  - `cloud/map-integration` (PR #1)
  - `cloud/overnight-heavy-lift` (PR #2)
  - `lead/week-w0`

## Who owns which files

One writer per file at a time. Claim files in your handoff file (below) before you edit them.

- **Lead-only hot spots:** `scripts/main.gd`, `scripts/online.gd`, `scripts/net.gd`, `scripts/steam_transport.gd`,
  `project.godot`, `export_presets.cfg`. A task may name one of them explicitly. If it doesn't, propose the change
  as a documented hook in your PR instead.
- **Everything that moves money or items** is host-validated in `online.gd`/`net.gd`. Clients ask; the host decides.
- **Art and world files** (`world.gd`, `city_detail.gd`, `buildings/*`, `car.gd`, `vehicle_kit.gd`, `sfx.gd`): one
  owner per task. Parallel tasks must touch disjoint files.

## Handoffs (there is no direct messaging between agents)

- `CLAUDE_HANDOFF.md` carries notes **to** Claude from Codex or the user.
- `CODEX_HANDOFF.md` carries notes **to** Codex from Claude.
- Each agent appends dated entries to its own outgoing file only.
- On a long pass, write an **IN PROGRESS** entry first and tick items as they land, so a session that runs out of
  usage can resume.
- Cloud sessions don't edit either file. Their PR description is their handoff.
- Design truth lives in:
  - `docs/GAME_VISION.md` (the user's decisions);
  - `docs/LEAD_DESIGN_DECISIONS.md` (the lead's choices);
  - `docs/DESIGN_WEEK_TRUST.md` (the trust systems plan).

## Tests are the contract

- Every suite must stay green on the target branch. A PR that fails a suite doesn't merge.
- Fix the code, or explain the failure in the PR. Never loosen a check to make it pass.
- New gameplay rules get headless checks (for example `tests/week_flow.gd` for the Week). Host rules get a
  `net_pair` step when they cross the network.
- Linux: `bash tests/run_all.sh`. Windows: `Run Tests.cmd`, then
  `powershell -File tests\run_net_pair.ps1 -Steps lobby,round`.

## Builds

- Only Claude Desktop, on the user's Windows PC, exports.
- The friends' playtest zip: `powershell -ExecutionPolicy Bypass -File tools\build_playtest.ps1`. It writes
  `..\Fast Talkers Playtest.zip` and never overwrites the user's own `..\play-fast-talkers` exe.
- Bump `config/version` in `project.godot` for every build you hand to other people. Different versions refuse to
  join each other, by design.
- `addons/godotsteam` (the GodotSteam 4.22.1 GDExtension, win64 and linux64 only) and `steam_appid.txt` (480,
  Valve's Spacewar test app) are committed on purpose, so every checkout can host on Steam.
  - Steam is off in headless runs.
  - A release build needs its own App ID, with `steam_appid.txt` removed.
