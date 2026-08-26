"""Rewrites hardcoded peso interpolations to the currency-aware formatter.

Only hotel-facing money is migrated. Platform money (credits, subscriptions,
central admin revenue) stays in PHP because the platform always bills in pesos.
"""
import os
import re
import sys

PESO = "\u20b1"
LIB = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "flutter_app", "lib"
)

TARGET_DIRS = (
    os.path.join("flow", "admin"),
    os.path.join("flow", "widgets"),
)
TARGET_FILES = (
    os.path.join("flow", "admin_bookings.dart"),
    os.path.join("flow", "customer_booking_status_screen.dart"),
    os.path.join("flow", "customer_room_detail_screen.dart"),
    os.path.join("flow", "guest_list_history.dart"),
    os.path.join("widgets", "guest_online_payment.dart"),
)
SKIP = (
    os.path.join("flow", "admin", "widgets", "hotel_subscription_gate.dart"),
)


def is_target(rel: str) -> bool:
    if rel in SKIP:
        return False
    if rel in TARGET_FILES:
        return True
    return any(rel.startswith(d + os.sep) for d in TARGET_DIRS)


def find_close(text: str, open_index: int) -> int:
    """Index of the '}' matching the '{' at open_index, ignoring nested braces."""
    depth = 0
    i = open_index
    while i < len(text):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def split_to_string_as_fixed(inner: str):
    """Splits `expr.toStringAsFixed(args)` -> (expr, args), else None."""
    marker = ".toStringAsFixed("
    idx = inner.rfind(marker)
    if idx == -1 or not inner.rstrip().endswith(")"):
        return None
    expr = inner[:idx]
    args = inner[idx + len(marker):].rstrip()
    if not args.endswith(")"):
        return None
    args = args[:-1]
    # Bail out when the closing paren we stripped was not the matching one.
    if args.count("(") != args.count(")"):
        return None
    return expr, args


def migrate(text: str) -> tuple[str, int]:
    out = []
    i = 0
    changes = 0
    needle = PESO + "${"
    while True:
        at = text.find(needle, i)
        if at == -1:
            out.append(text[i:])
            break
        brace = at + len(PESO) + 1
        close = find_close(text, brace)
        if close == -1:
            out.append(text[i:at + len(needle)])
            i = at + len(needle)
            continue
        inner = text[brace + 1:close]
        parts = split_to_string_as_fixed(inner)
        out.append(text[i:at])
        if parts is None:
            out.append("${formatMoney(" + inner + ")}")
        else:
            expr, args = parts
            if args in ("2", ""):
                out.append("${formatMoney(" + expr + ")}")
            else:
                out.append("${formatMoney(" + expr + ", decimals: " + args + ")}")
        changes += 1
        i = close + 1
    return "".join(out), changes


def ensure_import(text: str, rel: str) -> str:
    if "utils/money_format.dart" in text:
        return text
    depth = rel.count(os.sep)
    prefix = "../" * depth
    line = f"import '{prefix}utils/money_format.dart';\n"
    imports = list(re.finditer(r"^import .*;\n", text, flags=re.MULTILINE))
    if not imports:
        return line + text
    last = imports[-1]
    return text[: last.end()] + line + text[last.end():]


def main() -> None:
    total = 0
    touched = []
    for dirpath, _dirs, files in os.walk(LIB):
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, LIB)
            if not is_target(rel):
                continue
            with open(path, encoding="utf-8") as fh:
                original = fh.read()
            if PESO + "${" not in original:
                continue
            updated, changes = migrate(original)
            if changes == 0:
                continue
            updated = ensure_import(updated, rel)
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(updated)
            total += changes
            touched.append(f"{rel}: {changes}")
    for entry in touched:
        sys.stdout.write(entry + "\n")
    sys.stdout.write(f"TOTAL {total}\n")


if __name__ == "__main__":
    main()
