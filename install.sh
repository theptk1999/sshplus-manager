#!/usr/bin/env bash
# ==================================================
# SSHPlus Manager - Remote Installer
# Why: ติดตั้งผ่าน curl one-liner บน VPS
#      curl -fsSL https://raw.githubusercontent.com/theptk1999/sshplus-manager/main/install.sh | bash
# ==================================================

set -euo pipefail

# Why: กำหนด repo กลาง
REPO_URL="https://github.com/theptk1999/sshplus-manager.git"
INSTALL_DIR="/opt/sshplus-manager"
TARGET_BIN="/usr/local/sbin/sshplus"

log_info() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*" >&2; }
die() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Why: ต้องรันด้วย root เพราะติดตั้งเข้า system path และแก้ระบบ
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "กรุณารันด้วย root: curl ... | sudo bash"
  fi
}

# Why: ติดตั้ง git ถ้ายังไม่มี
ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi

  log_info "กำลังติดตั้ง git..."

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y git >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git >/dev/null 2>&1
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm git >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache git >/dev/null 2>&1
  else
    die "ไม่พบ package manager ที่รองรับ"
  fi
}

# Why: clone หรือ pull repo
fetch_repo() {
  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log_info "อัปเดตโค้ดล่าสุด..."
    cd "$INSTALL_DIR"
    git pull --ff-only origin main >/dev/null 2>&1 || git reset --hard origin/main
  else
    log_info "ดาวน์โหลดโปรเจกต์..."
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi
}

# Why: build ไฟล์เดียวจาก modules
build_project() {
  log_info "กำลัง build..."
  bash scripts/build.sh
}

# Why: ติดตั้งไปยัง system path
install_binary() {
  if [[ ! -f dist/sshplus.sh ]]; then
    die "Build ไม่สำเร็จ ไม่พบ dist/sshplus.sh"
  fi

  install -D -m 755 dist/sshplus.sh "$TARGET_BIN"
  log_info "ติดตั้งเรียบร้อย: $TARGET_BIN"
}

# Why: ถามว่าจะรันเลยหรือไม่
ask_run() {
  if [[ -t 0 ]]; then
    read -r -p "ต้องการรัน SSHPlus Manager เลยหรือไม่? (y/n): " answer
    if [[ "$answer" =~ ^[Yy] ]]; then
      exec "$TARGET_BIN"
    fi
  else
    log_info "รันด้วยคำสั่ง: sshplus"
  fi
}

main() {
  require_root
  ensure_git
  fetch_repo
  build_project
  install_binary

  echo
  log_info "╔══════════════════════════════════════════╗"
  log_info "║   SSHPlus Manager ติดตั้งสำเร็จ!       ║"
  log_info "╠══════════════════════════════════════════╣"
  log_info "║  รันด้วย:  sshplus                     ║"
  log_info "║  อัปเดต:   bash ${INSTALL_DIR}/install.sh  ║"
  log_info "╚══════════════════════════════════════════╝"
  echo

  ask_run
}

main "$@"