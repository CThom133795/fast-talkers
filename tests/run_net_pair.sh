#!/usr/bin/env bash
# Two-process network test (docs/NET_M1_SPEC.md section 5).
# Usage: tests/run_net_pair.sh [port] [steps]      (defaults: 24651, lobby)
# Logs: ../../work/net-host.log and ../../work/net-client.log. Exit 0 only if both RESULT lines show 0 failures.
# Only the Godot processes started here are killed (by PID, with their child tree); other agents' Godot runs are left alone.
PORT="${1:-24651}"
STEPS="${2:-lobby}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$HERE/.." && pwd)"
# Local checkout: logs go to ../../work next to the portable Godot. Cloud clone: a temp dir,
# and Godot from $GODOT, PATH or the cloud_setup.sh install.
if [ -d "$PROJECT/../../work" ]; then
	WORK="$(cd "$PROJECT/../../work" && pwd)"
	DEFAULT_GODOT="$WORK/tools/godot/Godot_v4.4.1-stable_win64_console.exe"
else
	WORK="$(mktemp -d)"
	DEFAULT_GODOT="$(command -v godot || echo "$HOME/.godot-4.4.1/Godot_v4.4.1-stable_linux.x86_64")"
fi
GODOT="${GODOT:-$DEFAULT_GODOT}"
HOST_LOG="$WORK/net-host.log"
CLIENT_LOG="$WORK/net-client.log"
LIMIT="${NET_PAIR_LIMIT:-70}"   # hard per-process cap in seconds (the scripts' own watchdog fires at 45 s, 120 s with the round step)
case ",$STEPS," in *,round,*|*,phone,*) LIMIT="${NET_PAIR_LIMIT:-140}" ;; esac

HOST_PID=""; CLIENT_PID=""

kill_tree() {  # $1 = msys pid
	local pid="$1" winpid=""
	[ -z "$pid" ] && return
	if [ -r "/proc/$pid/winpid" ]; then winpid="$(cat "/proc/$pid/winpid")"; fi
	if [ -n "$winpid" ]; then
		MSYS2_ARG_CONV_EXCL='*' taskkill /PID "$winpid" /T /F >/dev/null 2>&1
	fi
	kill -9 "$pid" >/dev/null 2>&1
}
cleanup() { kill_tree "$HOST_PID"; kill_tree "$CLIENT_PID"; }
trap cleanup EXIT INT TERM

run_role() {  # $1 = role, $2 = log
	"$GODOT" --headless --path "$PROJECT" --script res://tests/net_pair.gd -- \
		--role="$1" --port="$PORT" --steps="$STEPS" > "$2" 2>&1 &
}

: > "$HOST_LOG"; : > "$CLIENT_LOG"
echo "net_pair: port $PORT, steps '$STEPS'"
run_role host "$HOST_LOG";     HOST_PID=$!
sleep 1.5
run_role client "$CLIENT_LOG"; CLIENT_PID=$!

# Wait for both (own timeout so we can kill by PID).
start=$SECONDS
while kill -0 "$HOST_PID" 2>/dev/null || kill -0 "$CLIENT_PID" 2>/dev/null; do
	if [ $((SECONDS - start)) -ge "$LIMIT" ]; then
		echo "net_pair: hard timeout after ${LIMIT}s, killing what is left"
		cleanup
		break
	fi
	sleep 0.5
done
wait "$HOST_PID" 2>/dev/null; HOST_RC=$?
wait "$CLIENT_PID" 2>/dev/null; CLIENT_RC=$?
HOST_PID=""; CLIENT_PID=""

HOST_RESULT="$(grep -a 'NET PAIR HOST RESULT' "$HOST_LOG" | tail -1 | tr -d '\r')"
CLIENT_RESULT="$(grep -a 'NET PAIR CLIENT RESULT' "$CLIENT_LOG" | tail -1 | tr -d '\r')"
echo "${HOST_RESULT:-NET PAIR HOST RESULT: MISSING (see $HOST_LOG)}"
echo "${CLIENT_RESULT:-NET PAIR CLIENT RESULT: MISSING (see $CLIENT_LOG)}"

FAILED=0
for line in "$HOST_RESULT" "$CLIENT_RESULT"; do
	case "$line" in
		*" 0 failures"*) ;;
		*) FAILED=1 ;;
	esac
done
[ "$HOST_RC" -ne 0 ] && FAILED=1
[ "$CLIENT_RC" -ne 0 ] && FAILED=1
if [ "$FAILED" -ne 0 ]; then
	echo "NET PAIR FAILED (host rc=$HOST_RC, client rc=$CLIENT_RC). Failing lines:"
	grep -a -h -E 'FAIL|SCRIPT ERROR|WATCHDOG' "$HOST_LOG" "$CLIENT_LOG" | tr -d '\r' | sort -u | head -20
	exit 1
fi
echo "NET PAIR PASSED"
exit 0
