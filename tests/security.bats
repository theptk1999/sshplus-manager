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

@test "backup restore validator rejects malformed database records" {
  run bash -c '
    set -euo pipefail

    tmp="$1"
    mkdir -p "$tmp"

    source src/lib/core/validation.sh
    source src/lib/data/user_db.sh

    valid="$tmp/valid.db"

    cat > "$valid" <<DATA
zzbtuser01:2:1791158400
zzbtuser02:1:253402041600
DATA

    db_validate_file "$valid"

    printf "%s\n" \
      "zzbtuser01:1:1791158400:extra" \
      > "$tmp/extra.db"

    if db_validate_file "$tmp/extra.db"; then
      echo "accepted extra field"
      exit 1
    fi

    cat > "$tmp/duplicate.db" <<DATA
zzbtuser01:1:1791158400
zzbtuser01:2:1791158401
DATA

    if db_validate_file "$tmp/duplicate.db"; then
      echo "accepted duplicate username"
      exit 1
    fi

    printf "%s\n" \
      "zzbtuser01:0:1791158400" \
      > "$tmp/zero-limit.db"

    if db_validate_file "$tmp/zero-limit.db"; then
      echo "accepted zero limit"
      exit 1
    fi

    printf "%s\n" \
      "zzbtuser01:1:0" \
      > "$tmp/zero-expiry.db"

    if db_validate_file "$tmp/zero-expiry.db"; then
      echo "accepted zero expiry"
      exit 1
    fi

    printf "%s\n" \
      "zzbtuser01:1:253402300800" \
      > "$tmp/huge-expiry.db"

    if db_validate_file "$tmp/huge-expiry.db"; then
      echo "accepted expiry beyond year 9999"
      exit 1
    fi

    printf "%s\n" \
      "root:1:1791158400" \
      > "$tmp/root.db"

    if db_validate_file "$tmp/root.db"; then
      echo "accepted protected username"
      exit 1
    fi

    echo "DB validation fail-closed behavior verified"
  ' _ "$BATS_TEST_TMPDIR/validate"

  [ "$status" -eq 0 ]
}

@test "backup creation produces validated private exact copy" {
  run bash -c '
    set -euo pipefail

    tmp="$1"
    db="$tmp/usuarios.db"
    lock="$tmp/usuarios.db.lock"
    backups="$tmp/backups"

    mkdir -p "$backups"

    cat > "$db" <<DATA
zzbtcopy01:2:1791158400
zzbtcopy02:1:253402041600
DATA

    chmod 600 "$db"

    export DB_FILE="$db"
    export DB_LOCK_FILE="$lock"
    export SSHPLUS_BACKUP_DIR="$backups"
    export SSHPLUS_BACKUP_UID
    export SSHPLUS_BACKUP_GID

    SSHPLUS_BACKUP_UID="$(id -u)"
    SSHPLUS_BACKUP_GID="$(id -g)"

    source src/lib/core/validation.sh
    source src/lib/data/user_db.sh

    db_create_backup

    [[ -n "$DB_LAST_BACKUP" ]]
    [[ -f "$DB_LAST_BACKUP" ]]
    [[ ! -L "$DB_LAST_BACKUP" ]]

    cmp -s "$db" "$DB_LAST_BACKUP"

    [[ "$(stat -c "%a" "$DB_LAST_BACKUP")" == "600" ]]
    [[ "$(stat -c "%u" "$DB_LAST_BACKUP")" == "$SSHPLUS_BACKUP_UID" ]]
    [[ "$(stat -c "%g" "$DB_LAST_BACKUP")" == "$SSHPLUS_BACKUP_GID" ]]

    db_validate_backup_file "$DB_LAST_BACKUP"

    case "${DB_LAST_BACKUP##*/}" in
      backup_users_*.db) ;;
      *)
        echo "unsafe backup filename"
        exit 1
        ;;
    esac

    echo "private exact backup verified"
  ' _ "$BATS_TEST_TMPDIR/create"

  [ "$status" -eq 0 ]
}

