#!/usr/bin/env bash
# ==================================================
# Phase 2 Menu Scaffold Generator
# Why: สร้างโครงสร้างเมนูแบบ modular สำหรับ SSHPlus Manager
#      เพื่อเตรียมย้ายโค้ดจริงจาก sshplusthai.sh เข้า features
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

# Why: เขียนไฟล์แบบปลอดภัยผ่าน temp file + mv
write_file() {
  local path="$1"
  local mode="${2:-644}"
  local dir
  local temp

  dir="$(dirname "$path")"
  mkdir -p "$dir"

  temp="$(mktemp "${dir}/.tmp.XXXXXX")"
  cat > "$temp"
  chmod "$mode" "$temp"
  mv "$temp" "$path"
}

# Why: ตรวจสอบว่ารันจาก root ของโปรเจกต์จริง
ensure_environment() {
  if [[ ! -d src ]]; then
    die "Please run this script from repository root."
  fi

  mkdir -p src/lib/core
  mkdir -p src/lib/data
  mkdir -p src/lib/features
}

# Why: สร้าง UI helpers เช่น pause และ clear_screen
create_ui_helpers() {
  log_info "Creating src/lib/core/ui.sh"

  write_file "src/lib/core/ui.sh" 644 <<'EOF_UI'
# ==================================================
# Core: UI Helpers
# Why: ฟังก์ชัน UI พื้นฐานสำหรับเมนู interactive
# ==================================================

# Why: หยุดรอผู้ใช้กด Enter เฉพาะเมื่อเป็น interactive shell
pause() {
  if [[ ! -t 0 ]]; then
    return 0
  fi

  read -r -p "Press Enter to continue..."
}

# Why: ล้างหน้าจอเฉพาะเมื่ออยู่บน terminal จริง
clear_screen() {
  if [[ -t 1 ]]; then
    clear
  fi
}
EOF_UI
}

# Why: สร้างไฟล์ feature สำหรับ user management
create_user_feature() {
  log_info "Creating src/lib/features/10_users.sh"

  write_file "src/lib/features/10_users.sh" 644 <<'EOF_USERS'
# ==================================================
# Feature: User Management
# Why: เก็บฟังก์ชันเกี่ยวกับผู้ใช้ SSH
#      ตอนนี้เป็น stub เพื่อเตรียมย้ายโค้ดจริงจาก sshplusthai.sh
# ==================================================

# Why: stub สำหรับสร้างผู้ใช้ใหม่
function_create_user() {
  log_warn "TODO: move function_create_user from sshplusthai.sh"
  pause
}

# Why: stub สำหรับสร้างไอดีทดสอบ
function_create_test() {
  log_warn "TODO: move function_create_test from sshplusthai.sh"
  pause
}

# Why: stub สำหรับลบผู้ใช้
function_delete_user() {
  log_warn "TODO: move function_delete_user from sshplusthai.sh"
  pause
}

# Why: stub สำหรับต่ออายุผู้ใช้
function_renew_user() {
  log_warn "TODO: move function_renew_user from sshplusthai.sh"
  pause
}

# Why: stub สำหรับแสดงผู้ใช้กำลังออนไลน์
function_users_online() {
  log_warn "TODO: move function_users_online from sshplusthai.sh"
  pause
}

# Why: stub สำหรับแก้วันหมดอายุ
function_change_expiry() {
  log_warn "TODO: move function_change_expiry from sshplusthai.sh"
  pause
}

# Why: stub สำหรับแก้ limit
function_change_limit() {
  log_warn "TODO: move function_change_limit from sshplusthai.sh"
  pause
}

# Why: stub สำหรับเปลี่ยนรหัสผ่าน
function_change_pass() {
  log_warn "TODO: move function_change_pass from sshplusthai.sh"
  pause
}

# Why: เรียก db layer เพื่อล้างผู้ใช้หมดอายุ
function_remove_expired() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_warn "This function requires root privileges."
    pause
    return 0
  fi

  db_remove_expired
  pause
}

