#!/usr/bin/env bash
# ==================================================
# Install Script
# Why: ติดตั้งไฟล์ build แล้วไปยัง /usr/local/sbin/sshplus
# ==================================================

# Why: strict mode เพื่อความปลอดภัยขณะติดตั้ง
set -euo pipefail

# Why: หา root directory ของโปรเจกต์
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Why: path ของไฟล์ build และปลายทางติดตั้ง
DIST_FILE="$ROOT_DIR/dist/sshplus.sh"
TARGET_FILE="/usr/local/sbin/sshplus"

# Why: log info
log_info() {
  echo "[INFO] $*"
}

# Why: จบเมื่อพบ error
die() {
  echo "[ERROR] $*" >&2
  exit 1
}

# Why: ต้องใช้ root เพราะติดตั้งเข้า system path
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "Please run install script as root."
  fi
}

# Why: ถ้ายังไม่มีไฟล์ build ให้สร้างก่อน
ensure_dist() {
  if [[ ! -f "$DIST_FILE" ]]; then
    log_info "Distribution not found. Running build..."
    bash "$ROOT_DIR/scripts/build.sh"
  fi
}

# Why: คัดลอกไฟล์ไปยัง system path พร้อมสิทธิ์ที่เหมาะสม
install_binary() {
  install -D -m 755 "$DIST_FILE" "$TARGET_FILE"
}

# Why: orchestrate การติดตั้ง
main() {
  require_root
  ensure_dist
  install_binary
  log_info "Installed to $TARGET_FILE"
  log_info "Run with: sshplus"
}

main "$@"
