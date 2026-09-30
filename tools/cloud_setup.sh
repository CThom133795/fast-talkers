#!/usr/bin/env bash
# Cloud-session setup for Fast Talkers: installs Godot 4.4.1 (editor build, no export templates) and
# primes the class cache. Idempotent. Usage: bash tools/cloud_setup.sh   (any cwd)
set -euo pipefail

VERSION="4.4.1"
DIR="$HOME/.godot-$VERSION"
BIN="$DIR/Godot_v${VERSION}-stable_linux.x86_64"
URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable/Godot_v${VERSION}-stable_linux.x86_64.zip"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -x "$BIN" ]; then
	echo "cloud_setup: downloading Godot $VERSION to $DIR"
	mkdir -p "$DIR"
	ZIP="$DIR/godot.zip"
	if command -v curl >/dev/null 2>&1; then
		curl -fL --retry 3 -o "$ZIP" "$URL"
	else
		wget -q -O "$ZIP" "$URL"
	fi
	if command -v unzip >/dev/null 2>&1; then
		unzip -o -q "$ZIP" -d "$DIR"
	else
		python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$ZIP" "$DIR"
	fi
	rm -f "$ZIP"
	chmod +x "$BIN"
else
	echo "cloud_setup: Godot $VERSION already present at $BIN"
fi

VER_OUT="$("$BIN" --version 2>/dev/null | head -1 | tr -d '\r')"
case "$VER_OUT" in
	"$VERSION".*) echo "cloud_setup: version OK ($VER_OUT)" ;;
	*) echo "cloud_setup: unexpected Godot version '$VER_OUT' (wanted $VERSION)" >&2; exit 1 ;;
esac

# Optional convenience symlink: $HOME/bin/godot
if mkdir -p "$HOME/bin" 2>/dev/null; then
	ln -sf "$BIN" "$HOME/bin/godot"
	echo "cloud_setup: symlinked $HOME/bin/godot (add \$HOME/bin to PATH if needed)"
fi

# One-time import so new class_name scripts resolve (the .godot/ cache is not committed).
echo "cloud_setup: importing project (class cache) from $REPO"
cd "$REPO"
timeout 300 "$BIN" --headless --import --path . >/dev/null 2>&1 || echo "cloud_setup: import exited non-zero (usually harmless shutdown noise)"

echo
echo "Done. Use it with:"
echo "  export GODOT=\"$BIN\""
echo "  bash tests/run_all.sh            # all suites"
