#!/usr/bin/env bash
# ==================================================
# SSHPlus Manager - Pinned Remote Installer
#
# Recommended usage:
#
#   COMMIT="<40-char trusted commit SHA>"
#   curl -fsSL \
#     "https://raw.githubusercontent.com/theptk1999/sshplus-manager/${COMMIT}/install.sh" |
#     sudo env SSHPLUS_REF="$COMMIT" bash
#
# Why:
# - installer itself is fetched from an immutable commit
# - installed source must match the same explicit commit
# - no automatic reset --hard / pull of mutable main
# ==================================================

set -euo pipefail

REPO_URL="https://github.com/theptk1999/sshplus-manager.git"
INSTALL_DIR="/opt/sshplus-manager"
TARGET_BIN="/usr/local/sbin/sshplus"
SSHPLUS_REF="${SSHPLUS_REF:-}"

log_info() {
  echo -e "\033[1;32m[INFO]\033[0m $*"
}

log_warn() {
  echo -e "\033[1;33m[WARN]\033[0m $*" >&2
}

die() {
  echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "กรุณารัน installer ด้วย root"
  fi
}

normalize_ref() {
  SSHPLUS_REF="$(
    printf '%s' "$SSHPLUS_REF" |
      tr 'A-F' 'a-f'
  )"

  if [[ ! "$SSHPLUS_REF" =~ ^[0-9a-f]{40}$ ]]; then
    die "ต้องกำหนด SSHPLUS_REF เป็น commit SHA 40 ตัว"
  fi
}

is_expected_origin() {
  local origin="${1:-}"

  case "$origin" in
    "https://github.com/theptk1999/sshplus-manager.git" | \
    "git@github.com:theptk1999/sshplus-manager.git" | \
    "ssh://git@github.com/theptk1999/sshplus-manager.git")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  log_info "กำลังติดตั้ง git..."

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y git >/dev/null 2>&1

  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git >/dev/null 2>&1

  elif command -v yum >/dev/null 2>&1; then
    yum install -y git >/dev/null 2>&1

  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm git >/dev/null 2>&1

  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache git >/dev/null 2>&1

  else
    die "ไม่พบ package manager ที่รองรับ"
  fi
}

verify_existing_origin() {
  local origin=""

  origin="$(
    git -C "$INSTALL_DIR" \
      remote get-url origin 2>/dev/null ||
      true
  )"

  if ! is_expected_origin "$origin"; then
    die "origin ของ $INSTALL_DIR ไม่ใช่ SSHPlus repository ที่อนุญาต: $origin"
  fi
}

require_clean_tree() {
  local dirty=""

  dirty="$(
    git -C "$INSTALL_DIR" \
      status --porcelain 2>/dev/null ||
      true
  )"

  if [[ -n "$dirty" ]]; then
    die "$INSTALL_DIR มี local changes กรุณา commit/stash ก่อนติดตั้ง"
  fi
}

prepare_repo() {
  local repo_preexisting=0
  local resolved=""

  if [[ -d "$INSTALL_DIR/.git" ]]; then
    repo_preexisting=1
  elif [[ -e "$INSTALL_DIR" ]]; then
    die "$INSTALL_DIR มีอยู่แล้วแต่ไม่ใช่ Git repository"
  else
    log_info "Clone SSHPlus repository..."
    git clone --no-checkout "$REPO_URL" "$INSTALL_DIR"
  fi

  verify_existing_origin

  if (( repo_preexisting == 1 )); then
    require_clean_tree
  fi

  log_info "Fetch origin/main..."
  git -C "$INSTALL_DIR" fetch --prune origin main

  if ! git -C "$INSTALL_DIR" cat-file -e "${SSHPLUS_REF}^{commit}" 2>/dev/null; then
    log_info "Fetch commit ที่ระบุ..."
    git -C "$INSTALL_DIR" fetch origin "$SSHPLUS_REF" ||
      die "ไม่พบ commit $SSHPLUS_REF จาก origin"
  fi

  resolved="$(git -C "$INSTALL_DIR" rev-parse "${SSHPLUS_REF}^{commit}")"
  resolved="$(printf '%s' "$resolved" | tr 'A-F' 'a-f')"

  [[ "$resolved" == "$SSHPLUS_REF" ]] ||
    die "Commit ที่ resolve ได้ไม่ตรงกับ SSHPLUS_REF"

  git -C "$INSTALL_DIR" merge-base --is-ancestor "$SSHPLUS_REF" origin/main ||
    die "Commit ที่ระบุไม่ได้อยู่ในประวัติ origin/main"

  log_info "Checkout pinned commit:"
  log_info "$SSHPLUS_REF"

  git -C "$INSTALL_DIR" checkout --detach "$SSHPLUS_REF"

  if [[ -n "$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null)" ]]; then
    die "Working tree ไม่สะอาดหลัง checkout pinned commit"
  fi
}

