# ==================================================
# Core: Service Helper
# Why: ตรวจสถานะ service แบบรองรับหลาย init system
# ==================================================

# Why: ตรวจสอบว่า service กำลังทำงานอยู่หรือไม่
svc_is_active() {
  local svc="${1:-}"
  local clean_svc="${svc%.service}"

  [[ -z "$svc" ]] && return 1

  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet "$svc" 2>/dev/null && return 0
  fi

  if command -v service >/dev/null 2>&1; then
    service "$clean_svc" status >/dev/null 2>&1 && return 0
  fi

  if command -v rc-service >/dev/null 2>&1; then
    rc-service "$clean_svc" status >/dev/null 2>&1 && return 0
  fi

  if [[ -x "/etc/init.d/${clean_svc}" ]]; then
    "/etc/init.d/${clean_svc}" status >/dev/null 2>&1 && return 0
  fi

  pgrep -f "$clean_svc" >/dev/null 2>&1
}
