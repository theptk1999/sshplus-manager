#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "username validation blocks protected and option-like names" {
  run bash -c '
    source src/lib/core/validation.sh

    is_username normaluser
    is_username user_01
    is_username user-test
    is_username _user

    ! is_username root
    ! is_username -rf
    ! is_username --help
    ! is_username "bad:name"
    ! is_username "bad user"
  '

  [ "$status" -eq 0 ]
}

@test "runtime source contains no broad pkill" {
  run bash -c '
    if grep -RFn \
      --exclude="*.bak" \
      "pkill" \
      src
    then
      exit 1
    fi
  '

  [ "$status" -eq 0 ]
}

@test "runtime source contains no mutable GitHub raw main or master URLs" {
  run bash -c '
    if grep -RniE \
      --exclude="*.bak" \
      "raw\.githubusercontent\.com/.*/(main|master)/" \
      src install.sh
    then
      exit 1
    fi
  '

  [ "$status" -eq 0 ]
}

@test "old confirmation-only download API is absent" {
  run bash -c '
    if grep -RFn \
      --exclude="*.bak" \
      "download_with_user_confirmation" \
      src
    then
      exit 1
    fi
  '

  [ "$status" -eq 0 ]
}

@test "runtime updater contains no pull or reset hard" {
  run bash -c '
    if grep -RniE \
      --exclude="*.bak" \
      "git[[:space:]]+(pull|reset[[:space:]]+--hard)" \
      src install.sh
    then
      exit 1
    fi
  '

  [ "$status" -eq 0 ]
}

@test "installer requires a full pinned commit" {
  run grep -q \
    'SSHPLUS_REF.*40' \
    install.sh

  [ "$status" -eq 0 ]
}

@test "verified downloader rejects bad hashes and HTTP URLs" {
  run bash -c '
    set -e

    log_error() { :; }
    log_warn()  { :; }
    log_info()  { :; }

    source src/lib/core/download.sh

    tmp="$(mktemp)"
    trap "rm -f \"$tmp\"" EXIT

    printf "sshplus-security-test\n" > "$tmp"

    good="$(file_sha256 "$tmp")"
    bad="0000000000000000000000000000000000000000000000000000000000000000"

    verify_file_sha256 \
      "$tmp" \
      "$good" \
      "good-test"

    if verify_file_sha256 \
         "$tmp" \
         "$bad" \
         "bad-test"
    then
      exit 1
    fi

    if download_to_temp_file \
         "http://example.com/file" \
         "$tmp"
    then
      exit 1
    fi
  '

  [ "$status" -eq 0 ]
}

@test "trusted upstream hashes have valid SHA256 format" {
  run bash -c '
    source src/lib/core/constants.sh
    source src/lib/core/download.sh

    is_sha256 "$OPENVPN_SHA256"
    is_sha256 "$XRAY_INSTALL_SHA256"
    is_sha256 "$BADVPN_PRIMARY_SHA256"
    is_sha256 "$BADVPN_BACKUP_SHA256"
  '

  [ "$status" -eq 0 ]
}

@test "websocket manager has exactly one definition" {
  run bash -c '
    count="$(
      grep -Rhs \
        --include="*.sh" \
        "^function_websocket() {" \
        src |
      wc -l |
      tr -d " "
    )"

    [[ "$count" == "1" ]]
  '

  [ "$status" -eq 0 ]
}

@test "legacy phase generators fail closed" {
  run bash scripts/phase4-real-core.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"deprecated and disabled"* ]]

  run bash scripts/phase5-all-features.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"deprecated and disabled"* ]]
}

@test "legacy generators contain no insecure implementation" {
  run bash -c '
    if grep -En \
      "raw\.githubusercontent\.com/.*/(main|master)/|download_with_user_confirmation|pkill|userdel[[:space:]]+--force" \
      scripts/phase4-real-core.sh \
      scripts/phase5-all-features.sh
    then
      exit 1
    fi
  '

  [ "$status" -eq 0 ]
}

@test "Telegram bot has no runtime pip install or requests dependency" {
  run bash -c '
    if grep -nE \
      "import requests|requests\.(get|post)|-m[[:space:]]*['\''\"]?pip|pip3?[[:space:]]+install" \
      src/lib/features/30_services.sh
    then
      exit 1
    fi

    grep -q "urllib.request" \
      src/lib/features/30_services.sh
  '

  [ "$status" -eq 0 ]
}

@test "GitHub Actions are pinned to full commit SHAs" {
  run python3 - <<'PYTEST'
from pathlib import Path
import re
import sys

text = Path(
    ".github/workflows/ci.yml"
).read_text(
    encoding="utf-8"
)

refs = re.findall(
    r"^\s*uses:\s*([^@\s]+)@([^\s#]+)",
    text,
    re.M,
)

if not refs:
    raise SystemExit(
        "no GitHub Actions references found"
    )

bad = []

for action, ref in refs:
    if not re.fullmatch(
        r"[0-9a-f]{40}",
        ref
    ):
        bad.append(
            f"{action}@{ref}"
        )

if bad:
    print(
        "\n".join(bad),
        file=sys.stderr,
    )
    raise SystemExit(1)

print(
    f"verified {len(refs)} pinned Actions"
)
PYTEST

  [ "$status" -eq 0 ]
}

@test "embedded Telegram and limiter programs validate" {
  run python3 tests/check_embedded.py
  [ "$status" -eq 0 ]
}

