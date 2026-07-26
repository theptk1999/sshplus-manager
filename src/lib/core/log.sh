# ==================================================
# Core: Logging
# Why: มาตรฐานข้อความ info/warn/error และ die
# ==================================================

# Why: กำหนดสีเฉพาะเมื่อ terminal รองรับ
if [[ -t 1 ]]; then
  SSHPLUS_RED=$'\033[1;31m'
  SSHPLUS_GREEN=$'\033[1;32m'
  SSHPLUS_YELLOW=$'\033[1;33m'
  SSHPLUS_BLUE=$'\033[1;34m'
  SSHPLUS_CYAN=$'\033[1;36m'
  SSHPLUS_WHITE=$'\033[1;37m'
  SSHPLUS_NC=$'\033[0m'
else
  SSHPLUS_RED=""
  SSHPLUS_GREEN=""
  SSHPLUS_YELLOW=""
  SSHPLUS_BLUE=""
  SSHPLUS_CYAN=""
  SSHPLUS_WHITE=""
  SSHPLUS_NC=""
fi

# Why: แสดงข้อความระดับ info
log_info() {
  printf '%b[INFO]%b %s\n' "${SSHPLUS_GREEN:-}" "${SSHPLUS_NC:-}" "$*"
}

# Why: แสดงข้อความระดับ warning แต่ไม่หยุดโปรแกรม
log_warn() {
  printf '%b[WARN]%b %s\n' "${SSHPLUS_YELLOW:-}" "${SSHPLUS_NC:-}" "$*" >&2
}

# Why: แสดงข้อความระดับ error
log_error() {
  printf '%b[ERROR]%b %s\n' "${SSHPLUS_RED:-}" "${SSHPLUS_NC:-}" "$*" >&2
}

# Why: จบโปรแกรมทันทีเมื่อพบเงื่อนไขร้ายแรง
die() {
  log_error "$*"
  exit 1
}
