"""Post-processing of the generated TypeScript SDK (run by sdks/generate.sh).

typescript-fetch imports every model an operation or model mentions, whether or
not the generated code ends up using it, and its blanket `eslint-disable` header
hides the result. It also escapes quotes inside JSDoc comments, where they need
no escaping. This module removes both, deterministically, and proves it did:

* only identifiers are matched, against the file body without its import
  statements, so a name used in code or in a type position always survives;
* a second pass over the result must find nothing left to do (idempotence);
* nothing is written until every file passed, and each file is replaced
  atomically, so a failure never leaves a half-written file behind.
"""

import os
import pathlib
import re
import sys
import tempfile

IMPORT = re.compile(r"^import (type )?\{([^}]*)\} from '([^']+)';\n", re.M)


class PostProcessError(Exception):
    """Raised when the generated tree cannot be post-processed safely."""


def specifier_name(specifier):
    """`type Foo` imports the type `Foo`; the identifier to look for is `Foo`."""
    return specifier.removeprefix("type ")


def prune(text):
    """Drops the import specifiers that the file body never references."""
    body = IMPORT.sub("", text)

    def rewrite(match):
        kind, raw, source = match.group(1) or "", match.group(2), match.group(3)
        names = [n.strip() for n in raw.split(",") if n.strip()]
        kept = [n for n in names if re.search(r"\b" + re.escape(specifier_name(n)) + r"\b", body)]
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


def process_text(text):
    return unescape_comments(prune(text))


def plan(root):
    """Maps each file that needs a change to its new content; validates every file first."""
    results = {}
    for path in sorted(pathlib.Path(root).rglob("*.ts")):
        before = path.read_text()
        after = process_text(before)
        if process_text(after) != after:
            raise PostProcessError(f"{path}: post-processing is not idempotent")
        if after != before:
            results[path] = after
    return results


def write_atomically(path, content):
    """Writes next to the target, then renames over it: a reader never sees half a file."""
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=path.name, suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w") as handle:
            handle.write(content)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def run(root):
    results = plan(root)
    for path, content in results.items():
        write_atomically(path, content)
    return len(results)


def main(argv):
    if len(argv) != 2:
        print("usage: postprocess_typescript.py <typescript/src>", file=sys.stderr)
        return 2
    try:
        changed = run(argv[1])
    except PostProcessError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"pruned unused imports in {changed} typescript files")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
