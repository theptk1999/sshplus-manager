#!/usr/bin/env bash
# ==================================================
# GitHub Push Helper
# Why: ช่วยตรวจและ push โปรเจกต์ขึ้น GitHub จาก Termux
# ==================================================

# Why: strict mode เพื่อหยุดเมื่อมี error
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

# Why: ตรวจสอบว่ารันจาก root ของโปรเจกต์จริง
ensure_repo_root() {
  if [[ ! -d src || ! -d scripts ]]; then
    die "Please run this script from repository root."
  fi
}

# Why: เพิ่ม safe.directory ป้องกันปัญหา ownership บน sdcard
fix_safe_directory() {
  local current_dir
  current_dir="$(pwd)"

  git config --global --add safe.directory "$current_dir" 2>/dev/null || true
}

# Why: ตรวจสอบ branch ปัจจุบันให้เป็น main
ensure_branch_main() {
  local branch
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"

  if [[ -z "$branch" ]]; then
    log_warn "Cannot detect branch. Trying to set main..."
    git checkout -b main 2>/dev/null || git symbolic-ref HEAD refs/heads/main
    return 0
  fi

  if [[ "$branch" != "main" ]]; then
    log_warn "Current branch is '$branch'. Switching to main if possible..."
    git checkout main 2>/dev/null || git checkout -b main 2>/dev/null || true
  fi
}

# Why: ตรวจสอบ remote origin
ensure_remote() {
  if git remote get-url origin >/dev/null 2>&1; then
    log_info "Remote origin: $(git remote get-url origin)"
    return 0
  fi

  local remote_url="${GIT_REMOTE:-}"

  if [[ -z "$remote_url" && -t 0 ]]; then
    read -r -p "Enter GitHub remote URL: " remote_url || true
  fi

  if [[ -z "$remote_url" ]]; then
    die "No remote origin. Add with: git remote add origin <URL>"
  fi

  git remote add origin "$remote_url"
  log_info "Added remote origin: $remote_url"
}

# Why: สร้าง commit ถ้ายังไม่มีอะไร commit
ensure_commit() {
  # Why: กรณี repo ว่างเปล่า ยังไม่มี commit แรก
  if ! git rev-parse HEAD >/dev/null 2>&1; then
    log_info "No commit found. Creating initial commit..."
    git add .
    git commit -m "${GIT_COMMIT_MSG:-chore: initial modular scaffold}"
    return 0
  fi

  # Why: กรณีมีไฟล์แก้ไขค้างอยู่ ให้ commit ก่อน push
  if [[ -n "$(git status --porcelain)" ]]; then
    log_info "Uncommitted changes found. Committing..."
    git add .
    git commit -m "${GIT_COMMIT_MSG:-chore: update project}"
  else
    log_info "Working tree clean."
  fi
}

# Why: แสดงสถานะก่อน push
show_status() {
  log_info "Git status:"
  git status --short || true

  log_info "Latest commits:"
  git log --oneline -n 5 || true
}

# Why: push ขึ้น GitHub
push_to_github() {
  log_info "Pushing to origin/main..."

  if git push -u origin main; then
    log_info "Push completed."
    return 0
  fi

  log_warn "Push failed."
  cat <<'EOF'

Possible fixes:

1. If GitHub asks for password, use Personal Access Token, not your account password.

2. If repository has existing README/LICENSE, run:

   git pull --rebase origin main --allow-unrelated-histories
   git push -u origin main

3. If using SSH and permission denied, test with:

   ssh -T git@github.com

EOF
  return 1
}

# Why: รันทุกขั้นตอนตามลำดับ
main() {
  ensure_repo_root
  fix_safe_directory
  ensure_branch_main
  ensure_remote
  ensure_commit
  show_status
  push_to_github
}

main "$@"