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