@test "restore atomically replaces DB and preserves pre-restore safety backup" {
  run bash -c '
    set -euo pipefail

    tmp="$1"
    db="$tmp/usuarios.db"
    lock="$tmp/usuarios.db.lock"
    backups="$tmp/backups"

    mkdir -p "$backups"

    export DB_FILE="$db"
    export DB_LOCK_FILE="$lock"
    export SSHPLUS_BACKUP_DIR="$backups"

    export SSHPLUS_BACKUP_UID="$(id -u)"
    export SSHPLUS_BACKUP_GID="$(id -g)"
    export SSHPLUS_DB_UID="$(id -u)"
    export SSHPLUS_DB_GID="$(id -g)"

    source src/lib/core/validation.sh
    source src/lib/data/user_db.sh

    cat > "$db" <<DATA
zzbtorig01:2:1791158400
DATA
    chmod 600 "$db"

    db_create_backup
    source_backup="$DB_LAST_BACKUP"

    cat > "$db" <<DATA
zzbtnew01:7:1791763200
DATA
    chmod 600 "$db"

    cp "$db" "$tmp/pre-restore.expected"

    db_restore_backup "$source_backup"

    cmp -s "$db" "$source_backup"

    [[ -n "$DB_RESTORE_SAFETY_BACKUP" ]]
    [[ -f "$DB_RESTORE_SAFETY_BACKUP" ]]

    cmp -s \
      "$DB_RESTORE_SAFETY_BACKUP" \
      "$tmp/pre-restore.expected"

    [[ "$(stat -c "%a" "$db")" == "600" ]]
    [[ "$(stat -c "%a" "$DB_RESTORE_SAFETY_BACKUP")" == "600" ]]

    db_validate_backup_file \
      "$DB_RESTORE_SAFETY_BACKUP"

    echo "transactional restore and safety backup verified"
  ' _ "$BATS_TEST_TMPDIR/restore"

  [ "$status" -eq 0 ]
}

@test "invalid restore fails without replacing current DB" {
  run bash -c '
    set -euo pipefail

    tmp="$1"
    db="$tmp/usuarios.db"
    lock="$tmp/usuarios.db.lock"
    backups="$tmp/backups"

    mkdir -p "$backups"

    export DB_FILE="$db"
    export DB_LOCK_FILE="$lock"
    export SSHPLUS_BACKUP_DIR="$backups"

    export SSHPLUS_BACKUP_UID="$(id -u)"
    export SSHPLUS_BACKUP_GID="$(id -g)"
    export SSHPLUS_DB_UID="$(id -u)"
    export SSHPLUS_DB_GID="$(id -g)"

    source src/lib/core/validation.sh
    source src/lib/data/user_db.sh

    cat > "$db" <<DATA
zzbtsafe01:3:1791158400
DATA
    chmod 600 "$db"

    cp "$db" "$tmp/original.expected"

    bad="$backups/backup_users_20260923_120000_bad.db"

    cat > "$bad" <<DATA
zzbtsafe01:0:0
DATA

    chmod 600 "$bad"

    set +e
    db_restore_backup "$bad"
    rc=$?
    set -e

    [[ "$rc" -ne 0 ]]

    cmp -s \
      "$db" \
      "$tmp/original.expected"

    [[ -z "$DB_RESTORE_SAFETY_BACKUP" ]]

    echo "invalid restore preserved current DB"
  ' _ "$BATS_TEST_TMPDIR/reject"

  [ "$status" -eq 0 ]
}

@test "restore primitive requires explicit ADOPT for unmanaged existing account" {
  run bash -c '
    set -euo pipefail

    tmp="$1"
    db="$tmp/usuarios.db"
    lock="$tmp/usuarios.db.lock"
    backups="$tmp/backups"

    mkdir -p "$backups"

    export DB_FILE="$db"
    export DB_LOCK_FILE="$lock"
    export SSHPLUS_BACKUP_DIR="$backups"

    export SSHPLUS_BACKUP_UID="$(id -u)"
    export SSHPLUS_BACKUP_GID="$(id -g)"
    export SSHPLUS_DB_UID="$(id -u)"
    export SSHPLUS_DB_GID="$(id -g)"

    source src/lib/core/validation.sh
    source src/lib/data/user_db.sh

    cat > "$db" <<DATA
zzbtbase01:1:1791158400
DATA
    chmod 600 "$db"

    cp "$db" "$tmp/original.expected"

    backup="$backups/backup_users_20260923_130000_adopt.db"

    cat > "$backup" <<DATA
zzbtadopt01:2:1791763200
DATA
    chmod 600 "$backup"

    id() {
      if [[ "${1:-}" == "zzbtadopt01" ]]; then
        return 0
      fi

      command id "$@"
    }

    is_safe_deletable_local_user() {
      [[ "${1:-}" == "zzbtadopt01" ]]
    }

    db_user_is_managed() {
      return 1
    }

    db_validate_backup_file "$backup"

    set +e
    db_restore_backup "$backup"
    rc=$?
    set -e

    [[ "$rc" -eq 2 ]]

    cmp -s \
      "$db" \
      "$tmp/original.expected"

    [[ -z "$DB_RESTORE_SAFETY_BACKUP" ]]

    db_restore_backup \
      "$backup" \
      "ADOPT"

    grep -qx \
      "zzbtadopt01:2:1791763200" \
      "$db"

    [[ -n "$DB_RESTORE_SAFETY_BACKUP" ]]
    [[ -f "$DB_RESTORE_SAFETY_BACKUP" ]]

    echo "internal ADOPT enforcement verified"
  ' _ "$BATS_TEST_TMPDIR/adopt"

  [ "$status" -eq 0 ]
}

