#!/usr/bin/env python3
"""Checks that the real Kinbir server still answers in the shape the app expects.

Free, public endpoints only. It never signs in and never spends credits.
Python 3 stdlib only. Usage: python3 scripts/live_smoke.py [base_url]
"""
import json
import sys
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "https://api.kinbir.com"
failures = []


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("User-Agent", "kinbir-ios-ci")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            return res.status, json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode() or "{}")
        except ValueError:
            return e.code, {}


def check(name, ok, detail=""):
    print(("PASS  " if ok else "FAIL  ") + name + (("  " + detail) if detail and not ok else ""))
    if not ok:
        failures.append(name)


def has_ethiopic(text):
    return any(0x1200 <= ord(c) <= 0x137F for c in text or "")


try:
    status, _ = call("GET", "/health")
    check("GET /health answers 200", status == 200, "got %s" % status)

    status, body = call("GET", "/enroll/script")
    check("GET /enroll/script answers 200", status == 200, "got %s" % status)
    script = body.get("personal") or body.get("enroll_text") or ""
    check("enroll script is Amharic text", has_ethiopic(script))

    # A bad email must be refused with a sentence in `detail`, the shape the app shows.
    status, body = call("POST", "/auth/request-code", {"email": "not-an-email"})
    check("POST /auth/request-code refuses a bad email with 400", status == 400, "got %s" % status)
    check("errors carry a sentence in detail", isinstance(body.get("detail"), str))

    # No access code must be 401, which the app turns into "sign in again".
    status, _ = call("GET", "/whoami")
    check("GET /whoami without a code answers 401", status == 401, "got %s" % status)
except Exception as e:  # network trouble is a failure of this check, with a clear line
    check("server reachable", False, repr(e))

print()
if failures:
    print("%d check(s) failed: %s" % (len(failures), ", ".join(failures)))
    sys.exit(1)
print("All live server checks passed.")
