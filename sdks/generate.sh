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

# The two inline item schemas of `Interview.progress` would otherwise be named
# after their position (`..._progress_inner`, `..._inner_answers_inner`). Give
# them names that say what they are, in all three SDKs.
INLINE_NAMES="PublicInterview_progress_inner=PublicInterviewProgressCompetency,PublicInterview_progress_inner_answers_inner=PublicInterviewProgressAnswer"
# The same goes for the models shared across operations: the generator names a
# schema after the first operation that uses it, so the RFC 9457 problem body
# would read as an "exports index 400" model everywhere.
INLINE_NAMES="$INLINE_NAMES,public_api_exports_index_400_response=PublicProblem,public_api_exports_index_400_response_errors_inner=PublicProblemError,public_api_webhooks_deliveries_index_200_response_data_inner=PublicWebhookDelivery,public_api_exports_index_200_response_data_inner=PublicExport,inline_object=PublicMessageError"

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

generate typescript "$TMP/openapi.json" -g typescript-fetch \
  --additional-properties="npmName=@beai/sdk,npmVersion=$VERSION,supportsES6=true,typescriptThreePlus=true"

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
# not the generated code ends up using it, and its blanket `eslint-disable` header
# hides the result. Drop the specifiers that are never referenced. Only identifiers
# are matched, against the file body without its import statements, so a name
# used in code or in a type position always survives. The same pass removes the
# backslashes the generator puts in front of quotes inside JSDoc comments.
python3 - typescript/src <<'PY'
import pathlib
import re
import sys

IMPORT = re.compile(r"^import (type )?\{([^}]*)\} from '([^']+)';\n", re.M)


def prune(text):
    body = IMPORT.sub("", text)

    def rewrite(match):
        kind, raw, source = match.group(1) or "", match.group(2), match.group(3)
        names = [n.strip() for n in raw.split(",") if n.strip()]
        kept = [n for n in names if re.search(r"\b" + re.escape(n.removeprefix("type ")) + r"\b", body)]
        if len(kept) == len(names):
            return match.group(0)
        if not kept:
            return ""
        if "\n" in raw:
            inner = "".join(f"    {n},\n" for n in kept)
            return f"import {kind}{{\n{inner}}} from '{source}';\n"
        return f"import {kind}{{ {', '.join(kept)} }} from '{source}';\n"

    return IMPORT.sub(rewrite, text)


def unescape_comments(text):
    """The generator escapes quotes inside JSDoc (`organization\\'s`); comments need no escaping."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.lstrip().startswith("*"):
            lines[i] = line.replace("\\'", "'").replace('\\"', '"')
    return "\n".join(lines)


changed = 0
for path in sorted(pathlib.Path(sys.argv[1]).rglob("*.ts")):
    before = path.read_text()
    after = unescape_comments(prune(before))
    if after != before:
        path.write_text(after)
        changed += 1
print(f"pruned unused imports in {changed} typescript files")
PY

generate php "$TMP/openapi.json" -g php \
  --additional-properties="composerVendorName=beai,composerProjectName=beai-php,packageName=Beai,invokerPackage=Beai,artifactVersion=$VERSION"

generate python "$TMP/openapi.json" -g python \
  --additional-properties="packageName=beai,projectName=beai,packageVersion=$VERSION"
