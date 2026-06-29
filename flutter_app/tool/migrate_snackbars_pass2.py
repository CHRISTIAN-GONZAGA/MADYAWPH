#!/usr/bin/env python3
"""Second-pass snackbar migration for dioErrorMessage and chained calls."""
from __future__ import annotations

import re
from pathlib import Path

LIB = Path(__file__).resolve().parent.parent / "lib"
IMPORT = "import 'package:gloretto_mobile/widgets/app_notice.dart';\n"
SKIP = {"app_notice.dart", "app_overlay.dart", "hotel_credits_policy.dart"}


def ensure_import(text: str) -> str:
    if "app_notice.dart" in text:
        return text
    if text.startswith("import "):
        first = text.find(";\n") + 2
        return text[:first] + IMPORT + text[first:]
    return IMPORT + text


def migrate(text: str) -> str:
    messenger_ctx = None
    m = re.search(
        r"final\s+messenger\s*=\s*ScaffoldMessenger\.of\(([^)]+)\)",
        text,
    )
    if m:
        messenger_ctx = m.group(1).strip()

    patterns = [
        (
            re.compile(
                r"ScaffoldMessenger\.of\((?P<ctx>[^)]+)\)\s*"
                r"(?:\.\s*)?showSnackBar\(\s*"
                r"SnackBar\(\s*content:\s*Text\(dioErrorMessage\(e\)\)\s*,?\s*\)\s*,?\s*\)\s*;",
                re.MULTILINE,
            ),
            lambda m: f"showAppMessage({m.group('ctx').strip()}, dioErrorMessage(e), isError: true);",
        ),
        (
            re.compile(
                r"ScaffoldMessenger\.of\((?P<ctx>[^)]+)\)\s*"
                r"\n\s*\.showSnackBar\(SnackBar\(content: Text\(dioErrorMessage\(e\)\)\)\)\s*;",
                re.MULTILINE,
            ),
            lambda m: f"showAppMessage({m.group('ctx').strip()}, dioErrorMessage(e), isError: true);",
        ),
        (
            re.compile(
                r"messenger\.showSnackBar\(\s*"
                r"SnackBar\(\s*content:\s*Text\(dioErrorMessage\(e\)\)\s*,?\s*\)\s*,?\s*\)\s*;",
                re.MULTILINE,
            ),
            lambda m: f"showAppMessage({messenger_ctx or 'context'}, dioErrorMessage(e), isError: true);",
        ),
        (
            re.compile(
                r"ScaffoldMessenger\.of\((?P<ctx>[^)]+)\)\s*"
                r"\n\s*\.showSnackBar\(\s*const\s+SnackBar\(content: Text\((?P<text>[^)]+)\)\)\s*,?\s*\)\s*;",
                re.MULTILINE,
            ),
            lambda m: f"showAppMessage({m.group('ctx').strip()}, {m.group('text')});",
        ),
        (
            re.compile(
                r"ScaffoldMessenger\.of\((?P<ctx>[^)]+)\)\s*"
                r"\n\s*\.showSnackBar\(SnackBar\(content: Text\((?P<text>[^)]+)\)\)\)\s*;",
                re.MULTILINE,
            ),
            lambda m: f"showAppMessage({m.group('ctx').strip()}, {m.group('text')});",
        ),
    ]

    for pattern, repl in patterns:
        text = pattern.sub(repl, text)
    return text


def main() -> None:
    changed = 0
    for path in LIB.rglob("*.dart"):
        if path.name in SKIP:
            continue
        original = path.read_text(encoding="utf-8")
        updated = migrate(original)
        if updated == original:
            continue
        path.write_text(ensure_import(updated), encoding="utf-8")
        changed += 1
        print(f"updated {path.relative_to(LIB.parent)}")
    print(f"done: {changed} files")


if __name__ == "__main__":
    main()
