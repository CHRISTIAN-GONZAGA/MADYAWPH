"""Unwraps string literals that contain nothing but a formatMoney call."""
import os
import sys

LIB = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "flutter_app", "lib"
)


def find_close(text: str, open_index: int) -> int:
    depth = 0
    i = open_index
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def unwrap(text: str) -> tuple[str, int]:
    changes = 0
    for quote in ("'", '"'):
        needle = quote + "${formatMoney("
        i = 0
        out = []
        while True:
            at = text.find(needle, i)
            if at == -1:
                out.append(text[i:])
                break
            brace = at + len(quote) + 1
            close = find_close(text, brace)
            if close == -1 or close + 1 >= len(text) or text[close + 1] != quote:
                out.append(text[i:at + len(needle)])
                i = at + len(needle)
                continue
            out.append(text[i:at])
            out.append(text[brace + 1:close])
            changes += 1
            i = close + 2
        text = "".join(out)
    return text, changes


def main() -> None:
    total = 0
    for dirpath, _dirs, files in os.walk(LIB):
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8") as fh:
                original = fh.read()
            updated, changes = unwrap(original)
            if changes:
                with open(path, "w", encoding="utf-8", newline="") as fh:
                    fh.write(updated)
                total += changes
                sys.stdout.write(f"{os.path.relpath(path, LIB)}: {changes}\n")
    sys.stdout.write(f"TOTAL {total}\n")


if __name__ == "__main__":
    main()
