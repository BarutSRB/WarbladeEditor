#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: $0 --editor-parse|res://path/to/test.gd" >&2
	exit 2
fi

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
godot_binary=${GODOT:-godot}
test_log=$(mktemp)

cleanup() {
	rm -f -- "$test_log"
}

trap cleanup EXIT INT TERM

set +e
if [ "$1" = "--editor-parse" ]; then
	"$godot_binary" --headless --path "$project_root" --editor --quit >"$test_log" 2>&1
else
	"$godot_binary" --headless --path "$project_root" --script "$1" >"$test_log" 2>&1
fi
test_status=$?
set -e

sed -n '1,$p' "$test_log"

if [ "$test_status" -ne 0 ]; then
	exit "$test_status"
fi

if command -v rg >/dev/null 2>&1; then
	if rg -q '^(SCRIPT ERROR|ERROR):' "$test_log"; then
		exit 1
	fi
else
	if grep -Eq '^(SCRIPT ERROR|ERROR):' "$test_log"; then
		exit 1
	fi
fi
