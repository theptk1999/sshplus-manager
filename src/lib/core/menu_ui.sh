# ==================================================
# Core: Original Menu UI
# Why: แสดงเมนูหลักแบบ sshplusthai.sh เดิม
# ==================================================

# Why: ใช้สีจาก log.sh แต่ตั้งชื่อให้ตรงกับโค้ดเมนูเดิม
MENU_RED="${SSHPLUS_RED:-}"
MENU_GREEN="${SSHPLUS_GREEN:-}"
MENU_YELLOW="${SSHPLUS_YELLOW:-}"
MENU_BLUE="${SSHPLUS_BLUE:-}"
MENU_CYAN="${SSHPLUS_CYAN:-}"
MENU_WHITE="${SSHPLUS_WHITE:-}"
MENU_BG_RED="${SSHPLUS_BG_RED:-}"
MENU_NC="${SSHPLUS_NC:-}"

# Why: สถานะ service แบบ icon
MENU_ON="${MENU_GREEN}●${MENU_NC}"
MENU_OFF="${MENU_RED}○${MENU_NC}"

# Why: wrapper ตรวจ service แบบปลอดภัย
service_active() {
  local svc="${1:-}"

  if declare -F svc_is_active >/dev/null 2>&1; then
    svc_is_active "${svc:-}"
    return $?
  fi

  return 1
}

# Why: คำนวณ CPU usage จาก /proc/stat แบบ sample สั้นๆ
get_cpu_usage() {
  if [[ ! -r /proc/stat ]]; then
    echo 0
    return 0
  fi

  local cpu1 cpu2
  local _ u1 n1 s1 i1 w1 q1 sq1 st1 _
  local _ u2 n2 s2 i2 w2 q2 sq2 st2 _

  cpu1="$(grep '^cpu ' /proc/stat 2>/dev/null || true)"
  if [[ -z "$cpu1" ]]; then
    echo 0
    return 0
  fi

  read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ <<< "$cpu1"

  sleep 0.2 2>/dev/null || sleep 1

  cpu2="$(grep '^cpu ' /proc/stat 2>/dev/null || true)"
  if [[ -z "$cpu2" ]]; then
    echo 0
    return 0
  fi

  read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ <<< "$cpu2"

  u1=${u1:-0}; n1=${n1:-0}; s1=${s1:-0}; i1=${i1:-0}
  w1=${w1:-0}; q1=${q1:-0}; sq1=${sq1:-0}; st1=${st1:-0}

  u2=${u2:-0}; n2=${n2:-0}; s2=${s2:-0}; i2=${i2:-0}
  w2=${w2:-0}; q2=${q2:-0}; sq2=${sq2:-0}; st2=${st2:-0}

  local total1 total2 idle1 idle2

  total1=$((u1 + n1 + s1 + i1 + w1 + q1 + sq1 + st1))
  total2=$((u2 + n2 + s2 + i2 + w2 + q2 + sq2 + st2))

  idle1=$((i1 + w1))
  idle2=$((i2 + w2))

  if (( total2 > total1 )); then
    echo $((100 * (total2 - total1 - (idle2 - idle1)) / (total2 - total1)))
  else
    echo 0
  fi
}

# Why: รวบรวมข้อมูลระบบสำหรับแสดงบน header
get_system_info() {
  full_os="Linux"
  os_name="Linux"
  ver_name=""
  time_now=""
  ram_display="N/A"
  ram_per=0
  cpu_cores=1
  cpu_use=0
  total_users=0
  onlines_count=0
  expired_count=0

  if [[ -f /etc/os-release ]]; then
    os_name="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 | awk '{print $1}')"
    ver_name="$(grep VERSION_ID /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    full_os="${os_name} ${ver_name}"
  else
    full_os="$(uname -o 2>/dev/null || echo Linux)"
    os_name="$(uname -s 2>/dev/null || echo Linux)"
  fi

  time_now="$(date +%H:%M:%S 2>/dev/null || echo '')"

  local ram_total_mb ram_used_mb

  if command -v free >/dev/null 2>&1; then
    ram_total_mb="$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}')"
    ram_used_mb="$(free -m 2>/dev/null | awk '/^Mem:/ {print $3}')"
    ram_display="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')"
  elif [[ -r /proc/meminfo ]]; then
    local ram_total_kb ram_avail_kb

    ram_total_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    ram_avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"

    ram_total_mb=$((ram_total_kb / 1024))
    ram_used_mb=$(((ram_total_kb - ram_avail_kb) / 1024))
    ram_display="${ram_total_mb}M"
  fi

  if declare -F is_uint >/dev/null 2>&1; then
    if is_uint "${ram_total_mb:-}" && [[ "${ram_total_mb:-0}" -gt 0 ]]; then
      ram_per=$(( ${ram_used_mb:-0} * 100 / ram_total_mb ))
    fi
  fi

  cpu_cores="$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)"
  cpu_use="$(get_cpu_usage)"

  local db_file="${SSHPLUS_DB_FILE:-/root/usuarios.db}"

  if [[ -f "$db_file" ]]; then
    total_users="$(grep -c . "$db_file" 2>/dev/null || true)"
  fi

  if [[ ! "${total_users:-}" =~ ^[0-9]+$ ]]; then
    total_users=0
  fi

  onlines_count="$(ps -eo args 2>/dev/null | grep "sshd: " | grep -v "grep" | grep -v "priv" | grep -v "root" | wc -l | tr -d ' ' || true)"

  if [[ ! "${onlines_count:-}" =~ ^[0-9]+$ ]]; then
    onlines_count=0
  fi

  local current_ts
  current_ts="$(date +%s 2>/dev/null || echo 0)"

  if [[ -f "$db_file" ]]; then
    expired_count="$(awk -v now="$current_ts" -F: '$3 ~ /^[0-9]+$/ && $3 < now {count++} END {print count+0}' "$db_file" 2>/dev/null || echo 0)"
  fi

  if [[ ! "${expired_count:-}" =~ ^[0-9]+$ ]]; then
    expired_count=0
  fi
}