@test "restore enforces ADOPT against exact validated restore copy" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/data/user_db.sh"
).read_text(encoding="utf-8")

start = text.index("db_restore_backup() {")
end = text.index(
    "\ndb_report_restore_mismatches() {",
    start,
)

body = text[start:end]

copy_pos = body.index(
    'cp -- "$source" "$restore_temp"'
)

validate_pos = body.index(
    'db_validate_file "$restore_temp"'
)

adopt_pos = body.index(
    'db_report_restore_adoptions "$restore_temp"'
)

move_pos = body.index(
    'mv -- "$restore_temp" "$db"'
)

if not (
    copy_pos
    < validate_pos
    < adopt_pos
    < move_pos
):
    raise SystemExit(
        "unsafe restore order: "
        "copy -> validate -> ADOPT -> atomic move required"
    )

if 'db_report_restore_adoptions "$source"' in body:
    raise SystemExit(
        "ADOPT is still checked against mutable source"
    )

print("exact-copy ADOPT ordering verified")
PYTEST

  [ "$status" -eq 0 ]
}

@test "config backup is unique exact and fails closed on copy failure" {
  run bash -c '
    set -euo pipefail

    tmp="$1"
    mkdir -p "$tmp"

    source src/lib/core/validation.sh

    src="$tmp/config"
    printf "%s\n" "original-data" > "$src"

    first="$(backup_file "$src")"
    second="$(backup_file "$src")"

    [[ "$first" != "$second" ]]
    [[ -f "$first" ]]
    [[ -f "$second" ]]

    cmp -s "$src" "$first"
    cmp -s "$src" "$second"

    cp() {
      return 1
    }

    if backup_file "$src" >/dev/null 2>&1; then
      echo "backup_file ignored copy failure"
      exit 1
    fi

    echo "fail-closed unique config backup verified"
  ' _ "$BATS_TEST_TMPDIR/config-backup"

  [ "$status" -eq 0 ]
}

@test "SSH restart helper propagates failure" {
  run bash -c '
    set -euo pipefail

    source src/lib/core/service.sh

    svc_restart() {
      return 1
    }

    if restart_ssh_service; then
      echo "restart failure was hidden"
      exit 1
    fi

    calls=0

    svc_restart() {
      calls=$((calls + 1))

      if [[ "$1" == "sshd" ]]; then
        return 0
      fi

      return 1
    }

    restart_ssh_service

    echo "SSH restart failure propagation verified"
  '

  [ "$status" -eq 0 ]
}

@test "SSH socket guard blocks active or enabled socket activation" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/features/20_network.sh"
).read_text(encoding="utf-8")

start = text.index("ssh_socket_activation_active() {")
end = text.index("\n}", start) + 2

body = text[start:end]

required = [
    "systemctl is-active",
    "--quiet ssh.socket",
    "systemctl is-enabled",
]

for item in required:
    if item not in body:
        raise SystemExit(
            f"missing socket guard: {item}"
        )

if body.index("systemctl is-active") > body.index(
    "systemctl is-enabled"
):
    raise SystemExit(
        "active/enabled socket checks are unexpectedly ordered"
    )

print("active/enabled ssh.socket guard verified")
PYTEST

  [ "$status" -eq 0 ]
}

@test "SSH port migration blocks risky state before modifying config" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/features/20_network.sh"
).read_text(encoding="utf-8")

start = text.index("function_mode_connection() {")
end = text.index("\n      2)", start)

