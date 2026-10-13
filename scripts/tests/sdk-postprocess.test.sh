#!/usr/bin/env bash
# Tests for sdks/postprocess_typescript.py and its wiring in sdks/generate.sh.
#
# Python 3 stdlib only: unittest for the cases, and the `trace` module to measure
# line coverage, so CI needs no coverage.py and no new dependency. The module must be
# covered line for line (100%); an uncovered line fails this script.
#
# Run from the repo root: bash scripts/tests/sdk-postprocess.test.sh
set -euo pipefail
# The suite imports the module from sdks/; do not leave bytecode behind in the tree.
export PYTHONDONTWRITEBYTECODE=1

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
MODULE="$ROOT/sdks/postprocess_typescript.py"
SUITE_DIR="$ROOT/sdks/tests"

COVER=$(mktemp -d)
trap 'rm -rf "$COVER"' EXIT

STDLIB=$(python3 -c 'import sysconfig; print(sysconfig.get_paths()["stdlib"])')

echo "== unit tests"
# Run on their own first: `python3 -m trace` swallows the exit code of the program
# it traces, so a failing test would pass silently if it only ran under tracing.
python3 -m unittest discover -s "$SUITE_DIR" -p "test_*.py"

echo "== line coverage"
python3 -m trace --count --missing --coverdir="$COVER" --ignore-dir="$STDLIB" \
  --module unittest discover -s "$SUITE_DIR" -p "test_*.py" >/dev/null

REPORT="$COVER/postprocess_typescript.cover"
if [ ! -f "$REPORT" ]; then
  echo "FAIL: no coverage report for $MODULE" >&2
  exit 1
fi

# `trace --missing` marks executable lines that never ran with ">>>>>>".
MISSED=$(grep -c '^>>>>>>' "$REPORT" || true)
TOTAL=$(grep -cE '^ *[0-9]+: |^>>>>>>' "$REPORT" || true)
# A gate that measured nothing must not go green: zero lines means the report
# format changed or the module was never traced.
if [ "$TOTAL" -eq 0 ]; then
  echo "FAIL: no executable lines were measured in postprocess_typescript.py" >&2
  exit 1
fi
if [ "$MISSED" -ne 0 ]; then
  echo "FAIL: $MISSED of $TOTAL executable lines in postprocess_typescript.py are not covered:" >&2
  grep -n '^>>>>>>' "$REPORT" >&2
  exit 1
fi
echo "ok: $TOTAL of $TOTAL executable lines covered (100%)"

echo "== generate.sh runs the module, not an inline copy"
if ! grep -q 'postprocess_typescript.py' "$ROOT/sdks/generate.sh"; then
  echo "FAIL: sdks/generate.sh does not call postprocess_typescript.py" >&2
  exit 1
fi
if grep -q 'def unescape_comments' "$ROOT/sdks/generate.sh"; then
  echo "FAIL: sdks/generate.sh still carries an inline copy of the post-processing" >&2
  exit 1
fi
echo "ok"
