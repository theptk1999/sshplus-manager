# ==================================================
# Feature: Tools / System Info (REAL)
# ==================================================

function_speedtest() {
  command -v speedtest-cli >/dev/null 2>&1 || install_pkg "speedtest-cli"
  log_info "Running speedtest..."
  command -v speedtest-cli >/dev/null 2>&1 && speedtest-cli || log_error "ติดตั้งไม่สำเร็จ"
  pause
}

function_otimizar() {
  log_info "กำลังล้าง Cache..."
  sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  log_info "ล้าง RAM เรียบร้อย!"; sleep 1
}

function_info_sistema() {
  clear_screen
  local sys_os kernel up_time cpu_info cores ram_total ram_used disk_total disk_used disk_p pub_ip
  sys_os="$(grep -w PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -s)"
  kernel="$(uname -r 2>/dev/null || echo N/A)"
  up_time="$(uptime -p 2>/dev/null | sed 's/up //' || echo N/A)"
  cpu_info="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//' || echo 'Unknown')"
  cores="$(nproc 2>/dev/null || echo 1)"
  ram_total="$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo N/A)"
  ram_used="$(free -h 2>/dev/null | awk '/^Mem:/{print $3}' || echo N/A)"
  disk_total="$(df -h / 2>/dev/null | awk 'NR==2{print $2}' || echo N/A)"
  disk_used="$(df -h / 2>/dev/null | awk 'NR==2{print $3}' || echo N/A)"
  disk_p="$(df -h / 2>/dev/null | awk 'NR==2{print $5}' || echo N/A)"
  pub_ip="$(curl -s --max-time 3 ifconfig.me 2>/dev/null || echo N/A)"
  echo -e "${BLUE}┌────────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}│${BG_RED}                 ข้อมูลระบบ (SYSTEM INFO)                   ${NC}${BLUE}│${NC}"
  echo -e "${BLUE}├────────────────────────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}• ${WHITE}OS     : ${GREEN}${sys_os}${NC}"
  echo -e "  ${CYAN}• ${WHITE}Kernel : ${GREEN}${kernel}${NC}"
  echo -e "  ${CYAN}• ${WHITE}CPU    : ${YELLOW}${cpu_info} (${cores} Cores)${NC}"
  echo -e "  ${CYAN}• ${WHITE}RAM    : ${YELLOW}${ram_used} / ${ram_total}${NC}"
  echo -e "  ${CYAN}• ${WHITE}Disk   : ${YELLOW}${disk_used} / ${disk_total} (${disk_p})${NC}"
  echo -e "  ${CYAN}• ${WHITE}IP     : ${CYAN}${pub_ip}${NC}"
  echo -e "  ${CYAN}• ${WHITE}Uptime : ${GREEN}${up_time}${NC}"
  echo -e "${BLUE}└────────────────────────────────────────────────────────────┘${NC}"
  pause
}

function_banner() {
  while true; do
    clear_screen
    echo "1) แก้ไข Banner (Nano)  2) Template  3) ปิด  0) กลับ"
    read -r -p "เลือก: " opt
    case "$opt" in
      1) command -v nano >/dev/null 2>&1 || install_pkg "nano"
         nano /etc/issue.net
         if grep -qE "^#?[[:space:]]*Banner" /etc/ssh/sshd_config 2>/dev/null; then
           sed -i -E 's|^#?[[:space:]]*Banner.*|Banner /etc/issue.net|g' /etc/ssh/sshd_config
         else echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config; fi
         restart_ssh_service; log_info "อัปเดต Banner แล้ว!"; pause ;;
      2) cat <<'BNEOF' > /etc/issue.net
======================================
        WELCOME TO PREMIUM VPN
======================================
RULES:
- ห้ามใช้โหลด BitTorrent เด็ดขาด
- ห้ามใช้ทำสิ่งผิดกฎหมายทุกชนิด
- ห้ามแชร์บัญชีเกินลิมิตที่กำหนด
======================================
BNEOF
         if grep -qE "^#?[[:space:]]*Banner" /etc/ssh/sshd_config 2>/dev/null; then
           sed -i -E 's|^#?[[:space:]]*Banner.*|Banner /etc/issue.net|g' /etc/ssh/sshd_config
         else echo "Banner /etc/issue.net" >> /etc/ssh/sshd_config; fi
         restart_ssh_service; log_info "สร้าง Banner Template แล้ว!"; pause ;;
      3) : > /etc/issue.net
         sed -i -E 's|^Banner.*|#Banner none|g' /etc/ssh/sshd_config 2>/dev/null || true
         restart_ssh_service; log_info "ปิด Banner แล้ว!"; pause ;;
      0) return ;; *) sleep 1 ;;
    esac
  done
}

function_optimize_system() {
  clear_screen
  echo "1) TCP BBR  2) Swap 1GB  3) Certbot SSL  0) กลับ"
  read -r -p "เลือก: " os_opt
  case "$os_opt" in
    1)
      local bc="/etc/sysctl.d/99-sshplus-bbr.conf" bs=false
      grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null && bs=true
      modprobe tcp_bbr 2>/dev/null && bs=true
      [[ "$bs" == false ]] && { log_error "Kernel ไม่รองรับ BBR"; pause; return; }
      cat <<BBREOF > "$bc"
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_fastopen = 3
BBREOF
      sysctl -p "$bc" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
      local cc; cc="$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')"
      [[ "$cc" == "bbr" ]] && log_info "เปิด BBR สำเร็จ!" || log_warn "เขียน Config แล้ว อาจต้อง Reboot"; pause ;;
    2)
      if grep -qi "/swapfile" /proc/swaps 2>/dev/null; then log_warn "มี Swap แล้ว"
      else
        fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile
        grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log_info "เพิ่ม Swap 1GB แล้ว!"; free -h | grep -i swap || true
      fi; pause ;;
    3)
      install_pkg "certbot"
      read -r -p "โดเมน: " md; [[ -z "$md" ]] && return
      svc_is_active nginx && svc_stop nginx || true
      svc_is_active sshplus-ws && svc_stop sshplus-ws || true
      certbot certonly --standalone -d "$md" --non-interactive --agree-tos -m "admin@${md}"
      [[ -d "/etc/letsencrypt/live/$md" ]] && log_info "SSL สำเร็จ!" || log_error "SSL ไม่สำเร็จ"; pause ;;
    0) return ;; *) sleep 1 ;;
  esac
}
