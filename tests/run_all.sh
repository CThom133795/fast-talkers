#!/usr/bin/env bash
# Run every headless suite and print a summary table.
# Usage: bash tests/run_all.sh [suite ...]     (no args = all, in the standard order)
# GODOT: $GODOT, else `godot` on PATH, else ~/.godot-4.4.1/... (see tools/cloud_setup.sh).
# Exit 0 only if every selected suite passed. Two-process net test runs last when no subset is given
# (or when the arg `net_pair` is listed).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"

if [ -z "${GODOT:-}" ]; then
	if command -v godot >/dev/null 2>&1; then GODOT="godot"
	else GODOT="$HOME/.godot-4.4.1/Godot_v4.4.1-stable_linux.x86_64"; fi
fi
export GODOT
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "run_all: Godot not found ('$GODOT'). Run tools/cloud_setup.sh or set GODOT." >&2
	exit 2
fi

ALL="vehicle_art vehicles_06 integration free_roam wiring_05 map_interiors map_06 city_detail city_audit building_landmarks sfx_audio social_features net_security voice voice_perf week_flow stair_walk prefabs city_fill remote_player chat_ui net_lobby_ui soak"
if [ $# -gt 0 ]; then SUITES="$*"; else SUITES="$ALL net_pair"; fi

NOISE='BUG: Unreferenced static string|RID allocations|leaked at exit|Thread object is being destroyed|ObjectDB instances leaked|Pages in use exist at exit|Orphan StringName|WARNING: .*at: (cleanup|~)'
cd "$PROJECT" || exit 2
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SUMMARY=(); FAILED=0

for s in $SUITES; do
	if [ "$s" = "net_pair" ]; then
		if [ ! -f tests/run_net_pair.sh ]; then SUMMARY+=("SKIP  net_pair (tests/run_net_pair.sh missing)"); continue; fi
		echo "=== net_pair ==="
		timeout 170 bash tests/run_net_pair.sh > "$TMP/net_pair.out" 2>&1; rc=$?
		grep -a -v -E "$NOISE" "$TMP/net_pair.out" | tr -d '\r' | tail -n 8
		res="$(grep -a -E 'NET PAIR (PASSED|FAILED)' "$TMP/net_pair.out" | tail -1 | tr -d '\r')"
		[ "$rc" -ne 0 ] && FAILED=1
		SUMMARY+=("$([ "$rc" -eq 0 ] && echo PASS || echo FAIL)  net_pair  exit=$rc  ${res:-no result}")
		continue
	fi
	if [ ! -f "tests/$s.gd" ]; then SUMMARY+=("SKIP  $s (tests/$s.gd missing)"); continue; fi
	extra=""; [ "$s" = "soak" ] && extra="--fixed-fps 60"
	echo "=== $s ==="
	timeout 170 "$GODOT" --headless $extra --path . --script "res://tests/$s.gd" > "$TMP/$s.out" 2>&1; rc=$?
	grep -a -v -E "$NOISE" "$TMP/$s.out" | tr -d '\r' | tail -n 15
	res="$(grep -a 'RESULT' "$TMP/$s.out" | tail -1 | tr -d '\r')"
	if [ "$rc" -ne 0 ] || grep -a -q 'SCRIPT ERROR' "$TMP/$s.out"; then
		FAILED=1; st=FAIL; [ "$rc" -eq 124 ] && res="${res:-TIMEOUT after 170s}"
	else st=PASS; fi
	SUMMARY+=("$st  $s  exit=$rc  ${res:-no RESULT line}")
done

echo
echo "================ SUMMARY ================"
for l in "${SUMMARY[@]}"; do echo "$l"; done
if [ "$FAILED" -ne 0 ]; then echo "OVERALL: FAIL"; exit 1; fi
echo "OVERALL: PASS"
