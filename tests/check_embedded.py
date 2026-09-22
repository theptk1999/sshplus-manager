#!/usr/bin/env python3

from pathlib import Path
import re
import subprocess
import sys

source_path = Path("src/lib/features/30_services.sh")

if not source_path.is_file():
    raise SystemExit("[FAIL] 30_services.sh not found")

source = source_path.read_text(encoding="utf-8")


def extract(tag):
    pattern = re.compile(
        rf"cat <<'{re.escape(tag)}' > [^\n]+\n"
        rf"(.*?)"
        rf"\n{re.escape(tag)}(?:\n|$)",
        re.S,
    )

    match = pattern.search(source)

    if not match:
        raise RuntimeError(
            f"embedded block not found: {tag}"
        )

    return match.group(1) + "\n"


bot = extract("BOTPY")

try:
    compile(
        bot,
        "<sshplus-telegram-bot>",
        "exec",
    )
except SyntaxError as exc:
    print(
        f"[FAIL] Telegram Python: line={exc.lineno} {exc.msg}",
        file=sys.stderr,
    )
    raise SystemExit(1)


ws_proxy = extract("WSEOF")

try:
    compile(
        ws_proxy,
        "<sshplus-websocket-proxy>",
        "exec",
    )
except SyntaxError as exc:
    print(
        f"[FAIL] WebSocket Python: line={exc.lineno} {exc.msg}",
        file=sys.stderr,
    )
    raise SystemExit(1)

print("[PASS] embedded WebSocket Python")


limiter = extract("LIMEOF")

result = subprocess.run(
    ["bash", "-n"],
    input=limiter,
    text=True,
    capture_output=True,
)

if result.returncode != 0:
    print(result.stderr, file=sys.stderr)
    raise SystemExit(
        "[FAIL] generated limiter Bash syntax"
    )

if re.search(r"\bpkill\b", limiter):
    raise SystemExit(
        "[FAIL] broad pkill detected in limiter"
    )

required = (
    "collect_sessions()",
    "session_matches_user()",
    "enforce_user_limit()",
    "kill -TERM",
    "kill -KILL",
    "sort -k2,2nr",
)

for marker in required:
    if marker not in limiter:
        raise SystemExit(
            f"[FAIL] limiter marker missing: {marker}"
        )

print("[PASS] embedded Telegram Python")
print("[PASS] generated SSH limiter syntax")
print("[PASS] limiter contains no broad pkill")
print("[PASS] limiter safety markers")
