#!/bin/sh
# Regenerates the three BEAI SDKs from api/openapi.v1.json. Generated output is
# never hand-edited: change the spec (or this script), then rerun.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SPEC="$ROOT/api/openapi.v1.json"
VERSION=$(tr -d '[:space:]' < "$ROOT/api/VERSION")

if [ ! -f "$SPEC" ]; then
  echo "ERROR: $SPEC not found" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The generator CLI is a locked dependency (tools/openapi-generator/bun.lock),
# never a floating `bunx pkg@version`. The jar it downloads is pinned in
# sdks/openapitools.json.
(cd "$ROOT/tools/openapi-generator" && bun install --frozen-lockfile >/dev/null)
GENERATOR="$ROOT/tools/openapi-generator/node_modules/.bin/openapi-generator-cli"

cd "$ROOT/sdks"

# Inline schemas are named after their position (`..._progress_inner`) or after the
# first operation that uses them (`..._exports_index_400_response`), which reads
# wrongly everywhere else. Give them names that say what they are, in all three
# SDKs. The keys are the generator's own inline names, so a generator upgrade that
# renames them fails the check after the typescript step instead of silently
# shipping the old names.
INLINE_NAMES="\
PublicInterview_progress_inner=PublicInterviewProgressCompetency,\
PublicInterview_progress_inner_answers_inner=PublicInterviewProgressAnswer,\
public_api_exports_index_400_response=PublicProblem,\
public_api_exports_index_400_response_errors_inner=PublicProblemError,\
public_api_webhooks_deliveries_index_200_response_data_inner=PublicWebhookDelivery,\
public_api_exports_index_200_response_data_inner=PublicExport,\
inline_object=PublicMessageError"

# Skip docs and tests: they multiply the tree size without adding runtime code.
SKIP="apiTests=false,modelTests=false,apiDocs=false,modelDocs=false"

generate() {
  name=$1
  spec=$2
  shift 2
  rm -rf "$name"
  "$GENERATOR" --openapitools ./openapitools.json generate \
    -i "$spec" -o "$name" --global-property "$SKIP" \
    --inline-schema-name-mappings "$INLINE_NAMES" "$@" >/dev/null
  # Generator bookkeeping that embeds nothing useful and churns diffs.
  rm -rf "$name/.openapi-generator" "$name/.openapi-generator-ignore" "$name/git_push.sh"
  # CI templates for a standalone package repo: unused here, and the nested
  # workflow would contradict the wrapper's SHA-pinning standard.
  rm -rf "$name/.github" "$name/.travis.yml" "$name/.gitlab-ci.yml"
  echo "generated sdks/$name"
}

# Generator 7.25.0 mishandles a schema typed `null` (the api's `errors: null`
# problem details): python aborts and typescript-fetch imports a missing
# `./Null` model. Feed all three a `["string", "null"]` equivalent (the spec is
# OpenAPI 3.1, where `nullable` is not a keyword).
python3 - "$SPEC" "$TMP/openapi.json" <<'PY'
import json
import sys


def fix(node):
    if isinstance(node, dict):
        if node.get("type") == "null" and len(node) == 1:
            node.clear()
            node.update({"type": ["string", "null"]})
        for value in list(node.values()):
            fix(value)
    elif isinstance(node, list):
        for value in node:
            fix(value)


with open(sys.argv[1]) as source:
    spec = json.load(source)
fix(spec)
with open(sys.argv[2], "w") as target:
    json.dump(spec, target, indent=2, sort_keys=True)
PY

# Fails when a mapped inline schema did not become the model it was named after:
# a generator upgrade that renames its inline schemas must stop here, in the SDK
# where it happened, instead of silently shipping the old names.
require_models() {
  sdk=$1
  for pair in $(printf '%s' "$INLINE_NAMES" | tr ',' ' '); do
    model=${pair#*=}
    case $sdk in
      typescript) found=$([ -f "typescript/src/models/$model.ts" ] && echo yes || echo no) ;;
      php) found=$([ -f "php/lib/Model/$model.php" ] && echo yes || echo no) ;;
      python) found=$(grep -rq "^class $model(" python/beai/models && echo yes || echo no) ;;
    esac
    if [ "$found" != yes ]; then
      echo "ERROR: inline schema mapping '$pair' produced no $sdk model $model" >&2
      exit 1
    fi
  done
}

generate typescript "$TMP/openapi.json" -g typescript-fetch \
  --additional-properties="npmName=@beai/sdk,npmVersion=$VERSION,supportsES6=true,typescriptThreePlus=true"
require_models typescript

# Bun is the only package manager we run: the generator's `prepare` script
# would shell out to npm on every install, and its README tells maintainers to
# use npm. Rewrite both deterministically. (The consumer-facing
# `npm install @beai/sdk` line stays: consumers choose their own manager.)
python3 - typescript <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])


def rewrite(path, pairs):
    """Applies each replacement and fails loudly when the pattern is gone."""
    text = path.read_text()
    for old, new in pairs:
        if old not in text:
            sys.exit(f"ERROR: {path}: expected text not found: {old!r}")
        text = text.replace(old, new)
    path.write_text(text)


rewrite(root / "package.json", [('"prepare": "npm run build"', '"prepare": "bun run build"')])
rewrite(root / "README.md", [
    ("you need to have Node.js and npm installed", "you need to have Bun installed"),
    ("npm install\nnpm run build", "bun install\nbun run build"),
    ("publish it to npm:\n\n```bash\nnpm publish", "publish it to npm:\n\n```bash\nbun publish"),
])
PY

# typescript-fetch imports every model an operation or model mentions, whether or
# not it uses it, and escapes quotes inside JSDoc comments. Clean both up in
# postprocess_typescript.py (tested by scripts/tests/sdk-postprocess.test.sh).
python3 -B postprocess_typescript.py typescript/src

generate php "$TMP/openapi.json" -g php \
  --additional-properties="composerVendorName=beai,composerProjectName=beai-php,packageName=Beai,invokerPackage=Beai,artifactVersion=$VERSION"
require_models php

generate python "$TMP/openapi.json" -g python \
  --additional-properties="packageName=beai,projectName=beai,packageVersion=$VERSION"
require_models python