# Why: ตรวจสอบสถานะ service สำหรับแสดง icon บนเมนู
check_service_status() {
  if [[ -s /etc/issue.net ]] && grep -qE "^[[:space:]]*Banner[[:space:]]+" /etc/ssh/sshd_config 2>/dev/null; then
    stat_banner="$MENU_ON"
  else
    stat_banner="$MENU_OFF"
  fi

  if service_active sshplus-limiter; then stat_limit="$MENU_ON"; else stat_limit="$MENU_OFF"; fi
  if service_active badvpn;          then stat_badvpn="$MENU_ON"; else stat_badvpn="$MENU_OFF"; fi
  if service_active sshplus-bot;     then stat_bot="$MENU_ON"; else stat_bot="$MENU_OFF"; fi
  if service_active sshplus-ws;      then stat_ws="$MENU_ON"; else stat_ws="$MENU_OFF"; fi
  if service_active openvpn;         then stat_ovpn="$MENU_ON"; else stat_ovpn="$MENU_OFF"; fi
  if service_active xray;            then stat_v2ray="$MENU_ON"; else stat_v2ray="$MENU_OFF"; fi

  if grep -q "SSHPlus_AutoMenu_Marker" /root/.bashrc 2>/dev/null; then
    stat_automenu="$MENU_ON"
  else
    stat_automenu="$MENU_OFF"
  fi
}

# Why: พิมพ์เมนู 2 คอลัมน์ให้อ่านง่าย
print_row() {
  echo -e "  ${MENU_RED}[${MENU_CYAN}$1${MENU_RED}] ${MENU_WHITE}• ${MENU_YELLOW}$2 ${MENU_RED}[${MENU_CYAN}$3${MENU_RED}] ${MENU_WHITE}• ${MENU_YELLOW}$4 ${MENU_NC}${5:-}"
}

# Why: แสดงเมนูหลักพร้อมสถานะระบบแบบสคริปต์เดิม
show_menu() {
  get_system_info
  check_service_status

  if declare -F clear_screen >/dev/null 2>&1; then
    clear_screen
  fi

  local LINE="${MENU_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${MENU_NC}"

  echo -e "${LINE}"
  echo -e "                     ${MENU_BG_RED}${MENU_WHITE}  ➱ SSHPLUS MANAGER PRO ➱  ${MENU_NC}"
  echo -e "${LINE}"

  printf "  ${MENU_CYAN}OS  :${MENU_WHITE} %-16s ${MENU_CYAN}TIME :${MENU_WHITE} %s${MENU_NC}\n" "${os_name:0:14}" "$time_now"
  printf "  ${MENU_CYAN}CPU :${MENU_WHITE} %-16s ${MENU_CYAN}RAM  :${MENU_WHITE} %s (%s%%)${MENU_NC}\n" "${cpu_cores} Core (${cpu_use}%)" "$ram_display" "$ram_per"

  echo -e "${LINE}"
  echo -e "  ${MENU_GREEN}● ออนไลน์: ${MENU_WHITE}${onlines_count}${MENU_NC}    ${MENU_RED}● หมดอายุ: ${MENU_WHITE}${expired_count}${MENU_NC}    ${MENU_YELLOW}● ทั้งหมด: ${MENU_WHITE}${total_users}${MENU_NC}"
  echo -e "${LINE}"

  print_row "01" "สร้างผู้ใช้งาน      " "15" "ดูทราฟฟิก (Traffic)" ""
  print_row "02" "สร้างไอดีทดสอบ      " "16" "จัดการ Firewall    " ""
  print_row "03" "ลบผู้ใช้งาน         " "17" "ข้อมูลระบบ (Info)  " ""
  print_row "04" "ต่ออายุผู้ใช้งาน    " "18" "ตั้งค่า Banner     " "$stat_banner"
  print_row "05" "แสดงคนออนไลน์       " "19" "SSH Limiter        " "$stat_limit"
  print_row "06" "แก้วันหมดอายุ       " "20" "BadVPN (Game)      " "$stat_badvpn"
  print_row "07" "แก้ไขลิมิตจอ        " "21" "เมนูอัตโนมัติ      " "$stat_automenu"
  print_row "08" "เปลี่ยนรหัสผ่าน     " "22" "บอท Telegram       " "$stat_bot"
  print_row "09" "ลบคนหมดอายุ         " "23" "เครื่องมือ (Tools) " "${MENU_CYAN}→${MENU_NC}"
  print_row "10" "รายชื่อทั้งหมด      " "24" "WebSocket (Proxy)  " "$stat_ws"
  print_row "11" "สำรองข้อมูล         " "25" "OpenVPN Manager    " "$stat_ovpn"
  print_row "12" "จัดการพอร์ต         " "26" "System Optimizer   " "${MENU_CYAN}→${MENU_NC}"
  print_row "13" "ทดสอบความเร็ว       " "27" "Xray (Reality)     " "$stat_v2ray"
  print_row "14" "เคลียร์แรม/Cache    " "28" "อัปเดต (GitHub)    " ""
  print_row "00" "ออกจากเมนู         " "29" "ถอนการติดตั้ง      " "${RED}⚠️${NC}"

  echo -e "${LINE}"
  printf " %sเลือกเมนู (Select Option): %s" "$MENU_GREEN" "$MENU_NC"
}