# Why: แสดงรายชื่อผู้ใช้จาก DB แบบพื้นฐาน
function_list_users() {
  clear_screen

  local db_file="${SSHPLUS_DB_FILE:-/root/usuarios.db}"

  if [[ ! -f "$db_file" ]]; then
    log_warn "DB file not found: $db_file"
    pause
    return 0
  fi

  printf '%-15s | %-10s | %-15s\n' "User" "Limit" "Expire"
  printf '%s\n' "------------------------------------------------"

  local user
  local limit
  local expire_epoch
  local expire_date

  while IFS=: read -r user limit expire_epoch || [[ -n "${user:-}" ]]; do
    if [[ -z "${user:-}" && -z "${limit:-}" && -z "${expire_epoch:-}" ]]; then
      continue
    fi

    expire_date="Never"

    if [[ "$expire_epoch" =~ ^[0-9]+$ ]] && [[ "$expire_epoch" -gt 0 ]]; then
      expire_date="$(date -d "@$expire_epoch" +%d/%m/%Y 2>/dev/null || echo "$expire_epoch")"
    fi

    printf '%-15s | %-10s | %-15s\n' "$user" "$limit" "$expire_date"
  done < <(db_list_users)

  pause
}

# Why: stub สำหรับ backup/restore DB
function_backup_users() {
  log_warn "TODO: move function_backup_users from sshplusthai.sh"
  pause
}
EOF_USERS
}

# Why: สร้างไฟล์ feature สำหรับ network/port/proxy
create_network_feature() {
  log_info "Creating src/lib/features/20_network.sh"

  write_file "src/lib/features/20_network.sh" 644 <<'EOF_NETWORK'
# ==================================================
# Feature: Network / Ports / Proxy
# Why: เก็บฟังก์ชันเกี่ยวกับ port, firewall, proxy, vpn
# ==================================================

# Why: stub สำหรับจัดการ port
function_mode_connection() {
  log_warn "TODO: move function_mode_connection from sshplusthai.sh"
  pause
}

# Why: stub สำหรับดู traffic
function_trafego() {
  log_warn "TODO: move function_trafego from sshplusthai.sh"
  pause
}

# Why: stub สำหรับจัดการ firewall
function_firewall() {
  log_warn "TODO: move function_firewall from sshplusthai.sh"
  pause
}

# Why: stub สำหรับ WebSocket proxy
function_websocket() {
  log_warn "TODO: move function_websocket from sshplusthai.sh"
  pause
}

# Why: stub สำหรับ OpenVPN
function_openvpn() {
  log_warn "TODO: move function_openvpn from sshplusthai.sh"
  pause
}

# Why: stub สำหรับ Xray/V2Ray
function_v2ray_manager() {
  log_warn "TODO: move function_v2ray_manager from sshplusthai.sh"
  pause
}
EOF_NETWORK
}

# Why: สร้างไฟล์ feature สำหรับ services
create_services_feature() {
  log_info "Creating src/lib/features/30_services.sh"

  write_file "src/lib/features/30_services.sh" 644 <<'EOF_SERVICES'
# ==================================================
# Feature: Services
# Why: เก็บฟังก์ชันเกี่ยวกับ service อัตโนมัติต่างๆ
# ==================================================

# Why: stub สำหรับ SSH limiter
function_toggle_limit() {
  log_warn "TODO: move function_toggle_limit from sshplusthai.sh"
  pause
}

# Why: stub สำหรับ BadVPN
function_toggle_badvpn() {
  log_warn "TODO: move function_toggle_badvpn from sshplusthai.sh"
  pause
}

# Why: stub สำหรับ Telegram bot
function_toggle_bot() {
  log_warn "TODO: move function_toggle_bot from sshplusthai.sh"
  pause
}

# Why: stub สำหรับ auto menu
function_auto_menu() {
  log_warn "TODO: move function_auto_menu from sshplusthai.sh"
  pause
}

# Why: stub สำหรับเครื่องมือเสริม
function_ferramentas() {
  log_warn "TODO: move function_ferramentas from sshplusthai.sh"
  pause
}
EOF_SERVICES
}

# Why: สร้างไฟล์ feature สำหรับ tools/system info
create_tools_feature() {
  log_info "Creating src/lib/features/40_tools.sh"

  write_file "src/lib/features/40_tools.sh" 644 <<'EOF_TOOLS'
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
EOF_TOOLS
}