ssh = text[start:end]

collision = ssh.index(
    'is_port_in_use "$new_ssh"'
)
session = ssh.index(
    "current_login_local_port"
)
socket = ssh.index(
    "ssh_socket_activation_active"
)
websocket = ssh.index(
    "svc_is_active sshplus-ws"
)
backup = ssh.index(
    'backup_file "$ssh_cfg"'
)

if not (
    collision
    < session
    < socket
    < websocket
    < backup
):
    raise SystemExit(
        "SSH safety checks must run before config backup/write"
    )

if "sed -i" not in ssh:
    raise SystemExit("SSH config update missing")

write = ssh.index("sed -i")

if backup > write:
    raise SystemExit(
        "SSH config is modified before backup"
    )

print("SSH pre-write safety ordering verified")
PYTEST

  [ "$status" -eq 0 ]
}

@test "Dropbear port migration has collision rollback and listener verification" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/features/20_network.sh"
).read_text(encoding="utf-8")

menu = text[text.index("function_mode_connection() {"):]

start = menu.index("\n      2)")
end = menu.index("\n      3)", start)

drop = menu[start:end]

required = [
    'is_port_in_use "$new_drop"',
    'backup_file "$cfg_drop"',
    "svc_restart dropbear",
    "rollback_port_config",
    'is_tcp_port_listening "$new_drop"',
]

for item in required:
    if item not in drop:
        raise SystemExit(
            f"Dropbear safety marker missing: {item}"
        )

if not (
    drop.index('is_port_in_use "$new_drop"')
    < drop.index('backup_file "$cfg_drop"')
    < drop.index("svc_restart dropbear")
    < drop.index('is_tcp_port_listening "$new_drop"')
):
    raise SystemExit(
        "Dropbear migration ordering is unsafe"
    )

print("Dropbear transactional migration markers verified")
PYTEST

  [ "$status" -eq 0 ]
}

@test "TCP listener helper matches exact port rather than substring" {
  run bash -c '
    set -euo pipefail

    source src/lib/core/validation.sh

    SS_OUT="LISTEN 0 128 0.0.0.0:2222 0.0.0.0:*"

    ss() {
      printf "%s\n" "$SS_OUT"
    }

    if is_tcp_port_listening 22; then
      echo "port 22 falsely matched port 2222"
      exit 1
    fi

    SS_OUT="$(printf "%s\n%s\n" \
      "LISTEN 0 128 0.0.0.0:2222 0.0.0.0:*" \
      "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*")"

    is_tcp_port_listening 22

    echo "exact TCP listener matching verified"
  '

  [ "$status" -eq 0 ]
}


@test "SSH login port detection survives sudo-style environment stripping" {
  run env \
    SSH_CONNECTION="198.51.100.10 45123 10.0.0.31 22022" \
    bash -c '
      set -eo pipefail

      env -u SSH_CONNECTION bash -c '"'"'
        set -eo pipefail

        source src/lib/core/validation.sh
        source src/lib/features/20_network.sh

        if [[ -n "${SSH_CONNECTION:-}" ]]; then
          echo "child unexpectedly inherited SSH_CONNECTION"
          exit 1
        fi

        port="$(
          current_login_local_port
        )"

        echo "detected-port=$port"

        [[ "$port" == "22022" ]]
      '"'"'
    '

  [ "$status" -eq 0 ]
}


@test "port manager never installs or starts missing services implicitly" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/features/20_network.sh"
).read_text(encoding="utf-8")

helper_start = text.index(
    "require_port_service_ready() {"
)
helper_end = text.index(
    "\n}",
    helper_start,
) + 2

helper = text[helper_start:helper_end]

menu_start = text.index(
    "function_mode_connection() {"
)
menu_end = text.index(
    "\nfunction_trafego() {",
    menu_start,
)

menu = text[menu_start:menu_end]

for forbidden in (
    "install_pkg",
    "apt-get",
    "svc_enable",
    "svc_start",
):
    if forbidden in helper:
        raise SystemExit(
            f"require-only helper contains side effect: {forbidden}"
        )

    if forbidden in menu:
        raise SystemExit(
            f"port menu contains implicit side effect: {forbidden}"
        )

if "ensure_port_service_installed" in menu:
    raise SystemExit(
        "port menu still invokes implicit installer"
    )

