#!/usr/bin/env bash
# ==================================================
# Phase 4+5: Real Core Infrastructure + Real Users
# Why: ย้าย core infrastructure จริงจาก sshplusthai.sh
#      และเปิดใช้งาน user management จริง
# ==================================================

set -euo pipefail

log_info() { echo "[INFO] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

write_file() {
  local path="$1" mode="${2:-644}" dir temp
  dir="$(dirname "$path")"
  mkdir -p "$dir"
  temp="$(mktemp "${dir}/.tmp.XXXXXX")"
  cat > "$temp"
  chmod "$mode" "$temp"
  mv "$temp" "$path"
}

ensure_environment() {
  [[ -d src ]] || die "Run from repo root."
  mkdir -p src/lib/core src/lib/data src/lib/features
}

# --------------------------------------------------
# constants.sh
# --------------------------------------------------
create_constants() {
  log_info "Creating src/lib/core/constants.sh"
  write_file "src/lib/core/constants.sh" 644 <<'EOF'
# ==================================================
# Core: Constants & Global State
# Why: รวม path/URL/global state ไว้ที่เดียว
# ==================================================

# Why: path กลางสำหรับ DB และ service scripts
DB_FILE="${SSHPLUS_DB_FILE:-/root/usuarios.db}"
DB_LOCK_FILE="${SSHPLUS_DB_LOCK_FILE:-${DB_FILE}.lock}"
INSTALL_LOG="/var/log/sshplus_install.log"
LIMIT_SCRIPT="/root/limit_auto.sh"
BOT_SCRIPT="/root/bot_auto.py"
WS_SCRIPT="/root/proxy_ws.py"
BADVPN_BIN="/usr/bin/badvpn-udpgw"
OPENVPN_SCRIPT="/root/openvpn-install.sh"
BOT_ENV_DIR="/etc/sshplus"
BOT_ENV_FILE="${BOT_ENV_DIR}/bot.env"

# Why: URL ภายนอกสำหรับดาวน์โหลด
URL_BADVPN="https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
URL_BADVPN_BACKUP="https://raw.githubusercontent.com/theptk1999/BadVPN/main/badvpn-udpgw64"
URL_OPENVPN="https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh"
URL_XRAY_INSTALL="https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh"

# Why: runtime state
GLOBAL_APT_UPDATED=0
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
TMP_BASE="${TMPDIR:-/tmp}"
EOF
}

# --------------------------------------------------
# package.sh
# --------------------------------------------------
create_package() {
  log_info "Creating src/lib/core/package.sh"
  write_file "src/lib/core/package.sh" 644 <<'EOF'
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
EOF
}

# --------------------------------------------------
# service.sh (full version)
# --------------------------------------------------
create_service() {
  log_info "Creating src/lib/core/service.sh (full)"
  write_file "src/lib/core/service.sh" 644 <<'EOF'
# ==================================================
# Core: Service Manager Abstraction (Full)
# Why: จัดการ service ข้าม init system
# ==================================================

svc_daemon_reload() { command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 || true; }

svc_logs() {
  local svc="${1:-}" lines="${2:-50}" clean_svc="${svc%.service}"
  [[ -z "$svc" ]] && return 1
  if command -v journalctl >/dev/null 2>&1; then journalctl -u "$svc" -n "$lines" --no-pager
  elif [[ -f /var/log/syslog ]]; then tail -n "$lines" /var/log/syslog | grep -i "$clean_svc" || true
  elif [[ -f /var/log/messages ]]; then tail -n "$lines" /var/log/messages | grep -i "$clean_svc" || true
  fi
}

svc_start() {
  local svc="${1:-}" clean_svc="${svc%.service}"
  [[ -z "$svc" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl start "$svc" >/dev/null 2>&1 && return 0
  command -v service >/dev/null 2>&1 && service "$clean_svc" start >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "$clean_svc" start >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" start >/dev/null 2>&1 && return 0
  return 1
}

svc_stop() {
  local svc="${1:-}" clean_svc="${svc%.service}"
  [[ -z "$svc" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl stop "$svc" >/dev/null 2>&1 && return 0
  command -v service >/dev/null 2>&1 && service "$clean_svc" stop >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "$clean_svc" stop >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" stop >/dev/null 2>&1 && return 0
  return 1
}

svc_restart() {
  local svc="${1:-}" clean_svc="${svc%.service}"
  [[ -z "$svc" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl restart "$svc" >/dev/null 2>&1 && return 0
  command -v service >/dev/null 2>&1 && service "$clean_svc" restart >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "$clean_svc" restart >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" restart >/dev/null 2>&1 && return 0
  return 1
}

svc_enable() {
  local svc="${1:-}" clean_svc="${svc%.service}"
  [[ -z "$svc" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl enable "$svc" >/dev/null 2>&1 && return 0
  command -v chkconfig >/dev/null 2>&1 && chkconfig "$clean_svc" on >/dev/null 2>&1 && return 0
  command -v update-rc.d >/dev/null 2>&1 && update-rc.d "$clean_svc" defaults >/dev/null 2>&1 && return 0
  command -v rc-update >/dev/null 2>&1 && rc-update add "$clean_svc" default >/dev/null 2>&1 && return 0
  return 1
}

svc_disable() {
  local svc="${1:-}" clean_svc="${svc%.service}"
  [[ -z "$svc" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl disable "$svc" >/dev/null 2>&1 && return 0
  command -v chkconfig >/dev/null 2>&1 && chkconfig "$clean_svc" off >/dev/null 2>&1 && return 0
  command -v update-rc.d >/dev/null 2>&1 && update-rc.d -f "$clean_svc" remove >/dev/null 2>&1 && return 0
  command -v rc-update >/dev/null 2>&1 && rc-update del "$clean_svc" default >/dev/null 2>&1 && return 0
  return 1
}

svc_is_active() {
  local svc="${1:-}" clean_svc="${svc%.service}"
  [[ -z "$svc" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$svc" 2>/dev/null && return 0
  command -v service >/dev/null 2>&1 && service "$clean_svc" status >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "$clean_svc" status >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" status >/dev/null 2>&1 && return 0
  pgrep -f "$clean_svc" >/dev/null 2>&1
}

svc_provision() {
  local name="${1:-}" desc="${2:-}" cmd="${3:-}" env_file="${4:-}" sysd_ext="${5:-}"
  [[ -z "$name" || -z "$desc" || -z "$cmd" ]] && return 1
  local sysd_env="" sysv_env_load=""
  if [[ -n "$env_file" ]]; then
    sysd_env="EnvironmentFile=${env_file}"
    sysv_env_load="[ -f \"${env_file}\" ] && . \"${env_file}\""
  fi
  if command -v systemctl >/dev/null 2>&1; then
    cat <<SVCEOF > "/etc/systemd/system/${name}.service"
[Unit]
Description=${desc}
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=${cmd}
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=10
${sysd_env}
${sysd_ext}
[Install]
WantedBy=multi-user.target
SVCEOF
    chmod 644 "/etc/systemd/system/${name}.service"
    svc_daemon_reload
  else
    cat <<SVCEOF > "/etc/init.d/${name}"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ${name}
# Required-Start:    \$network \$local_fs
# Required-Stop:     \$network \$local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ${desc}
### END INIT INFO
PIDFILE="/run/${name}.pid"
start() {
  if [ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null; then return 1; fi
  ${sysv_env_load}
  nohup ${cmd} >/dev/null 2>&1 &
  echo \$! > "\$PIDFILE"
}
stop() {
  if [ -f "\$PIDFILE" ]; then kill "\$(cat "\$PIDFILE")" 2>/dev/null || true; rm -f "\$PIDFILE"; fi
}
case "\$1" in
  start) start ;; stop) stop ;; restart) stop; sleep 2; start ;;
  status) [ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null && exit 0 || exit 1 ;;
  *) echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
SVCEOF
    chmod +x "/etc/init.d/${name}"
  fi
}

svc_remove() {
  local name="${1:-}"
  [[ -z "$name" ]] && return 1
  svc_stop "$name" || true
  svc_disable "$name" || true
  if command -v systemctl >/dev/null 2>&1; then
    rm -f "/etc/systemd/system/${name}.service"
    svc_daemon_reload
  else
    rm -f "/etc/init.d/${name}"
  fi
}

restart_ssh_service() { svc_restart ssh || svc_restart sshd || true; }
EOF
}

# --------------------------------------------------
# download.sh
# --------------------------------------------------
create_download() {
  log_info "Creating src/lib/core/download.sh"
  write_file "src/lib/core/download.sh" 644 <<'EOF'
# ==================================================
# Core: Secure Download Helpers
# Why: ดาวน์โหลดไฟล์ภายนอกอย่างปลอดภัย
# ==================================================

download_to_temp_file() {
  local url="${1:-}" temp_file="${2:-}"
  [[ -z "$url" || -z "$temp_file" ]] && return 1
  rm -f "$temp_file"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$temp_file"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$temp_file" "$url"
  else log_error "ไม่พบ curl หรือ wget"; return 1; fi
  [[ -s "$temp_file" ]] || { log_error "ดาวน์โหลดไม่สำเร็จ"; rm -f "$temp_file"; return 1; }
}

file_sha256() {
  local f="${1:-}"
  [[ -z "$f" || ! -f "$f" ]] && return 1
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" | awk '{print $1}'; return 0; fi
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$f" | awk '{print $1}'; return 0; fi
  return 1
}

confirm_trust_download() {
  local label="${1:-}" source_url="${2:-}" file_path="${3:-}"
  [[ -z "$label" || -z "$source_url" || -z "$file_path" || ! -f "$file_path" ]] && return 1
  local sha
  sha="$(file_sha256 "$file_path" || true)"
  clear_screen 2>/dev/null || clear
  echo -e "${MENU_BLUE:-}┌──────────────────────────────────────────────────────────────┐${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}│${MENU_BG_RED:-}              DOWNLOAD SECURITY CONFIRMATION                 ${MENU_NC:-}${MENU_BLUE:-}│${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}├──────────────────────────────────────────────────────────────┤${MENU_NC:-}"
  echo -e "  รายการ : ${label}"
  echo -e "  URL    : ${source_url}"
  echo -e "  SHA256 : ${sha:-ไม่สามารถคำนวณได้}"
  echo -e "${MENU_BLUE:-}└──────────────────────────────────────────────────────────────┘${MENU_NC:-}"
  local answer
  read -r -p "ยืนยันหรือไม่ (YES/NO): " answer
  [[ "$answer" == "YES" ]]
}

download_with_user_confirmation() {
  local label="${1:-}" source_url="${2:-}" destination_path="${3:-}" chmod_mode="${4:-}"
  [[ -z "$label" || -z "$source_url" || -z "$destination_path" ]] && return 1
  local temp_file
  temp_file="$(mktemp "${TMP_BASE:-/tmp}/secure-download.XXXXXX")" || return 1
  if ! download_to_temp_file "$source_url" "$temp_file"; then rm -f "$temp_file"; return 1; fi
  if ! confirm_trust_download "$label" "$source_url" "$temp_file"; then rm -f "$temp_file"; return 1; fi
  mv "$temp_file" "$destination_path"
  [[ -n "$chmod_mode" ]] && chmod "$chmod_mode" "$destination_path"
}
EOF
}

# --------------------------------------------------
# 10_users.sh (REAL CODE)
# --------------------------------------------------
create_real_users() {
  log_info "Creating src/lib/features/10_users.sh (REAL)"
  write_file "src/lib/features/10_users.sh" 644 <<'EOF'
# ==================================================
# Feature: User Management (REAL)
# Why: จัดการ SSH user จริงจาก sshplusthai.sh
# ==================================================

function_create_user() {
  clear_screen
  echo -e "${MENU_BLUE:-}┌──────────────────────────────────────────┐${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}│          สร้างผู้ใช้งาน SSH              ${MENU_NC:-}${MENU_BLUE:-}│${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}└──────────────────────────────────────────┘${MENU_NC:-}"
  read -r -p "ชื่อผู้ใช้งาน (Username): " username
  [[ -z "$username" ]] && return
  if ! is_username "$username"; then log_error "ห้ามใช้อักขระพิเศษ! อนุญาตแค่ a-z, 0-9, _ และ -"; pause; return; fi
  if id "$username" >/dev/null 2>&1; then log_error "ชื่อ '$username' มีอยู่แล้ว!"; pause; return; fi
  local password="" confirm_password=""
  prompt_password "รหัสผ่าน (Password): " password
  prompt_password "ยืนยันรหัสผ่าน: " confirm_password
  if [[ -z "$password" ]]; then log_error "รหัสผ่านห้ามว่าง"; pause; return; fi
  if [[ "$password" != "$confirm_password" ]]; then log_error "รหัสผ่านไม่ตรงกัน"; pause; return; fi
  read -r -p "จำนวนวัน (Days): " days
  is_uint "$days" || days=30
  read -r -p "จำกัดการเชื่อมต่อ (Limit): " limit
  is_uint "$limit" || limit=1
  local expire_date
  expire_date="$(date -d "+${days} days" +%Y-%m-%d)" || { log_error "คำนวณวันหมดอายุไม่สำเร็จ"; pause; return; }
  useradd -M -s /bin/false -e "$expire_date" "$username"
  if [[ $? -ne 0 ]]; then log_error "สร้างผู้ใช้ไม่สำเร็จ"; pause; return; fi
  printf '%s:%s\n' "$username" "$password" | chpasswd
  if [[ $? -ne 0 ]]; then userdel --force "$username" >/dev/null 2>&1 || true; log_error "ตั้งรหัสผ่านไม่สำเร็จ"; pause; return; fi
  chage -M "$days" "$username" >/dev/null 2>&1 || true
  local expire_epoch
  expire_epoch="$(date -d "$expire_date" +%s)"
  db_write_user_record "$username" "$limit" "$expire_epoch"
  local server_ip
  server_ip="$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo 'N/A')"
  clear_screen
  echo -e "${MENU_GREEN:-}[INFO]${MENU_NC:-} สร้างบัญชีสำเร็จ!"
  echo -e "  Host/IP  : ${server_ip}"
  echo -e "  Username : ${username}"
  echo -e "  Password : ${password}"
  echo -e "  Limit    : ${limit}"
  echo -e "  Expire   : $(date -d "$expire_date" +%d/%m/%Y) (${days} วัน)"
  pause
}

function_create_test() {
  clear_screen
  echo -e "${MENU_BLUE:-}┌──────────────────────────────────────────┐${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}│       สร้างไอดีทดสอบ (24ชม.)            ${MENU_NC:-}${MENU_BLUE:-}│${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}└──────────────────────────────────────────┘${MENU_NC:-}"
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ทดสอบ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  if ! is_username "$username"; then log_error "ชื่อไม่ถูกต้อง"; pause; return; fi
  if id "$username" >/dev/null 2>&1; then log_error "ชื่อมีอยู่แล้ว!"; pause; return; fi
  local password="" confirm_password=""
  prompt_password "รหัสผ่าน: " password
  prompt_password "ยืนยัน: " confirm_password
  if [[ -z "$password" || "$password" != "$confirm_password" ]]; then log_error "รหัสผ่านว่างหรือไม่ตรงกัน"; pause; return; fi
  local expire_date
  expire_date="$(date -d "+1 days" +%Y-%m-%d)" || { log_error "คำนวณวันที่ไม่สำเร็จ"; pause; return; }
  useradd -M -s /bin/false -e "$expire_date" "$username" || { log_error "สร้างผู้ใช้ไม่สำเร็จ"; pause; return; }
  printf '%s:%s\n' "$username" "$password" | chpasswd || { userdel --force "$username" >/dev/null 2>&1; log_error "ตั้งรหัสผ่านไม่สำเร็จ"; pause; return; }
  local expire_epoch
  expire_epoch="$(date -d "$expire_date" +%s)"
  db_write_user_record "$username" 1 "$expire_epoch"
  log_info "สร้างไอดีทดสอบสำเร็จ! Username: ${username} | Password: ${password}"
  pause
}

function_delete_user() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ที่จะลบ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  local user_line
  user_line="$(db_get_user_record "$username")"
  if [[ -z "$user_line" ]]; then log_error "ไม่พบผู้ใช้นี้!"; pause; return; fi
  read -r -p "ยืนยันลบ $username ? (YES/NO): " confirm_delete
  [[ "$confirm_delete" != "YES" ]] && { log_warn "ยกเลิก"; pause; return; }
  id "$username" >/dev/null 2>&1 && userdel --force "$username" >/dev/null 2>&1 || true
  db_delete_user_record "$username"
  log_info "ลบ $username เรียบร้อย!"
  pause
}

function_renew_user() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ที่จะต่ออายุ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  local user_line
  user_line="$(db_get_user_record "$username")"
  if [[ -z "$user_line" ]]; then log_error "ไม่พบผู้ใช้นี้!"; pause; return; fi
  local old_limit old_expire now
  old_limit="$(echo "$user_line" | cut -d: -f2)"
  old_expire="$(echo "$user_line" | cut -d: -f3)"
  now="$(date +%s)"
  read -r -p "จำนวนวันที่ต้องการเพิ่ม: " days
  if ! is_uint "$days" || [[ "$days" -le 0 ]]; then log_error "ต้องเป็นตัวเลข > 0"; pause; return; fi
  local new_expire
  if is_uint "$old_expire" && [[ "$old_expire" -ge "$now" ]]; then
    new_expire="$(date -d "@$old_expire + $days days" +%s)"
  else
    new_expire="$(date -d "+$days days" +%s)"
  fi
  local final_date_str
  final_date_str="$(date -d "@$new_expire" +%Y-%m-%d)"
  chage -E "$final_date_str" "$username" >/dev/null 2>&1 || true
  db_write_user_record "$username" "$old_limit" "$new_expire"
  log_info "ต่ออายุสำเร็จ! Expire ใหม่: $(date -d "@$new_expire" +%d/%m/%Y)"
  pause
}

function_users_online() {
  clear_screen
  printf "%-20s | %-10s | %-15s\n" "User" "PID" "Time"
  echo "------------------------------------------------"
  local found=0
  while read -r line; do
    local user pid etime
    user="$(sed -n 's/.*sshd: \([a-zA-Z0-9_-]*\).*/\1/p' <<< "$line")"
    pid="$(awk '{print $1}' <<< "$line")"
    etime="$(awk '{print $2}' <<< "$line")"
    if [[ -n "$user" && "$user" != "root" ]]; then
      printf "%-20s | %-10s | %-15s\n" "$user" "$pid" "$etime"
      found=1
    fi
  done < <(ps -eo pid,etime,args 2>/dev/null | grep "sshd: " | grep -v "grep" | grep -v "priv" || true)
  [[ "$found" -eq 0 ]] && echo "ไม่มีผู้ใช้กำลังออนไลน์"
  pause
}

function_change_expiry() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  local user_line
  user_line="$(db_get_user_record "$username")"
  [[ -z "$user_line" ]] && { log_error "ไม่พบ!"; pause; return; }
  read -r -p "วันหมดอายุใหม่ (YYYY-MM-DD): " new_date
  is_date "$new_date" || { log_error "รูปแบบวันที่ผิด!"; pause; return; }
  local new_epoch limit
  new_epoch="$(date -d "$new_date" +%s)"
  limit="$(echo "$user_line" | cut -d: -f2)"
  db_write_user_record "$username" "$limit" "$new_epoch"
  chage -E "$new_date" "$username" >/dev/null 2>&1 || true
  log_info "อัปเดตวันหมดอายุเป็น: $new_date"
  pause
}

function_change_limit() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  local user_line
  user_line="$(db_get_user_record "$username")"
  [[ -z "$user_line" ]] && { log_error "ไม่พบ!"; pause; return; }
  local expire_epoch
  expire_epoch="$(echo "$user_line" | cut -d: -f3)"
  read -r -p "ลิมิตใหม่: " new_limit
  if ! is_uint "$new_limit" || [[ "$new_limit" -le 0 ]]; then log_error "ต้องเป็นตัวเลข > 0"; pause; return; fi
  db_write_user_record "$username" "$new_limit" "$expire_epoch"
  log_info "อัปเดตลิมิตเป็น: $new_limit"
  pause
}

function_change_pass() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  id "$username" >/dev/null 2>&1 || { log_error "ไม่พบผู้ใช้ในระบบ!"; pause; return; }
  local newpass="" confirmpass=""
  prompt_password "รหัสผ่านใหม่: " newpass
  prompt_password "ยืนยัน: " confirmpass
  [[ -z "$newpass" ]] && { log_error "รหัสผ่านห้ามว่าง"; pause; return; }
  [[ "$newpass" != "$confirmpass" ]] && { log_error "ไม่ตรงกัน"; pause; return; }
  printf '%s:%s\n' "$username" "$newpass" | chpasswd || { log_error "เปลี่ยนรหัสผ่านไม่สำเร็จ"; pause; return; }
  log_info "เปลี่ยนรหัสผ่านสำเร็จ!"
  pause
}

function_remove_expired() {
  log_info "กำลังตรวจสอบบัญชีที่หมดอายุ..."
  db_remove_expired
  sleep 1
}

function_list_users() {
  local display_mode="${1:-}"
  [[ "$display_mode" != "inline" ]] && clear_screen
  printf "%-15s | %-10s | %-15s\n" "User" "Limit" "Expire"
  echo "------------------------------------------------"
  local user_count=0
  if [[ -f "${DB_FILE:-/root/usuarios.db}" ]]; then
    while IFS=: read -r user lim expire_epoch || [[ -n "${user:-}" ]]; do
      [[ -z "${user:-}" && -z "${lim:-}" && -z "${expire_epoch:-}" ]] && continue
      local exp_date="N/A"
      is_uint "$expire_epoch" && exp_date="$(date -d "@$expire_epoch" +%d/%m/%Y 2>/dev/null || echo 'N/A')"
      printf "%-15s | %-10s | %-15s\n" "$user" "$lim" "$exp_date"
      user_count=$((user_count + 1))
    done < "${DB_FILE:-/root/usuarios.db}"
  fi
  [[ "$user_count" -eq 0 ]] && echo "ไม่มีผู้ใช้งานในระบบ"
  [[ "$display_mode" != "inline" ]] && pause
}

function_backup_users() {
  while true; do
    clear_screen
    echo "1) สร้าง Backup"
    echo "2) Restore Backup"
    echo "0) ย้อนกลับ"
    read -r -p "เลือก: " b_opt
    case "$b_opt" in
      1)
        local backup_name="backup_users_$(date +%Y%m%d_%H%M%S).db"
        if ( flock -s 200 || exit 1; cp "${DB_FILE:-/root/usuarios.db}" "/root/$backup_name"; chmod 600 "/root/$backup_name" ) 200>"${DB_LOCK_FILE:-/root/usuarios.db.lock}"; then
          log_info "Backup: /root/$backup_name"
        else log_error "Backup ไม่สำเร็จ"; fi
        pause ;;
      2)
        ls /root/backup_users_*.db 2>/dev/null || log_error "ไม่มีไฟล์ Backup"
        read -r -p "ชื่อไฟล์ (0=ยกเลิก): " restore_file
        [[ "$restore_file" == "0" || -z "$restore_file" ]] && continue
        local restore_name="${restore_file##*/}"
        [[ -f "/root/$restore_name" ]] || { log_error "ไม่พบไฟล์"; pause; continue; }
        read -r -p "YES เพื่อยืนยัน: " confirm_restore
        [[ "$confirm_restore" != "YES" ]] && continue
        if ( flock -x 200 || exit 1; cp "/root/$restore_name" "${DB_FILE:-/root/usuarios.db}"; chmod 600 "${DB_FILE:-/root/usuarios.db}" ) 200>"${DB_LOCK_FILE:-/root/usuarios.db.lock}"; then
          db_migrate_schema_if_needed || true
          log_info "Restore สำเร็จ!"
        else log_error "Restore ไม่สำเร็จ"; fi
        pause ;;
      0) return ;;
      *) log_error "เลือกไม่ถูกต้อง"; sleep 1 ;;
    esac
  done
}
EOF
}

# --------------------------------------------------
# update user_db.sh to use DB_FILE from constants
# --------------------------------------------------
update_user_db() {
  log_info "Updating src/lib/data/user_db.sh"
  write_file "src/lib/data/user_db.sh" 644 <<'EOF'
# ==================================================
# Data: User DB Layer
# Why: จัดการ DB แบบ atomic + lock
# ==================================================

ensure_db() {
  local db="${DB_FILE:-/root/usuarios.db}"
  [[ -f "$db" ]] || touch "$db"
  chmod 600 "$db" 2>/dev/null || true
}

db_migrate_schema_if_needed() {
  local db="${DB_FILE:-/root/usuarios.db}"
  [[ -f "$db" ]] || return 0
  local temp_file
  temp_file="$(mktemp "${db}.migrate.XXXXXX")" || return 1
  if ! ( flock -x 200 || exit 1
    while IFS=: read -r f1 f2 f3 f4 extra || [[ -n "${f1:-}" ]]; do
      [[ -z "${f1:-}" && -z "${f2:-}" && -z "${f3:-}" && -z "${f4:-}" ]] && continue
      [[ -n "${extra:-}" ]] && continue
      if [[ -n "${f4:-}" ]]; then printf '%s:%s:%s\n' "$f1" "$f3" "$f4" >> "$temp_file"; continue; fi
      if [[ -n "${f3:-}" ]]; then printf '%s:%s:%s\n' "$f1" "$f2" "$f3" >> "$temp_file"; continue; fi
    done < "$db"
    chmod 600 "$temp_file"
    mv "$temp_file" "$db"
  ) 200>"${DB_LOCK_FILE:-${db}.lock}"; then rm -f "$temp_file"; return 1; fi
}

db_write_user_record() {
  local username="${1:-}" limit="${2:-1}" expire_epoch="${3:-0}"
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  [[ "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || return 1
  [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
  [[ "$expire_epoch" =~ ^[0-9]+$ ]] || expire_epoch=0
  local temp_file
  temp_file="$(mktemp "${db}.write.XXXXXX")" || return 1
  if ! ( flock -x 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 != u' "$db" > "$temp_file"
    printf '%s:%s:%s\n' "$username" "$limit" "$expire_epoch" >> "$temp_file"
    chmod 600 "$temp_file"; mv "$temp_file" "$db"
  ) 200>"$lock"; then rm -f "$temp_file"; return 1; fi
}

db_delete_user_record() {
  local username="${1:-}"
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  [[ "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || return 1
  local temp_file
  temp_file="$(mktemp "${db}.delete.XXXXXX")" || return 1
  if ! ( flock -x 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 != u' "$db" > "$temp_file"
    chmod 600 "$temp_file"; mv "$temp_file" "$db"
  ) 200>"$lock"; then rm -f "$temp_file"; return 1; fi
}

db_get_user_record() {
  local username="${1:-}"
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  [[ "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || return 1
  ( flock -s 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 == u' "$db" 2>/dev/null | head -n1
  ) 200>"$lock"
}

db_get_field() {
  local username="${1:-}" field="${2:-2}" line
  line="$(db_get_user_record "$username")"
  [[ -z "$line" ]] && return 0
  echo "$line" | cut -d: -f"$field"
}

db_list_users() {
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  ( flock -s 200 || exit 1; [[ -f "$db" ]] && cat "$db" ) 200>"$lock"
}

db_remove_expired() {
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  local current_time count=0 temp_db
  current_time="$(date +%s)"
  [[ "${EUID:-$(id -u)}" -ne 0 ]] && { log_warn "db_remove_expired requires root"; return 1; }
  temp_db="$(mktemp "${db}.expire.XXXXXX")" || return 1
  exec 200>"$lock"
  if ! flock -x 200; then rm -f "$temp_db"; exec 200>&-; return 1; fi
  if [[ -f "$db" ]]; then
    while IFS=: read -r user lim expire_epoch || [[ -n "${user:-}" ]]; do
      [[ -z "${user:-}" && -z "${lim:-}" && -z "${expire_epoch:-}" ]] && continue
      if [[ "$user" == "root" ]]; then printf '%s:%s:%s\n' "$user" "$lim" "$expire_epoch" >> "$temp_db"; continue; fi
      if [[ "$expire_epoch" =~ ^[0-9]+$ ]] && [[ "$expire_epoch" -gt 0 ]] && [[ "$current_time" -ge "$expire_epoch" ]]; then
        log_info "ลบ user หมดอายุ: $user"
        userdel --force "$user" >/dev/null 2>&1 || true
        count=$((count + 1))
      else printf '%s:%s:%s\n' "$user" "$lim" "$expire_epoch" >> "$temp_db"; fi
    done < "$db"
    chmod 600 "$temp_db"; mv "$temp_db" "$db"
  else rm -f "$temp_db"; fi
  flock -u 200; exec 200>&-
  [[ "$count" -eq 0 ]] && log_info "ไม่มีบัญชีหมดอายุ" || log_info "ลบไป $count บัญชี"
}
EOF
}

print_next() {
  cat <<'EOF'

Phase 4+5 completed.

Run:
  bash scripts/termux-prepare.sh
  bash dist/sshplus.sh

Then test on a real VPS:
  scp dist/sshplus.sh root@YOUR_VPS:/root/
  ssh root@YOUR_VPS
  bash /root/sshplus.sh

Commit:
  git add .
  git commit -m "feat: add real core infrastructure and user management"
  git push

EOF
}

main() {
  ensure_environment
  create_constants
  create_package
  create_service
  create_download
  create_real_users
  update_user_db
  print_next
}

main "$@"