# Why: สร้าง main.sh ใหม่ให้มีเมนูหลักและ dispatcher
create_main() {
  log_info "Replacing src/main.sh"

  write_file "src/main.sh" 644 <<'EOF_MAIN'
# ==================================================
# Application Main
# Why: เมนูหลักและ dispatcher สำหรับ feature functions
# ==================================================

# Why: แสดงเมนูหลัก
show_main_menu() {
  clear_screen

  cat <<'MENU'
==================================================
 SSHPlus Manager - Modular Menu
==================================================
 01) Create user
 02) Create test user
 03) Delete user
 04) Renew user
 05) Online users
 06) Change expiry
 07) Change limit
 08) Change password
 09) Remove expired users
 10) List users
 11) Backup users
 12) Port manager
 13) Speedtest
 14) Clear cache
 15) Traffic
 16) Firewall
 17) System info
 18) Banner
 19) SSH limiter
 20) BadVPN
 21) Auto menu
 22) Telegram bot
 23) Tools
 24) WebSocket
 25) OpenVPN
 26) System optimizer
 27) Xray manager
 00) Exit
==================================================
MENU
}

# Why: bootstrap เบาๆ แล้วเข้าเมนู
main() {
  detect_os
  log_info "OS detected: ${SSHPLUS_OS_ID:-unknown}"

  # Why: ถ้ารันด้วย root ให้เตรียม DB ไว้ล่วงหน้า
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    ensure_db || true
    db_migrate_schema_if_needed || true
  fi

  # Why: ถ้าไม่ใช่ interactive shell ให้จบเลย
  #      เพื่อป้องกัน CI หรือ automation hang
  if [[ ! -t 0 ]]; then
    echo "SSHPlus Manager - Phase 2 scaffold ready"
    return 0
  fi

  local option

  while true; do
    show_main_menu

    if ! read -r -p "Select menu: " option; then
      break
    fi

    case "$option" in
      01|1) function_create_user ;;
      02|2) function_create_test ;;
      03|3) function_delete_user ;;
      04|4) function_renew_user ;;
      05|5) function_users_online ;;
      06|6) function_change_expiry ;;
      07|7) function_change_limit ;;
      08|8) function_change_pass ;;
      09|9) function_remove_expired ;;
      10) function_list_users ;;
      11) function_backup_users ;;
      12) function_mode_connection ;;
      13) function_speedtest ;;
      14) function_otimizar ;;
      15) function_trafego ;;
      16) function_firewall ;;
      17) function_info_sistema ;;
      18) function_banner ;;
      19) function_toggle_limit ;;
      20) function_toggle_badvpn ;;
      21) function_auto_menu ;;
      22) function_toggle_bot ;;
      23) function_ferramentas ;;
      24) function_websocket ;;
      25) function_openvpn ;;
      26) function_optimize_system ;;
      27) function_v2ray_manager ;;
      00|0)
        log_info "Good bye"
        return 0
        ;;
      *)
        log_error "Invalid menu"
        sleep 1
        ;;
    esac
  done
}
EOF_MAIN
}

