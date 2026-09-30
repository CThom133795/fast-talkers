#!/usr/bin/env bash
# Windowed two-instance visual smoke test. Saves screenshots to the out dir (default ../../work/captures/net).
# Usage: tests/run_net_visual.sh [port] [outdir]      (defaults: 24700, <work>/captures/net)
# Logs: <work>/net-visual-host.log and net-visual-client.log. Only the Godot processes started here are killed.
PORT="${1:-24700}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
WORK="$(cd "$PROJECT/../../work" && pwd)"
OUT="${2:-$WORK/captures/net}"
mkdir -p "$OUT"
OUT_WIN="$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")"
GODOT="${GODOT:-$WORK/tools/godot/Godot_v4.4.1-stable_win64_console.exe}"
HOST_LOG="$WORK/net-visual-host.log"
CLIENT_LOG="$WORK/net-visual-client.log"
LIMIT="${NET_VISUAL_LIMIT:-170}"

HOST_PID=""; CLIENT_PID=""
kill_tree() {
	local pid="$1" winpid=""
	[ -z "$pid" ] && return
	if [ -r "/proc/$pid/winpid" ]; then winpid="$(cat "/proc/$pid/winpid")"; fi
	if [ -n "$winpid" ]; then MSYS2_ARG_CONV_EXCL='*' taskkill /PID "$winpid" /T /F >/dev/null 2>&1; fi
	kill -9 "$pid" >/dev/null 2>&1
}
cleanup() { kill_tree "$HOST_PID"; kill_tree "$CLIENT_PID"; }
trap cleanup EXIT INT TERM

run_role() {  # $1 = role, $2 = log, $3 = window position
	"$GODOT" --path "$PROJECT" --resolution 1280x720 --position "$3" --script res://tests/net_visual.gd -- \
		--role="$1" --port="$PORT" --out="$OUT_WIN" > "$2" 2>&1 &
}

: > "$HOST_LOG"; : > "$CLIENT_LOG"
echo "net_visual: port $PORT, out $OUT_WIN"
run_role host "$HOST_LOG" 0,0;        HOST_PID=$!
sleep 2
run_role client "$CLIENT_LOG" 660,40; CLIENT_PID=$!

start=$SECONDS
while kill -0 "$HOST_PID" 2>/dev/null || kill -0 "$CLIENT_PID" 2>/dev/null; do
	if [ $((SECONDS - start)) -ge "$LIMIT" ]; then
		echo "net_visual: hard timeout after ${LIMIT}s, killing what is left"
		cleanup
		break
	fi
	sleep 0.5
done
wait "$HOST_PID" 2>/dev/null; wait "$CLIENT_PID" 2>/dev/null
HOST_PID=""; CLIENT_PID=""
grep -a -h -E 'NET VISUAL|WATCHDOG|SCRIPT ERROR|WARN:' "$HOST_LOG" "$CLIENT_LOG" | tr -d '\r' | sort -u
ls "$OUT"
