#!/usr/bin/env bash
# ==================================================
# Git Init Safe Script
# Why: เตรียม Git repository บน Termux / sdcard อย่างปลอดภัย
#      พร้อมตั้งค่าลดปัญหา filemode, CRLF, safe.directory
# ==================================================

# Why: strict mode เพื่อหยุดทันทีเมื่อมี error
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

# Why: ตรวจสอบว่ามี git ติดตั้งอยู่หรือไม่
check_git() {
  if ! command -v git >/dev/null 2>&1; then
    die "git not found. Install with: pkg install git"
  fi
}

# Why: ตรวจสอบว่ารันจาก root ของโปรเจกต์จริง
ensure_repo_root() {
  if [[ ! -d src || ! -d scripts ]]; then
    die "Please run this script from repository root."
  fi
}

# Why: เพิ่ม safe.directory ป้องกัน git ปฏิเสธ repo เพราะ ownership แปลกบน sdcard
fix_safe_directory() {
  local current_dir
  current_dir="$(pwd)"

  log_info "Adding safe.directory: $current_dir"
  git config --global --add safe.directory "$current_dir" 2>/dev/null || true
}

# Why: init git repository ถ้ายังไม่มี
init_repo() {
  if [[ -d .git ]]; then
    log_info "Git repository already exists."
    return 0
  fi

  log_info "Initializing Git repository..."
  git init

  # Why: ตั้ง branch หลักเป็น main
  git branch -M main 2>/dev/null || git symbolic-ref HEAD refs/heads/main
}

# Why: ตั้งค่า repo ให้เหมาะกับ sdcard/Termux
configure_repo() {
  log_info "Configuring repository..."

  # Why: sdcard มักเก็บ executable bit ไม่ถูกต้อง
  git config core.fileMode false

  # Why: ป้องกัน Git แปลง LF เป็น CRLF
  git config core.autocrlf false

  # Why: บังคับ end-of-line เป็น LF
  git config core.eol lf
}

# Why: ตั้งค่า user.name/user.email ถ้ายังไม่มี
ensure_identity() {
  local git_name
  local git_email

  git_name="$(git config user.name 2>/dev/null || true)"
  git_email="$(git config user.email 2>/dev/null || true)"

  if [[ -z "$git_name" ]]; then
    git_name="${GIT_NAME:-}"

    if [[ -z "$git_name" && -t 0 ]]; then
      read -r -p "Enter your GitHub name [SSHPlus Dev]: " git_name || true
    fi

    if [[ -z "$git_name" ]]; then
      git_name="SSHPlus Dev"
    fi

    git config user.name "$git_name"
    log_info "Set git user.name = $git_name"
  fi

  if [[ -z "$git_email" ]]; then
    git_email="${GIT_EMAIL:-}"

    if [[ -z "$git_email" && -t 0 ]]; then
      read -r -p "Enter your GitHub email [dev@localhost]: " git_email || true
    fi

    if [[ -z "$git_email" ]]; then
      git_email="dev@localhost"
    fi

    git config user.email "$git_email"
    log_info "Set git user.email = $git_email"
  fi
}

# Why: เพิ่ม remote origin ถ้ายังไม่มี
add_remote() {
  if git remote get-url origin >/dev/null 2>&1; then
    log_info "Remote origin already exists: $(git remote get-url origin)"
    return 0
  fi

  local remote_url="${GIT_REMOTE:-}"

  if [[ -z "$remote_url" && -t 0 ]]; then
    echo
    echo "Example SSH:    git@github.com:YOUR_USER/sshplus-manager.git"
    echo "Example HTTPS:  https://github.com/YOUR_USER/sshplus-manager.git"
    read -r -p "Enter GitHub remote URL or press Enter to skip: " remote_url || true
  fi

  if [[ -n "$remote_url" ]]; then
    git remote add origin "$remote_url"
    log_info "Added remote origin: $remote_url"
  else
    log_warn "No remote added. Add later with:"
    echo "  git remote add origin git@github.com:YOUR_USER/sshplus-manager.git"
  fi
}

# Why: สร้าง initial commit ถ้ามีไฟล์เปลี่ยนแปลง
initial_commit() {
  log_info "Staging files..."
  git add .

  if git diff --cached --quiet 2>/dev/null; then
    log_info "Nothing to commit."
    return 0
  fi

  local commit_msg="${GIT_COMMIT_MSG:-chore: initial modular scaffold}"

  log_info "Creating commit..."
  git commit -m "$commit_msg"
}

# Why: แสดงขั้นตอน push ต่อไป
print_next_steps() {
  cat <<'EOF'

Git repository prepared.

Next:

1. If you have not created a GitHub repository, create an empty repo first.

2. Add remote if not added:

   git remote add origin git@github.com:YOUR_USER/sshplus-manager.git

   or:

   git remote add origin https://github.com/YOUR_USER/sshplus-manager.git

3. Push:

   git push -u origin main

If using SSH and need a key:

   pkg install openssh
   ssh-keygen -t ed25519 -C "termux-sshplus"
   cat ~/.ssh/id_ed25519.pub

Then add that public key to:
   GitHub -> Settings -> SSH and GPG keys

EOF
}

# Why: รันทุกขั้นตอนตามลำดับ
main() {
  check_git
  ensure_repo_root
  fix_safe_directory
  init_repo
  configure_repo
  ensure_identity
  add_remote
  initial_commit
  print_next_steps
}

main "$@"