# Why: แทนที่ build.sh ให้รองรับ auto-load feature modules
update_build_script() {
  log_info "Replacing scripts/build.sh"

  write_file "scripts/build.sh" 755 <<'EOF_BUILD'
#!/usr/bin/env bash
# ==================================================
# Build Script
# Why: รวม module หลายไฟล์เป็นไฟล์เดียวสำหรับ distribution
#      รองรับ auto-load จาก core/data/features
# ==================================================

# Why: strict mode เพื่อหยุดทันทีเมื่อ build พลาด
set -euo pipefail

# Why: หา root directory ของโปรเจกต์
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Why: กำหนด path ของไฟล์ผลลัพธ์
DIST_DIR="$ROOT_DIR/dist"
OUT_FILE="$DIST_DIR/sshplus.sh"

# Why: log info สำหรับ build process
log_info() {
  echo "[INFO] $*"
}

# Why: จบ build เมื่อพบ error
die() {
  echo "[ERROR] $*" >&2
  exit 1
}

# Why: ล้าง dist เก่าเพื่อให้ build artifact สะอาดเสมอ
prepare_dist() {
  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR"
}

# Why: เขียน header ของไฟล์ distribution
write_header() {
  cat > "$OUT_FILE" <<'HEADER'
#!/usr/bin/env bash
# ==================================================
# SSHPlus Manager - Single-file Distribution
# Generated by scripts/build.sh
# ==================================================

# Why: strict mode สำหรับ runtime
set -u
set -o pipefail

# Why: locale คงที่
export LC_ALL=C

# Why: umask ปลอดภัย
umask 077
HEADER
}

# Why: เพิ่ม module หนึ่งไฟล์ โดยตัด shebang ทิ้ง และบังคับ newline หลังไฟล์
append_module() {
  local module="$1"
  local full_path="$ROOT_DIR/$module"

  if [[ ! -f "$full_path" ]]; then
    die "Missing module: $module"
  fi

  log_info "Appending $module"

  # Why: ตัด shebang ของ module ออก เพราะไฟล์รวมมี shebang เดียว
  sed -e '1{/^#!/d}' "$full_path" >> "$OUT_FILE"

  # Why: บังคับ newline หลังแต่ละ module
  printf '\n' >> "$OUT_FILE"
}

# Why: เพิ่ม modules ทั้งหมดจาก directory ที่กำหนด
add_modules_from_dir() {
  local dir="$1"
  local full_dir="$ROOT_DIR/$dir"

  if [[ ! -d "$full_dir" ]]; then
    return 0
  fi

  local file_path
  local relative_path

  while IFS= read -r -d '' file_path; do
    relative_path="${file_path#"$ROOT_DIR"/}"
    MODULES+=("$relative_path")
  done < <(find "$full_dir" -type f -name '*.sh' -print0 | sort -z)
}

# Why: รวบรวม module ทั้งหมดตามลำดับการโหลด
collect_modules() {
  MODULES=()

  # Why: core ต้องโหลดก่อน
  add_modules_from_dir "src/lib/core"

  # Why: data layer โหลดหลัง core
  add_modules_from_dir "src/lib/data"

  # Why: features โหลดหลัง data
  add_modules_from_dir "src/lib/features"

  # Why: main ต้องโหลดหลังสุด
  MODULES+=("src/main.sh")
}

# Why: วนรวมทุก module ตามลำดับที่กำหนด
append_modules() {
  local module

  for module in "${MODULES[@]}"; do
    append_module "$module"
  done
}

# Why: เพิ่ม main dispatcher ตอนท้ายของไฟล์ distribution
append_entrypoint_call() {
  printf '\nmain "$@"\n' >> "$OUT_FILE"
}

# Why: ตั้งสิทธิ์ให้ไฟล์ dist รันได้
make_executable() {
  chmod 755 "$OUT_FILE" 2>/dev/null || true
}

# Why: สร้าง checksum สำหรับตรวจสอบความสมบูรณ์ของ artifact
write_checksum() {
  (
    cd "$DIST_DIR"

    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum sshplus.sh > sshplus.sh.sha256
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 sshplus.sh > sshplus.sh.sha256
    else
      log_info "No sha256 tool found. Skip checksum."
    fi
  )
}

# Why: orchestrate build ทั้งหมด
main() {
  prepare_dist
  write_header
  collect_modules
  append_modules
  append_entrypoint_call
  make_executable
  write_checksum
  log_info "Build completed: $OUT_FILE"
}

main "$@"
EOF_BUILD
}

# Why: สรุปขั้นตอนถัดไป
print_next_steps() {
  cat <<'EOF'

Phase 2 scaffold completed.

Next commands:

  bash scripts/termux-prepare.sh
  bash dist/sshplus.sh

Then commit:

  git add .
  git commit -m "feat: add phase2 modular menu scaffold"

After that, start moving real code from sshplusthai.sh
into files under:

  src/lib/features/

EOF
}

# Why: รันทุกขั้นตอนตามลำดับ
main() {
  ensure_environment
  create_ui_helpers
  create_user_feature
  create_network_feature
  create_services_feature
  create_tools_feature
  create_main
  update_build_script
  print_next_steps
}

main "$@"