for service in (
    "ssh",
    "dropbear",
    "stunnel",
    "squid",
):
    marker = f"require_port_service_ready {service}"

    if menu.count(marker) != 1:
        raise SystemExit(
            f"missing/duplicate readiness guard: {marker}"
        )

print("port manager has no implicit installation/start")
PYTEST

  [ "$status" -eq 0 ]
}

@test "stunnel and squid require configured active services before mutation" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/features/20_network.sh"
).read_text(encoding="utf-8")

h_start = text.index(
    "require_port_service_ready() {"
)
h_end = text.index(
    "\n}",
    h_start,
) + 2

helper = text[h_start:h_end]

required = [
    "/etc/stunnel/stunnel.conf",
    "svc_is_active stunnel4",
    "svc_is_active stunnel",
    "/etc/squid/squid.conf",
    "/etc/squid3/squid.conf",
    "svc_is_active squid",
    "svc_is_active squid3",
]

for marker in required:
    if marker not in helper:
        raise SystemExit(
            f"readiness guard missing: {marker}"
        )

menu_start = text.index(
    "function_mode_connection() {"
)
menu = text[menu_start:]

st_start = menu.index("\n      3)")
st_end = menu.index("\n      4)", st_start)
stunnel = menu[st_start:st_end]

sq_start = menu.index("\n      4)")
sq_end = menu.index("\n      5)", sq_start)
squid = menu[sq_start:sq_end]

if stunnel.index(
    "require_port_service_ready stunnel"
) > stunnel.index(
    'backup_file "$cfg_st"'
):
    raise SystemExit(
        "Stunnel readiness guard occurs after mutation preparation"
    )

if squid.index(
    "require_port_service_ready squid"
) > squid.index(
    'backup_file "$cfg_sq"'
):
    raise SystemExit(
        "Squid readiness guard occurs after mutation preparation"
    )

print("inactive/unconfigured Stunnel and Squid fail before mutation")
PYTEST

  [ "$status" -eq 0 ]
}


@test "speedtest menu never installs packages implicitly" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/features/40_tools.sh"
).read_text(encoding="utf-8")

start = text.index("function_speedtest() {")
end = text.index("\n}", start) + 2

body = text[start:end]

for forbidden in (
    "install_pkg",
    "apt-get",
    "apt ",
    "pip ",
    "curl ",
    "wget ",
):
    if forbidden in body:
        raise SystemExit(
            f"speedtest menu contains implicit setup: {forbidden}"
        )

required = [
    "command -v speedtest-cli",
    'log_error "ยังไม่ได้ติดตั้ง speedtest-cli"',
    "speedtest-cli",
    'log_error "Speedtest ทำงานไม่สำเร็จ"',
    "return 1",
]

for marker in required:
    if marker not in body:
        raise SystemExit(
            f"speedtest guard missing: {marker}"
        )

print("speedtest menu is execution-only")
PYTEST

  [ "$status" -eq 0 ]
}

@test "speedtest menu handles missing command without invoking installer" {
  run bash -c '
    set -eo pipefail

    source src/lib/features/40_tools.sh

    messages=""
    pauses=0

    log_info() {
      messages="${messages}INFO:$*\n"
    }

    log_warn() {
      messages="${messages}WARN:$*\n"
    }

    log_error() {
      messages="${messages}ERROR:$*\n"
    }

    pause() {
      pauses=$((pauses + 1))
    }

    command() {
      if [[ "${1:-}" == "-v" &&
            "${2:-}" == "speedtest-cli" ]]; then
        return 1
      fi

      builtin command "$@"
    }

    if function_speedtest; then
      echo "missing speedtest unexpectedly succeeded"
      exit 1
    fi

    [[ "$pauses" -eq 1 ]]
    [[ "$messages" == *"ยังไม่ได้ติดตั้ง speedtest-cli"* ]]

    echo "missing speedtest fails without installation"
  '

  [ "$status" -eq 0 ]
}


