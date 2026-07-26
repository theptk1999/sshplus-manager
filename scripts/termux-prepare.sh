#!/usr/bin/env bash
# ==================================================
# Termux Prepare Script
# Why: เตรียมโปรเจกต์บน Termux ก่อน build/push GitHub
#      - แก้ CRLF เป็น LF
#      - เพิ่ม newline ท้ายไฟล์
#      - ตั้งสิทธิ์
#      - ตรวจ syntax
#      - build dist
# ==================================================

# Why: strict mode เพื่อให้หยุดทันทีเมื่อมี error
set -euo pipefail

# Why: log info มาตรฐาน
log_info() {
  echo "[INFO] $*"
}

# Why: log warning แต่ไม่หยุดโปรแกรม
log_warn() {
  echo "[WARN] $*" >&2
}

# Why: จบโปรแกรมเมื่อพบ error ร้ายแรง
die() {
  echo "[ERROR] $*" >&2
  exit 1
}

# Why: ตรวจสอบว่ามีคำสั่งพื้นฐานที่จำเป็น
check_required_commands() {
  local cmd

  for cmd in bash find sed chmod xargs tail; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      die "Missing required command: $cmd"
    fi
  done
}

# Why: แก้ CRLF เป็น LF เพราะ Bash จะพังถ้าเจอ Windows line ending
fix_line_endings() {
  log_info "Fixing line endings to LF..."

  find . -type f \
    \( \
      -name '*.sh' \
      -o -name '*.bats' \
      -o -name 'sshplus' \
      -o -name 'ci.yml' \
      -o -name 'Makefile' \
      -o -name '*.md' \
      -o -name '.gitignore' \
      -o -name '.editorconfig' \
    \) \
    -exec sed -i 's/\r$//' {} +
}

# Why: ทำให้ไฟล์ text ทุกไฟล์มี newline ท้ายไฟล์
#      สำคัญมากสำหรับ build แบบรวมไฟล์
ensure_final_newline() {
  log_info "Ensuring final newline for text files..."

  local f

  while IFS= read -r -d '' f; do
    if [[ ! -s "$f" ]]; then
      printf '\n' >> "$f"
      continue
    fi

    # Why: ถ้า tail -c1 แล้ว command substitution ว่าง
    #      แปลว่าไฟล์ลงท้ายด้วย newline แล้ว
    if [[ -n "$(tail -c1 "$f")" ]]; then
      printf '\n' >> "$f"
    fi
  done < <(
    find . -type f \
      \( \
        -name '*.sh' \
        -o -name '*.bats' \
        -o -name 'sshplus' \
        -o -name 'ci.yml' \
        -o -name 'Makefile' \
        -o -name '*.md' \
        -o -name '.gitignore' \
        -o -name '.editorconfig' \
      \) \
      -print0
  )
}

# Why: ตั้งสิทธิ์ให้ไฟล์ที่ควรรันได้
set_permissions() {
  log_info "Setting executable permissions..."

  chmod +x bin/sshplus 2>/dev/null || true
  chmod +x scripts/*.sh 2>/dev/null || true
  chmod +x tests/smoke.bats 2>/dev/null || true
}

# Why: ตรวจ syntax bash ของ source files ก่อน build จริง
syntax_check_sources() {
  log_info "Checking bash syntax for source files..."

  if [[ -f bin/sshplus ]]; then
    bash -n bin/sshplus
  fi

  local f

  while IFS= read -r -d '' f; do
    bash -n "$f"
  done < <(find src scripts -type f -name '*.sh' -print0)
}

# Why: build single-file distribution
build_dist() {
  log_info "Building dist/sshplus.sh..."
  bash scripts/build.sh
}

# Why: ตรวจ syntax ของไฟล์ที่ build แล้ว
syntax_check_dist() {
  if [[ ! -f dist/sshplus.sh ]]; then
    die "dist/sshplus.sh not found after build"
  fi

  log_info "Checking bash syntax for dist/sshplus.sh..."
  bash -n dist/sshplus.sh
}

# Why: สรุปผลลัพธ์หลังเตรียมโปรเจกต์
print_result() {
  if [[ -f dist/sshplus.sh ]]; then
    log_info "Build success: dist/sshplus.sh"
  else
    log_warn "dist/sshplus.sh not found. Check build output."
  fi
}

# Why: รันทุกขั้นตอนตามลำดับ
main() {
  check_required_commands
  fix_line_endings
  ensure_final_newline
  set_permissions
  syntax_check_sources
  build_dist
  syntax_check_dist
  print_result

  log_info "Termux preparation completed."
}

main "$@"
