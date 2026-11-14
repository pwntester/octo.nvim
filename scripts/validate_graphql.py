#!/usr/bin/env python3
"""Validate the GraphQL documents dumped by dump_graphql.lua against the
GitHub schema pinned in .graphqlrc.

Usage: validate_graphql.py <documents.json>
Reads the schema URL from .graphqlrc, caches it next to the file, and fails
with a nonzero exit code and a list of validation errors.
"""

import json
import sys
import urllib.request
from pathlib import Path

from graphql import build_schema, parse, validate
from graphql.validation import specified_rules

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_CACHE = ROOT / ".graphql-schema-cache.graphql"


def strip_deprecations(sdl: str) -> str:
    """GitHub's schema trips graphql-core's interface/implementation
    deprecation consistency rules; deprecation metadata does not affect
    document validation, so strip it."""
    import re

    return re.sub(r"@deprecated(?:\s*\((?:[^()]|\"[^\"]*\")*\))?", "", sdl)


def load_schema() -> str:
    if SCHEMA_CACHE.exists():
        return SCHEMA_CACHE.read_text()
    rc = (ROOT / ".graphqlrc").read_text()
    url = next(line.split(":", 1)[1].strip() for line in rc.splitlines() if line.startswith("schema:"))
    if not url.startswith("http"):
        return (ROOT / url).read_text()
    with urllib.request.urlopen(url, timeout=60) as resp:
        text = resp.read().decode()
    SCHEMA_CACHE.write_text(text)
    return text


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_graphql.py <documents.json>", file=sys.stderr)
        return 2
    docs = json.loads(Path(sys.argv[1]).read_text())
    schema = build_schema(strip_deprecations(load_schema()))

    # GitHub's server accepts same-name fields with different types in sibling
    # branches (octo's queries rely on this), but the spec's
    # OverlappingFieldsCanBeMergedRule rejects them; drop that one rule.
    rules = [r for r in specified_rules if getattr(r, "__name__", "") != "OverlappingFieldsCanBeMergedRule"]

    failures = 0
    skipped = 0
    for name, doc in sorted(docs.items()):
        if "%s" in doc or "%d" in doc or "%[" in doc:
            # Still built with string.format (see issue #765); not yet valid
            # standalone GraphQL, so nothing to validate.
            skipped += 1
            continue
        try:
            errors = validate(schema, parse(doc), rules=rules)
        except Exception as exc:  # syntax error
            print(f"{name}: PARSE ERROR: {exc}")
            failures += 1
            continue
        if errors:
            print(f"{name}: {len(errors)} error(s)")
            for err in errors:
                print(f"  {err.message}")
            failures += len(errors)

    if failures:
        print(f"\n{failures} validation error(s) in {len(docs)} documents")
        return 1
    skipped_note = f", {skipped} skipped (format placeholders, tracked in #765)" if skipped else ""
    print(f"OK: {len(docs) - skipped} documents validated against the schema{skipped_note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