@test "cache cleanup menu requires explicit confirmation and fails closed" {
  run python3 - <<'PYTEST'
from pathlib import Path

text = Path(
    "src/lib/features/40_tools.sh"
).read_text(encoding="utf-8")

import re

for name in (
    "can_drop_filesystem_caches",
    "drop_filesystem_caches",
    "function_otimizar",
):
    pattern = rf"^{re.escape(name)}\(\) \{{"

    if len(re.findall(pattern, text, re.MULTILINE)) != 1:
        raise SystemExit(
            f"missing/duplicated function: {name}"
        )

drop_match = re.search(
    r"^drop_filesystem_caches\(\) \{$",
    text,
    re.MULTILINE,
)

if not drop_match:
    raise SystemExit(
        "drop_filesystem_caches definition not found"
    )

drop_start = drop_match.start()
drop_end = text.index(
    "\n}",
    drop_start,
) + 2

drop = text[drop_start:drop_end]

for marker in (
    "sync || return 1",
    "printf '3\\n' > /proc/sys/vm/drop_caches",
):
    if marker not in drop:
        raise SystemExit(
            f"cache drop helper missing: {marker}"
        )

if "|| true" in drop:
    raise SystemExit(
        "cache drop helper suppresses failure"
    )

menu_start = text.index(
    "function_otimizar() {"
)
menu_end = text.index(
    "\n}",
    menu_start,
) + 2

menu = text[menu_start:menu_end]

required = (
    "require_root",
    "can_drop_filesystem_caches",
    '[[ "$confirm" != "YES" ]]',
    "drop_filesystem_caches",
    'log_error "ล้าง filesystem cache ไม่สำเร็จ"',
    'log_info "ล้าง filesystem cache เรียบร้อย"',
)

for marker in required:
    if marker not in menu:
        raise SystemExit(
            f"cache cleanup guard missing: {marker}"
        )

if "ล้าง RAM เรียบร้อย" in menu:
    raise SystemExit(
        "misleading RAM-cleanup message remains"
    )

print("cache cleanup is explicit and fail-closed")
PYTEST

  [ "$status" -eq 0 ]
}

@test "cache cleanup cancellation performs no cache drop" {
  run bash -c '
    set -eo pipefail

    source src/lib/features/40_tools.sh

    calls=0
    messages=""

    require_root() {
      return 0
    }

    can_drop_filesystem_caches() {
      return 0
    }

    drop_filesystem_caches() {
      calls=$((calls + 1))
      return 0
    }

    log_info() {
      messages="${messages}INFO:$*\n"
    }

    log_warn() {
      messages="${messages}WARN:$*\n"
    }

    log_error() {
      messages="${messages}ERROR:$*\n"
    }

    pause() {
      :
    }

    function_otimizar <<< "NO"

    [[ "$calls" -eq 0 ]]
    [[ "$messages" == *"ยกเลิกการล้าง filesystem cache"* ]]

    echo "cancellation performs no cache drop"
  '

  [ "$status" -eq 0 ]
}

@test "cache cleanup confirmation invokes cache drop exactly once" {
  run bash -c '
    set -eo pipefail

    source src/lib/features/40_tools.sh

    calls=0
    messages=""

    require_root() {
      return 0
    }

    can_drop_filesystem_caches() {
      return 0
    }

    drop_filesystem_caches() {
      calls=$((calls + 1))
      return 0
    }

    log_info() {
      messages="${messages}INFO:$*\n"
    }

    log_warn() {
      messages="${messages}WARN:$*\n"
    }

    log_error() {
      messages="${messages}ERROR:$*\n"
    }

    pause() {
      :
    }

    function_otimizar <<< "YES"

    [[ "$calls" -eq 1 ]]
    [[ "$messages" == *"ล้าง filesystem cache เรียบร้อย"* ]]

    echo "confirmed cleanup invokes cache drop once"
  '

  [ "$status" -eq 0 ]
}

@test "cache cleanup propagates cache drop failure" {
  run bash -c '
    set -eo pipefail

    source src/lib/features/40_tools.sh

    calls=0
    messages=""

    require_root() {
      return 0
    }

    can_drop_filesystem_caches() {
      return 0
    }

    drop_filesystem_caches() {
      calls=$((calls + 1))
      return 1
    }

    log_info() {
      messages="${messages}INFO:$*\n"
    }

    log_warn() {
      messages="${messages}WARN:$*\n"
    }

    log_error() {
      messages="${messages}ERROR:$*\n"
    }

    pause() {
      :
    }

    if function_otimizar <<< "YES"; then
      echo "cache-drop failure unexpectedly succeeded"
      exit 1
    fi

    [[ "$calls" -eq 1 ]]
    [[ "$messages" == *"ล้าง filesystem cache ไม่สำเร็จ"* ]]

    echo "cache-drop failure propagates correctly"
  '

  [ "$status" -eq 0 ]
}
