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
  echo -e "${YELLOW}บัญชี Linux users จะไม่ถูกลบอัตโนมัติ${NC}"
  echo "ตรวจรายชื่อ backup ก่อนลบทีละบัญชี:"
  echo "  cut -d: -f1 /root/usuarios.db.bak"
  echo
  echo "อย่าใช้คำสั่ง userdel แบบ loop กับไฟล์ DB โดยไม่ตรวจสอบ UID ก่อน"
  echo
  echo -e "${YELLOW}ขอบคุณที่ใช้งาน SSHPlus Manager! 🙏${NC}"
  echo
  exit 0
}

# Why: อัปเดต SSHPlus Manager จาก GitHub
function_self_update() {
  clear_screen

  echo -e "${BLUE}┌──────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}│${BG_RED}        VERIFIED SELF-UPDATE          ${NC}${BLUE}│${NC}"
  echo -e "${BLUE}└──────────────────────────────────────────┘${NC}"
  echo

  local repo_url="https://github.com/theptk1999/sshplus-manager.git"
  local install_dir="/opt/sshplus-manager"
  local target_bin="/usr/local/sbin/sshplus"
  local origin=""
  local current_commit=""
  local remote_commit=""
  local confirm_commit=""
  local staging=""
  local backup_name=""
  local staged_bin=""
  local branch=""
  local dirty=""

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "Self-update ต้องใช้ root"
    pause
    return
  fi

  if ! command -v git >/dev/null 2>&1; then
    install_pkg "git" || {
      log_error "ติดตั้ง git ไม่สำเร็จ"
      pause
      return
    }
  fi

  if ! command -v tar >/dev/null 2>&1; then
    log_error "ไม่พบ tar"
    pause
    return
  fi

  if [[ ! -d "$install_dir/.git" ]]; then
    log_error "ไม่พบ Git repository ที่ $install_dir"
    log_error "กรุณาติดตั้งด้วย pinned install.sh ก่อน"
    pause
    return
  fi

  origin="$(
    git -C "$install_dir" \
      remote get-url origin 2>/dev/null ||
      true
  )"

  case "$origin" in
    "$repo_url" | \
    "git@github.com:theptk1999/sshplus-manager.git" | \
    "ssh://git@github.com/theptk1999/sshplus-manager.git")
      ;;
    *)
      log_error "Origin ไม่ตรงกับ SSHPlus repository ที่อนุญาต"
      log_error "Origin: ${origin:-N/A}"
      pause
      return
      ;;
  esac

  current_commit="$(
    git -C "$install_dir" \
      rev-parse HEAD 2>/dev/null ||
      true
  )"

  log_info "กำลัง fetch origin/main โดยไม่แก้ working tree..."

  if ! git -C "$install_dir" \
       fetch \
       --prune \
       origin \
       main; then

    log_error "git fetch ไม่สำเร็จ"
    pause
    return
  fi

  remote_commit="$(
    git -C "$install_dir" \
      rev-parse refs/remotes/origin/main 2>/dev/null ||
      true
  )"

  if [[ ! "$remote_commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
    log_error "ไม่สามารถ resolve remote commit ได้"
    pause
    return
  fi

  remote_commit="$(
    printf '%s' "$remote_commit" |
      tr 'A-F' 'a-f'
  )"

  echo
  echo "Current source commit:"
  echo "  ${current_commit:-N/A}"
  echo
  echo "Candidate update commit:"
  echo "  $remote_commit"
  echo

  if [[ "$current_commit" == "$remote_commit" ]]; then
    log_info "Source tree อยู่ที่ commit ล่าสุดแล้ว"
    pause
    return
  fi

  if [[ ! -t 0 ]]; then
    log_error "Self-update ต้องยืนยัน commit ผ่าน interactive terminal"
    return
  fi

  read -r -p \
    "พิมพ์ commit SHA 40 ตัวด้านบนเพื่อยืนยัน: " \
    confirm_commit

  confirm_commit="$(
    printf '%s' "$confirm_commit" |
      tr 'A-F' 'a-f'
  )"

  if [[ "$confirm_commit" != "$remote_commit" ]]; then
    log_warn "Commit ไม่ตรง ยกเลิกการอัปเดต"
    pause
    return
  fi

  staging="$(
    mktemp -d \
      "${TMP_BASE:-/tmp}/sshplus-update.XXXXXX"
  )" || {
    log_error "สร้าง staging directory ไม่สำเร็จ"
    pause
    return
  }

  if ! git -C "$install_dir" \
       archive "$remote_commit" |
       tar -x -C "$staging"; then

    rm -rf -- "$staging"
    log_error "สร้าง source snapshot ไม่สำเร็จ"
    pause
    return
  fi

  log_info "กำลัง build isolated snapshot..."

  if ! (
    cd "$staging" &&
    bash scripts/build.sh &&
    bash -n dist/sshplus.sh
  ); then

    rm -rf -- "$staging"
    log_error "Build/syntax check ไม่สำเร็จ"
    pause
    return
  fi

  if [[ ! -s "$staging/dist/sshplus.sh.sha256" ]]; then
    rm -rf -- "$staging"
    log_error "ไม่พบ build checksum"
    pause
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then

    if ! (
      cd "$staging/dist" &&
      sha256sum -c sshplus.sh.sha256
    ); then

      rm -rf -- "$staging"
      log_error "Build checksum ไม่ผ่าน"
      pause
      return
    fi

  elif command -v shasum >/dev/null 2>&1; then

    local expected_sha=""
    local actual_sha=""

    expected_sha="$(
      awk 'NR==1 {print $1}' \
        "$staging/dist/sshplus.sh.sha256"
    )"

    actual_sha="$(
      shasum -a 256 \
        "$staging/dist/sshplus.sh" |
        awk '{print $1}'
    )"

    if [[ "$actual_sha" != "$expected_sha" ]]; then
      rm -rf -- "$staging"
      log_error "Build checksum ไม่ผ่าน"
      pause
      return
    fi

  else
    rm -rf -- "$staging"
    log_error "ไม่พบ SHA256 verification tool"
    pause
    return
  fi

  if [[ -f "$target_bin" ]]; then
    backup_name="${target_bin}.bak.$(date +%Y%m%d_%H%M%S)"

    if ! cp -p -- "$target_bin" "$backup_name"; then
      rm -rf -- "$staging"
      log_error "Backup binary ปัจจุบันไม่สำเร็จ"
      pause
      return
    fi

    log_info "Backup binary: $backup_name"
  fi

  staged_bin="${target_bin}.new.$$"
  rm -f -- "$staged_bin"

  if ! install \
       -m 755 \
       "$staging/dist/sshplus.sh" \
       "$staged_bin"; then

    rm -f -- "$staged_bin"
    rm -rf -- "$staging"

    log_error "Stage binary ใหม่ไม่สำเร็จ"
    pause
    return
  fi

  if ! mv -f -- "$staged_bin" "$target_bin"; then
    rm -f -- "$staged_bin"

    if [[ -n "$backup_name" &&
          -f "$backup_name" ]]; then
      cp -p -- "$backup_name" "$target_bin" || true
    fi

    rm -rf -- "$staging"

    log_error "ติดตั้ง binary ใหม่ไม่สำเร็จ"
    pause
    return
  fi

  log_info "ติดตั้ง binary จาก commit $remote_commit สำเร็จ"

  dirty="$(
    git -C "$install_dir" \
      status --porcelain 2>/dev/null ||
      true
  )"

  branch="$(
    git -C "$install_dir" \
      branch --show-current 2>/dev/null ||
      true
  )"

  if [[ -z "$dirty" && "$branch" == "main" ]]; then

    if git -C "$install_dir" \
       merge \
       --ff-only \
       "$remote_commit"; then

      log_info "Fast-forward source tree สำเร็จ"
    else
      log_warn "Binary อัปเดตแล้ว แต่ source tree fast-forward ไม่สำเร็จ"
    fi

  else
    log_warn "Binary อัปเดตแล้ว แต่ไม่แตะ source tree"
    log_warn "เหตุผล: branch ไม่ใช่ main หรือมี local changes"
  fi

  rm -rf -- "$staging"

  log_info "อัปเดตสำเร็จ"
  log_info "Commit: $remote_commit"

  sleep 1
  exec "$target_bin"
}
