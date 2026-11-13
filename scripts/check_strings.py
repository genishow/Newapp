#!/usr/bin/env python3
"""Checks the Amharic table: every title shown with A("...") has a line,
no key is written twice, and %@ counts match. Run from the repository root."""
import glob, re, sys

table_src = open("Sources/Support/Amharic.swift", encoding="utf-8").read()
STR = r'"((?:[^"\\]|\\.)*)"'
pairs = re.findall(STR + r'\s*:\s*' + STR, table_src)
keys = [k for k, _ in pairs]
problems = []
seen = set()
for k, v in pairs:
    if k in seen:
        problems.append(f"written twice: {k}")
    seen.add(k)
    if k.count("%@") != v.count("%@"):
        problems.append(f"%@ count differs: {k}")
    if v != v.strip() and k == k.strip():
        problems.append(f"stray space: {k}")

used = set()
for path in glob.glob("Sources/**/*.swift", recursive=True):
    if path.endswith("Amharic.swift"):
        continue
    src = open(path, encoding="utf-8").read()
    # The interface is English. Amharic is only shown under the big titles, through A("...").
    for m in re.finditer(r'\bA\(\s*' + STR, src):
        used.add(m.group(1))
for k in sorted(used - seen):
    if "\\(" in k or "sample" in k:   # sample buttons only exist in the test build
        continue
    problems.append(f"no Amharic line: {k}")

print(f"{len(keys)} lines in the table, {len(used)} strings used")
for p in problems:
    print("PROBLEM", p)
sys.exit(1 if problems else 0)
