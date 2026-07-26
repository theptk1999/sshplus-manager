# ==================================================
# Core: Guard / OS Detection
# Why: ตรวจสอบสิทธิ์ root และตรวจจับ OS
# ==================================================

# Why: ตรวจจับ distro เพื่อใช้ใน package/service abstraction
detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    SSHPLUS_OS_ID="${ID:-linux}"
    SSHPLUS_OS_VERSION_ID="${VERSION_ID:-}"
  else
    SSHPLUS_OS_ID="$(uname -s 2>/dev/null || echo linux)"
    SSHPLUS_OS_VERSION_ID=""
  fi
}

# Why: บังคับว่าต้องรันด้วย root เพราะสคริปต์แก้ระบบระดับลึก
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This command requires root privileges. Use sudo -i."
  fi
}