@test "managed SSH users do not have independent password expiry" {
  run python3 - <<'PYTEST'
from pathlib import Path

users = Path(
    "src/lib/features/10_users.sh"
).read_text(encoding="utf-8")

services = Path(
    "src/lib/features/30_services.sh"
).read_text(encoding="utf-8")

if 'chage -M "$days"' in users:
    raise SystemExit(
        "legacy password max-age tied to account days remains"
    )

if users.count('chage -M -1 "$username"') < 4:
    raise SystemExit(
        "managed user password-aging normalization missing"
    )

if '["chage","-M","-1",u]' not in services:
    raise SystemExit(
        "Telegram-created users do not disable password expiry"
    )

print("managed user password aging verified")
PYTEST

  [ "$status" -eq 0 ]
}

@test "verified self-update refreshes generated runtime scripts" {
  run python3 - <<'PYTEST'
from pathlib import Path

main = Path(
    "src/main.sh"
).read_text(encoding="utf-8")

update = Path(
    "src/lib/features/50_uninstall.sh"
).read_text(encoding="utf-8")

runtime = Path(
    "src/lib/core/runtime_refresh.sh"
).read_text(encoding="utf-8")

checks = {
    "internal refresh mode":
        '--refresh-runtime' in main,
    "self-update invokes new binary refresh":
        '"$target_bin" --refresh-runtime' in update,
    "limiter template refresh":
        '"LIMEOF"' in runtime,
    "bot template refresh":
        '"BOTPY"' in runtime,
    "websocket template refresh":
        '"WSEOF"' in runtime,
    "runtime rollback support":
        "sshplus-prev" in runtime,
}

bad = [
    name
    for name, ok in checks.items()
    if not ok
]

if bad:
    raise SystemExit(
        "missing: " + ", ".join(bad)
    )

print("self-update runtime refresh verified")
PYTEST

  [ "$status" -eq 0 ]
}

@test "runtime refresh never enables previously disabled services" {
  run bash -c '
    file="src/lib/core/runtime_refresh.sh"

    grep -q \
      "Restart only services that were already active" \
      "$file"

    if grep -nE \
      "svc_(enable|start)[[:space:]]+(sshplus-limiter|sshplus-bot|sshplus-ws)" \
      "$file"
    then
      exit 1
    fi
  '

  [ "$status" -eq 0 ]
}

@test "renew expiry calculation safely adds days to a future expiry" {
  source src/lib/core/validation.sh
  source src/lib/features/10_users.sh

  local got=""

  got="$(
    calculate_renewed_expiry_epoch \
      1790237421 \
      3 \
      1790000000
  )"

  echo "got=$got"

  [ "$got" = "1790496621" ]
}

@test "renew expiry calculation starts from now when account is expired" {
  source src/lib/core/validation.sh
  source src/lib/features/10_users.sh

  local got=""

  got="$(
    calculate_renewed_expiry_epoch \
      1700000000 \
      2 \
      1790237421
  )"

  echo "got=$got"
  echo "expected=1790410221"

  [ "$got" = "1790410221" ]
}

@test "user DB rejects invalid expiry instead of coercing it to zero" {
  source src/lib/core/validation.sh
  source src/lib/data/user_db.sh

  local tmp=""

  tmp="$(mktemp -d)"

  DB_FILE="$tmp/usuarios.db"
  DB_LOCK_FILE="$tmp/usuarios.db.lock"

  export DB_FILE
  export DB_LOCK_FILE

  ensure_db

  if db_write_user_record testuser 1 ""; then
    echo "invalid empty expiry was accepted"
    rm -rf -- "$tmp"
    return 1
  fi

  if grep -q '^testuser:' "$DB_FILE"; then
    echo "invalid record was written"
    rm -rf -- "$tmp"
    return 1
  fi

  if db_write_user_record testuser 1 invalid; then
    echo "invalid non-numeric expiry was accepted"
    rm -rf -- "$tmp"
    return 1
  fi

  if grep -q '^testuser:' "$DB_FILE"; then
    echo "invalid record was written"
    rm -rf -- "$tmp"
    return 1
  fi

  rm -rf -- "$tmp"

  echo "invalid expiry rejected"
}

@test "renew path does not contain ambiguous epoch date expression" {
  if grep -Fq \
    'date -d "@$old_expire + $days days"' \
    src/lib/features/10_users.sh
  then
    echo "ambiguous GNU date expression still present"
    return 1
  fi

  echo "ambiguous renew expression absent"
}

@test "expired-user cleanup menu waits for acknowledgement" {
  run python3 - <<'PYTEST'
from pathlib import Path
import re

text = Path(
    "src/lib/features/10_users.sh"
).read_text(encoding="utf-8")

m = re.search(
    r"^function_remove_expired\(\) \{\n"
    r"(.*?)"
    r"^\}",
    text,
    re.MULTILINE | re.DOTALL,
)

if not m:
    raise SystemExit(
        "function_remove_expired not found"
    )

body = m.group(1)

checks = {
    "clears screen":
        "clear_screen" in body,
    "runs cleanup":
        "db_remove_expired" in body,
    "checks cleanup failure":
        "if ! db_remove_expired" in body,
    "waits for Enter":
        re.search(r"^\s*pause\s*$", body, re.MULTILINE)
        is not None,
    "old one-second delay removed":
        "sleep 1" not in body,
}

failed = [
    name
    for name, ok in checks.items()
    if not ok
]

if failed:
    raise SystemExit(
        "failed: " + ", ".join(failed)
    )

print("expired-user cleanup UX verified")
PYTEST

  [ "$status" -eq 0 ]
}