verify_dist_checksum() {
  local dist_dir="$INSTALL_DIR/dist"
  local checksum="$dist_dir/sshplus.sh.sha256"

  [[ -s "$dist_dir/sshplus.sh" ]] ||
    die "ไม่พบ dist/sshplus.sh"

  [[ -s "$checksum" ]] ||
    die "ไม่พบ dist/sshplus.sh.sha256"

  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$dist_dir"
      sha256sum -c sshplus.sh.sha256
    ) || die "dist checksum verification failed"

  elif command -v shasum >/dev/null 2>&1; then
    local expected=""
    local actual=""

    expected="$(
      awk 'NR==1 {print $1}' "$checksum"
    )"

    actual="$(
      shasum -a 256 "$dist_dir/sshplus.sh" |
        awk '{print $1}'
    )"

    [[ "$actual" == "$expected" ]] ||
      die "dist checksum verification failed"

  else
    die "ไม่พบ SHA256 verification tool"
  fi
}

build_project() {
  log_info "กำลัง build pinned commit..."

  (
    cd "$INSTALL_DIR"
    bash scripts/build.sh
  )

  bash -n "$INSTALL_DIR/dist/sshplus.sh" ||
    die "dist/sshplus.sh syntax error"

  verify_dist_checksum
}

install_binary() {
  local staged="${TARGET_BIN}.new.$$"
  local backup=""

  if [[ -f "$TARGET_BIN" ]]; then
    backup="${TARGET_BIN}.bak.$(date +%Y%m%d_%H%M%S)"

    cp -p -- "$TARGET_BIN" "$backup" ||
      die "Backup binary เดิมไม่สำเร็จ"

    log_info "Backup binary: $backup"
  fi

  rm -f -- "$staged"

  if ! install \
       -m 755 \
       "$INSTALL_DIR/dist/sshplus.sh" \
       "$staged"; then

    rm -f -- "$staged"
    die "Stage binary ใหม่ไม่สำเร็จ"
  fi

  if ! mv -f -- "$staged" "$TARGET_BIN"; then
    rm -f -- "$staged"

    if [[ -n "$backup" && -f "$backup" ]]; then
      cp -p -- "$backup" "$TARGET_BIN" || true
    fi

    die "Atomic install ไม่สำเร็จ"
  fi

  log_info "ติดตั้งเรียบร้อย: $TARGET_BIN"
  log_info "Commit: $SSHPLUS_REF"
}

ask_run() {
  if [[ -t 0 ]]; then
    local answer=""

    read -r -p \
      "ต้องการรัน SSHPlus Manager เลยหรือไม่? (y/n): " \
      answer

    if [[ "$answer" =~ ^[Yy]$ ]]; then
      exec "$TARGET_BIN"
    fi
  else
    log_info "รันด้วยคำสั่ง: sshplus"
  fi
}

main() {
  require_root
  normalize_ref
  ensure_git
  prepare_repo
  build_project
  install_binary

  echo
  log_info "SSHPlus Manager ติดตั้งสำเร็จ"
  log_info "Pinned commit: $SSHPLUS_REF"
  log_info "รันด้วย: sshplus"
  echo

  ask_run
}

main "$@"
