#!/usr/bin/env bash
# ==================================================
# Prepare GitHub Script
# Why: ตรวจความพร้อมของโปรเจกต์ก่อน push/release ขึ้น GitHub
#      - ตรวจ git repo
#      - ตรวจ secret เบื้องต้น
#      - ตรวจ CRLF
#      - ตรวจ build
#      - แนะนำ flow ที่เหมาะสม
# ==================================================

# Why: strict mode เพื่อหยุดเมื่อมี error ระหว่างตรวจ
set -euo pipefail

# Why: log info มาตรฐาน
log_info() {
  echo "[INFO] $*"
}

# Why: log warning แต่ไม่หยุดโปรแกรม
log_warn() {
  echo "[WARN] $*" >&2
}

# Why: log error
log_error() {
  echo "[ERROR] $*" >&2
}

# Why: จบโปรแกรมเมื่อพบ error ร้ายแรง
die() {
  log_error "$*"
  exit 1
}

# Why: ตรวจสอบว่ามี git ติดตั้งอยู่หรือไม่
check_git_installed() {
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

# Why: เพิ่มรายการที่ห้าม commit ขึ้น GitHub
ensure_gitignore() {
  log_info "Checking .gitignore..."

  touch .gitignore

  local needed_items=(
    "dist/"
    "*.log"
    "*.tmp"
    "*.bak"
    ".env"
    "*.env"
    "*.key"
    "*.pem"
    "id_rsa"
    "id_ed25519"
    "usuarios.db"
    "usuarios.db.lock"
  )

  local item

  for item in "${needed_items[@]}"; do
    if ! grep -qxF "$item" .gitignore; then
      echo "$item" >> .gitignore
      log_info "Added to .gitignore: $item"
    fi
  done
}

# Why: ตรวจสอบว่าเป็น git repository แล้วหรือยัง
check_git_repository() {
  if [[ ! -d .git ]]; then
    log_warn "This directory is not a Git repository yet."
    log_info "Run this first:"
    echo "  bash scripts/git-init-safe.sh"
  else
    log_info "Git repository found."
  fi
}

# Why: ตรวจสอบ branch ปัจจุบัน
check_branch() {
  if [[ ! -d .git ]]; then
    return 0
  fi

  local branch
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"

  if [[ -z "$branch" ]]; then
    log_warn "Cannot detect current branch."
    return 0
  fi

  if [[ "$branch" != "main" ]]; then
    log_warn "Current branch is '$branch'. Recommended branch is 'main'."
  else
    log_info "Current branch is main."
  fi
}

# Why: ตรวจสอบ remote origin
check_remote() {
  if [[ ! -d .git ]]; then
    return 0
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    log_info "Remote origin: $(git remote get-url origin)"
  else
    log_warn "No remote origin found."
    log_info "Add later with:"
    echo "  git remote add origin git@github.com:YOUR_USER/sshplus-manager.git"
  fi
}

# Why: ตรวจสอบว่ามีไฟล์ที่ยังไม่ได้ commit หรือไม่
check_uncommitted_changes() {
  if [[ ! -d .git ]]; then
    return 0
  fi

  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    log_warn "You have uncommitted changes."
    log_info "Review with: git status"
  else
    log_info "Working tree clean."
  fi
}

# Why: ตรวจหา Windows line ending ที่ทำให้ Bash พัง
check_crlf() {
  log_info "Checking CRLF line endings..."

  local found=0
  local f

  while IFS= read -r -d '' f; do
    if grep -qI $'\r' "$f" 2>/dev/null; then
      log_warn "CRLF found: $f"
      found=1
    fi
  done < <(
    find . -type f \
      \( \
        -name '*.sh' \
        -o -name '*.bats' \
        -o -name '*.yml' \
        -o -name 'sshplus' \
        -o -name 'Makefile' \
      \) \
      -not -path './.git/*' \
      -not -path './dist/*' \
      -print0
  )

  if [[ "$found" -eq 0 ]]; then
    log_info "No CRLF problems found."
  else
    log_warn "Fix with:"
    echo "  bash scripts/termux-prepare.sh"
  fi
}

# Why: ตรวจหา secret หรือข้อมูลที่ไม่ควรขึ้น GitHub
check_secrets() {
  log_info "Scanning for possible secrets..."

  local patterns=(
    "BOT_TOKEN="
    "ADMIN_ID="
    "PRIVATE KEY"
    "BEGIN OPENSSH PRIVATE KEY"
    "BEGIN RSA PRIVATE KEY"
    "id_rsa"
    "id_ed25519"
    "api[_-]?key"
    "password[[:space:]]*="
    "token[[:space:]]*="
  )

  local pattern
  local found=0

  for pattern in "${patterns[@]}"; do
    if grep -RInE "$pattern" . \
      --exclude-dir=.git \
      --exclude-dir=dist \
      --exclude="*.log" \
      --exclude="prepare-github.sh" \
      2>/dev/null; then
      log_warn "Possible sensitive pattern: $pattern"
      found=1
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    log_info "No obvious secrets found."
  else
    log_warn "Please review the matches above before pushing to GitHub."
    log_warn "Do not commit Telegram token, SSH keys, passwords, or private data."
  fi
}

# Why: ตรวจว่า build script ยังทำงานได้
check_build() {
  if [[ ! -f scripts/build.sh ]]; then
    log_warn "scripts/build.sh not found."
    return 0
  fi

  log_info "Running build..."
  bash scripts/build.sh

  if [[ ! -f dist/sshplus.sh ]]; then
    die "Build did not produce dist/sshplus.sh"
  fi

  log_info "Checking dist syntax..."
  bash -n dist/sshplus.sh

  log_info "Build OK."
}

# Why: แสดงคำแนะนำ GitHub flow ที่เหมาะสำหรับโปรเจกต์นี้
print_recommendation() {
  cat <<'EOF'

==================================================
 Recommended GitHub Flow for SSHPlus Manager
==================================================

1. During development:
   - Keep repository PRIVATE first.
   - Work on main branch if solo developer.
   - Commit often with clear messages.

2. Before making repository public:
   - Remove all secrets.
   - Add README.md.
   - Add LICENSE if you want open source.
   - Test on a clean VPS.
   - Make sure GitHub Actions passes.

3. Release strategy:
   - Use semantic version tags:
       v0.1.0
       v0.2.0
       v1.0.0

   - Let GitHub Actions build:
       dist/sshplus.sh
       dist/sshplus.sh.sha256

   - Publish those files in GitHub Releases.

4. User installation:
   Users should download release artifacts, not clone source.

   Example:

     curl -fsSL https://github.com/YOUR_USER/sshplus-manager/releases/latest/download/sshplus.sh -o sshplus.sh
     curl -fsSL https://github.com/YOUR_USER/sshplus-manager/releases/latest/download/sshplus.sh.sha256 -o sshplus.sh.sha256
     sha256sum -c sshplus.sh.sha256
     chmod +x sshplus.sh
     sudo ./sshplus.sh

5. Suggested visibility:

   Private repo:
     - While unfinished
     - While testing
     - If you do not want public distribution yet

   Public repo:
     - When stable
     - When secrets are removed
     - When you choose a license
     - When you want community feedback

==================================================
EOF
}

# Why: รันทุกขั้นตอนตามลำดับ
main() {
  check_git_installed
  ensure_repo_root
  ensure_gitignore
  check_git_repository
  check_branch
  check_remote
  check_uncommitted_changes
  check_crlf
  check_secrets
  check_build
  print_recommendation

  log_info "GitHub preparation check completed."
}

main "$@"
