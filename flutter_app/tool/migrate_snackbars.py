#!/usr/bin/env python3
"""Replace ScaffoldMessenger snackbars with showAppMessage calls."""
from __future__ import annotations

import re
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent / "lib"
IMPORT = "import 'package:gloretto_mobile/widgets/app_notice.dart';\n"
SKIP = {"app_notice.dart", "app_overlay.dart"}

# Flexible: optional const, whitespace, chained line breaks
SNACK_RE = re.compile(
    r"(?:ScaffoldMessenger\.of\((?P<ctx>[^)]+)\)|(?P<var>messenger))"
    r"(?:\s*\.\s*|\s+)showSnackBar\(\s*"
    r"(?P<const>const\s+)?SnackBar\(\s*content:\s*Text\((?P<text>[^)]+)\)\s*,?\s*\)\s*,?\s*\)\s*;",
    re.MULTILINE | re.DOTALL,
)


def ensure_import(text: str) -> str:
    if "app_notice.dart" in text:
        return text
    if text.startswith("import "):
        first = text.find(";\n") + 2
        return text[:first] + IMPORT + text[first:]
    return IMPORT + text


def migrate_file(path: Path) -> bool:
    if path.name in SKIP:
        return False
    original = path.read_text(encoding="utf-8")
    messenger_ctx = None
    m = re.search(
        r"final\s+messenger\s*=\s*ScaffoldMessenger\.of\(([^)]+)\)",
        original,
    )
    if m:
        messenger_ctx = m.group(1).strip()

    def repl(match: re.Match[str]) -> str:
        ctx = match.group("ctx")
        if ctx is None:
            ctx = messenger_ctx or "context"
        else:
            ctx = ctx.strip()
        text = match.group("text").strip()
        return f"showAppMessage({ctx}, {text});"

    updated = SNACK_RE.sub(repl, original)
    if updated == original:
        return False
    path.write_text(ensure_import(updated), encoding="utf-8")
    return True


def main() -> None:
    changed = 0
    for path in LIB.rglob("*.dart"):
        if migrate_file(path):
            changed += 1
            print(f"updated {path.relative_to(LIB.parent)}")
    print(f"done: {changed} files")


if __name__ == "__main__":
    main()
