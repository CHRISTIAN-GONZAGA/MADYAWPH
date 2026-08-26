"""Lists every hardcoded peso interpolation in the Flutter app so they can be
migrated to the currency-aware formatter."""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "flutter_app", "lib")

pattern = re.compile("\u20b1")
count = 0
for dirpath, _dirs, files in os.walk(ROOT):
    for name in files:
        if not name.endswith(".dart"):
            continue
        path = os.path.join(dirpath, name)
        with open(path, encoding="utf-8") as fh:
            for i, line in enumerate(fh, 1):
                if pattern.search(line):
                    count += 1
                    rel = os.path.relpath(path, ROOT)
                    sys.stdout.write(f"{rel}:{i}: {line.strip()}\n")
sys.stdout.write(f"TOTAL {count}\n")
