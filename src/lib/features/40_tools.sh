# ==================================================
# Feature: Tools / System Info
# Why: เก็บฟังก์ชันเครื่องมือทั่วไป
# ==================================================

# Why: stub สำหรับ speedtest
function_speedtest() {
  log_warn "TODO: move function_speedtest from sshplusthai.sh"
  pause
}

# Why: stub สำหรับเคลียร์ cache/RAM
function_otimizar() {
  log_warn "TODO: move function_otimizar from sshplusthai.sh"
  pause
}

# Why: แสดงข้อมูลระบบพื้นฐานแบบปลอดภัย
function_info_sistema() {
  clear_screen

  detect_os

  echo "=================================================="
  echo " System Information"
  echo "=================================================="
  echo "OS ID      : ${SSHPLUS_OS_ID:-unknown}"
  echo "OS Version : ${SSHPLUS_OS_VERSION_ID:-unknown}"
  echo "Kernel     : $(uname -r 2>/dev/null || echo 'N/A')"
  echo "Hostname   : $(uname -n 2>/dev/null || echo 'N/A')"
  echo "Date       : $(date 2>/dev/null || echo 'N/A')"
  echo "=================================================="

  pause
}

# Why: stub สำหรับจัดการ banner
function_banner() {
  log_warn "TODO: move function_banner from sshplusthai.sh"
  pause
}

# Why: stub สำหรับ system optimizer
function_optimize_system() {
  log_warn "TODO: move function_optimize_system from sshplusthai.sh"
  pause
}
