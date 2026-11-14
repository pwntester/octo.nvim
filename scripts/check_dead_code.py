#!/usr/bin/env python3
"""Flag exported module functions that are never referenced anywhere.

Scans every module under lua/octo for exports (`function M.name`,
`M.name = ...`) and fails if any export has no other occurrence in the
Lua sources. Genuinely public API that has no internal caller belongs in
the ALLOWLIST below so the check stays green while remaining explicit.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "lua" / "octo"

# Exported names that are intentionally public API without internal callers.
ALLOWLIST: set[str] = {
    # documented in README.md search-completion example
    "create_base_search_command",
}

# Exported tables / config-style members that the check cannot reason about.
SKIP_NAMES: set[str] = set()


def exports_of(src: str) -> list[str]:
    names = re.findall(r"^function M\.([A-Za-z_][A-Za-z0-9_]*)", src, re.M)
    names += re.findall(r"^M\.([A-Za-z_][A-Za-z0-9_]*)\s*=", src, re.M)
    return sorted(set(names))


def main() -> int:
    files = sorted(p for p in ROOT.rglob("*.lua"))
    texts = {str(p): p.read_text() for p in files}

    dead: list[str] = []
    for path, src in texts.items():
        for name in exports_of(src):
            if name in ALLOWLIST or name in SKIP_NAMES:
                continue
            refs = sum(len(re.findall(rf"\b{name}\b", t)) for t in texts.values())
            if path in texts:
                refs -= len(re.findall(rf"\b{name}\b", src)) and 1
            if refs == 0:
                dead.append(f"{path.removeprefix(str(ROOT) + '/')}: {name}")

    if dead:
        print("Dead exports found:")
        for item in dead:
            print(f"  {item}")
        print("Delete them, use them, or add to ALLOWLIST in scripts/check_dead_code.py")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
