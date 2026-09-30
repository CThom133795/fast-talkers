# Cloud sessions (Claude Code on the web)

Cloud sessions clone the GitHub repo into a Linux sandbox. Use them for **parallel work on disjoint files**
(a new test suite, a doc, an isolated feature file). Every result comes back as a **PR against `dev`** (see `docs/WORKFLOW.md`),
reviewed and merged by the local lead session. Cloud sessions never export the game and never merge.

## Setup (once per sandbox)
```
bash tools/cloud_setup.sh
export GODOT="$HOME/.godot-4.4.1/Godot_v4.4.1-stable_linux.x86_64"
```
Downloads Godot 4.4.1 (editor only, no export templates), checks `--version`, symlinks `~/bin/godot`, and runs
`--headless --import` once so new `class_name` scripts resolve. Safe to re-run. The `.godot/` cache is not committed,
so a fresh clone needs this step before any test.

## Running tests
```
bash tests/run_all.sh                 # everything, ~8 min: per-suite PASS/FAIL table, non-zero exit on failure
bash tests/run_all.sh vehicle_art chat_ui   # subset
```
Order: vehicle_art, vehicles_06, integration, free_roam, wiring_05, map_interiors, remote_player, chat_ui,
net_lobby_ui, soak, then the two-process net test (skipped in a clone: `tests/run_net_pair.sh` needs a
`../../work` log dir). Each suite has `timeout 170`, because a SCRIPT ERROR in headless Godot hangs forever.
Run a single suite by hand: `timeout 170 "$GODOT" --headless --path . --script res://tests/<suite>.gd`.
Shutdown noise (`Unreferenced static string`, `RID allocations leaked`, `Thread object is being destroyed`) is filtered.

## Rules
- **One owner per file.** Before starting, check open PRs and the claims in `CODEX_HANDOFF.md`; stay inside the files your task names.
- Do **not** touch `scripts/main.gd`, `scripts/online.gd` or `scripts/net.gd` unless the task explicitly says so
  (they are the merge-conflict hot spots and the lead's territory).
- Do not edit `CODEX_HANDOFF.md` or `CLAUDE_HANDOFF.md`; put status in the PR description instead.
- No exports, no downloaded art/audio (the game ships no imported assets), no bots or AI in networked code paths.
- Read `docs/AGENT_BRIEF.md` first (file map, conventions, gotchas).
- Branch from `origin/dev` as `cloud/<task>` (e.g. `cloud/chat-tests`); commit small; never push to `master` or `dev`.
- Open a PR against `dev`. The body must contain: what changed, the files touched, and the pasted
  summary table from `tests/run_all.sh` (or the suites you ran and why a subset is enough).
- If a suite fails and you can't fix it within 3 tries, stop and say so in the PR instead of loosening the test.
