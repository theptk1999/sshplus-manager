# ==================================================
# Core: Package Manager Abstraction
# Why: ติดตั้ง package ข้าม distro อย่างปลอดภัย
# ==================================================

# Why: แปลงชื่อ package ตาม distro
translate_package_name() {
  local raw_pkg="$1" final_pkg="$1"
  if command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1 || command -v zypper >/dev/null 2>&1; then
    case "$raw_pkg" in
      uuid-runtime) final_pkg="util-linux" ;; cron) final_pkg="cronie" ;;
      stunnel4) final_pkg="stunnel" ;; squid3) final_pkg="squid" ;;
    esac
  elif command -v pacman >/dev/null 2>&1; then
    case "$raw_pkg" in
      uuid-runtime) final_pkg="util-linux" ;; cron) final_pkg="cronie" ;;
      python3-pip) final_pkg="python-pip" ;; stunnel4) final_pkg="stunnel" ;;
    esac
  elif command -v apk >/dev/null 2>&1; then
    case "$raw_pkg" in
      uuid-runtime) final_pkg="util-linux" ;; cron) final_pkg="dcron" ;;
      python3-pip) final_pkg="py3-pip" ;; python3-requests) final_pkg="py3-requests" ;;
    esac
  fi
  echo "$final_pkg"
}

# Why: ตรวจว่า package ติดตั้งแล้วหรือยัง
is_pkg_installed() {
  local pkg="$1"
  if command -v dpkg >/dev/null 2>&1; then dpkg -s "$pkg" >/dev/null 2>&1
  elif command -v rpm >/dev/null 2>&1; then rpm -q "$pkg" >/dev/null 2>&1
  elif command -v pacman >/dev/null 2>&1; then pacman -Qs "^${pkg}$" >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then apk info -e "$pkg" >/dev/null 2>&1
  else return 1; fi
}

# Why: ติดตั้ง package กลาง พร้อม log
install_pkg() {
  local raw_pkg="${1:-}"
  [[ -z "$raw_pkg" ]] && return 1
  local final_pkg
  final_pkg="$(translate_package_name "$raw_pkg")"
  is_pkg_installed "$final_pkg" && return 0

  [[ -f "$INSTALL_LOG" ]] || { touch "$INSTALL_LOG" 2>/dev/null || true; chmod 600 "$INSTALL_LOG" 2>/dev/null || true; }
  log_info "กำลังติดตั้ง ${final_pkg}..."
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Installing: ${final_pkg}" >> "$INSTALL_LOG" 2>/dev/null || true

  if command -v apt-get >/dev/null 2>&1; then
    if [[ "${GLOBAL_APT_UPDATED:-0}" -eq 0 ]]; then
      DEBIAN_FRONTEND=noninteractive apt-get update -y >> "$INSTALL_LOG" 2>&1 || true
      GLOBAL_APT_UPDATED=1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$final_pkg" >> "$INSTALL_LOG" 2>&1
  elif command -v dnf >/dev/null 2>&1; then dnf install -y "$final_pkg" >> "$INSTALL_LOG" 2>&1
  elif command -v yum >/dev/null 2>&1; then yum install -y "$final_pkg" >> "$INSTALL_LOG" 2>&1
  elif command -v pacman >/dev/null 2>&1; then pacman -Sy --noconfirm "$final_pkg" >> "$INSTALL_LOG" 2>&1
  elif command -v zypper >/dev/null 2>&1; then zypper install -y "$final_pkg" >> "$INSTALL_LOG" 2>&1
  elif command -v apk >/dev/null 2>&1; then apk add --no-cache "$final_pkg" >> "$INSTALL_LOG" 2>&1
  else log_error "ไม่พบ package manager"; return 1; fi

  if [[ $? -ne 0 ]]; then log_error "ติดตั้ง ${final_pkg} ไม่สำเร็จ"; return 1; fi
  log_info "ติดตั้ง ${final_pkg} สำเร็จ"
}

# Why: ติดตั้ง dependencies พื้นฐาน
install_base_dependencies() {
  local pkg
  for pkg in screen wget python3 net-tools procps python3-pip curl uuid-runtime; do
    command -v "$pkg" >/dev/null 2>&1 || install_pkg "$pkg" || true
  done
  command -v uuidgen >/dev/null 2>&1 || install_pkg "uuid-runtime" || true
  command -v pip3 >/dev/null 2>&1 || install_pkg "python3-pip" || true
}
