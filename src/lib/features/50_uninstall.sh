# ==================================================
# Feature: Uninstall & Self-Update
# Why: ถอนการติดตั้งทั้งหมดอย่างสะอาด และอัปเดตจาก GitHub
# ==================================================

# Why: ถอนการติดตั้ง SSHPlus Manager ทั้งหมด
function_uninstall() {
  clear_screen
  echo -e "${RED}==================================================${NC}"
  echo -e "${RED}  ⚠️  SSHPlus Manager - UNINSTALL${NC}"
  echo -e "${RED}==================================================${NC}"
  echo
  echo -e "${YELLOW}จะลบสิ่งต่อไปนี้:${NC}"
  echo "  • SSHPlus binary (/usr/local/sbin/sshplus)"
  echo "  • Source code (/opt/sshplus-manager)"
  echo "  • Services (limiter, badvpn, bot, ws)"
  echo "  • Config files (/etc/sshplus)"
  echo "  • DB file (/root/usuarios.db)"
  echo "  • Scripts (/root/limit_auto.sh, bot_auto.py, proxy_ws.py)"
  echo "  • Auto menu ใน .bashrc"
  echo
  echo -e "${GREEN}สิ่งที่ไม่ลบ:${NC}"
  echo "  • SSH users (ต้องลบเอง)"
  echo "  • OpenVPN / Xray config"
  echo "  • SSH config / Firewall rules"
  echo
  echo -e "${RED}⚠️  การกระทำนี้ไม่สามารถย้อนกลับได้!${NC}"
  echo

  read -r -p "พิมพ์ UNINSTALL เพื่อยืนยัน: " confirm_uninstall
  if [[ "$confirm_uninstall" != "UNINSTALL" ]]; then
    log_warn "ยกเลิกการถอนการติดตั้ง"
    pause
    return
  fi

  echo
  log_info "[1/7] หยุด services..."
  local svc_name
  for svc_name in sshplus-limiter badvpn sshplus-bot sshplus-ws; do
    if svc_is_active "$svc_name" 2>/dev/null; then
      svc_stop "$svc_name" || true
      svc_disable "$svc_name" || true
      log_info "  หยุด $svc_name แล้ว"
    fi
    svc_remove "$svc_name" 2>/dev/null || true
  done
  svc_daemon_reload

  log_info "[2/7] ลบ binary..."
  rm -f /usr/local/sbin/sshplus

  log_info "[3/7] ลบ source code..."
  rm -rf /opt/sshplus-manager

  log_info "[4/7] ลบ config..."
  rm -rf /etc/sshplus

  log_info "[5/7] ลบ scripts..."
  rm -f /root/limit_auto.sh
  rm -f /root/bot_auto.py
  rm -f /root/proxy_ws.py
  rm -f /root/openvpn-install.sh

  log_info "[6/7] ลบ DB..."
  rm -f /root/usuarios.db
  rm -f /root/usuarios.db.lock
  rm -f /root/backup_users_*.db

  log_info "[7/7] ลบ auto menu..."
  sed -i '/SSHPlus_AutoMenu_Marker/d' /root/.bashrc 2>/dev/null || true

  echo
  echo -e "${GREEN}==================================================${NC}"
  echo -e "${GREEN}  ✅ ถอนการติดตั้ง SSHPlus Manager สำเร็จ!${NC}"
  echo -e "${GREEN}==================================================${NC}"
  echo
  echo -e "${YELLOW}ถ้าต้องการลบ SSH users ทั้งหมดด้วย:${NC}"
  echo "  awk -F: '{print \$1}' /root/usuarios.db.bak | while read u; do userdel --force \"\$u\"; done"
  echo
  echo -e "${YELLOW}ขอบคุณที่ใช้งาน SSHPlus Manager! 🙏${NC}"
  echo
  exit 0
}

# Why: อัปเดต SSHPlus Manager จาก GitHub
function_self_update() {
  clear_screen
  echo -e "${BLUE}┌──────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}│${BG_RED}        SELF-UPDATE FROM GITHUB        ${NC}${BLUE}│${NC}"
  echo -e "${BLUE}└──────────────────────────────────────────┘${NC}"
  echo

  local repo_url="https://github.com/theptk1999/sshplus-manager.git"
  local install_dir="/opt/sshplus-manager"
  local target_bin="/usr/local/sbin/sshplus"

  # Why: backup เวอร์ชันปัจจุบันก่อนอัปเดต
  if [[ -f "$target_bin" ]]; then
    local backup_name="${target_bin}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$target_bin" "$backup_name"
    log_info "Backup: $backup_name"
  fi

  # Why: ดึงโค้ดล่าสุดจาก GitHub
  if [[ -d "${install_dir}/.git" ]]; then
    log_info "กำลัง pull โค้ดล่าสุด..."
    cd "$install_dir"
    if ! git pull --ff-only origin main 2>/dev/null; then
      log_warn "Fast-forward ไม่ได้ กำลัง reset..."
      git fetch origin main
      git reset --hard origin/main
    fi
  else
    log_info "กำลัง clone จาก GitHub..."
    command -v git >/dev/null 2>&1 || install_pkg "git"
    rm -rf "$install_dir"
    git clone --depth 1 "$repo_url" "$install_dir"
    cd "$install_dir"
  fi

  # Why: build ไฟล์ใหม่
  log_info "กำลัง build..."
  if ! bash scripts/build.sh; then
    log_error "Build ไม่สำเร็จ!"
    pause
    return
  fi

  # Why: ติดตั้งไฟล์ใหม่ทับที่เดิม
  if [[ -f dist/sshplus.sh ]]; then
    install -m 755 dist/sshplus.sh "$target_bin"
        log_info "อัปเดตสำเร็จ! กำลังรีสตาร์ทเพื่อใช้เวอร์ชันใหม่..."
    sleep 2
    exec /usr/local/sbin/sshplus
  else
    log_error "ไม่พบ dist/sshplus.sh หลัง build"
  fi

  pause
}
