# ==================================================
# Feature: Network / Ports / Proxy / VPN (REAL)
# ==================================================

require_port_service_ready() {
  local target="${1:-}"

  case "$target" in
    ssh)
      if ! command -v sshd >/dev/null 2>&1 &&
         [[ ! -x /usr/sbin/sshd ]]; then
        log_error "ยังไม่ได้ติดตั้ง OpenSSH Server"
        return 1
      fi

      [[ -f /etc/ssh/sshd_config ]] || {
        log_error "ไม่พบ /etc/ssh/sshd_config"
        return 1
      }

      if ! svc_is_active ssh &&
         ! svc_is_active sshd &&
         ! svc_is_active ssh.socket; then
        log_error "SSH ไม่ได้ทำงานอยู่"
        log_warn "เมนูเปลี่ยนพอร์ตจะไม่ start service อัตโนมัติ"
        return 1
      fi
      ;;

    dropbear)
      command -v dropbear >/dev/null 2>&1 || {
        log_error "ยังไม่ได้ติดตั้ง Dropbear"
        return 1
      }

      if [[ ! -f /etc/default/dropbear &&
            ! -f /etc/sysconfig/dropbear ]]; then
        log_error "ไม่พบ config Dropbear"
        return 1
      fi

      if ! svc_is_active dropbear; then
        log_error "Dropbear ไม่ได้ทำงานอยู่"
        log_warn "เมนูเปลี่ยนพอร์ตจะไม่ start service อัตโนมัติ"
        return 1
      fi
      ;;

    stunnel)
      if ! command -v stunnel >/dev/null 2>&1 &&
         ! command -v stunnel4 >/dev/null 2>&1; then
        log_error "ยังไม่ได้ติดตั้ง Stunnel"
        return 1
      fi

      [[ -f /etc/stunnel/stunnel.conf ]] || {
        log_error \
          "Stunnel ติดตั้งแล้วแต่ยังไม่ได้ตั้งค่า /etc/stunnel/stunnel.conf"
        log_warn \
          "เมนูเปลี่ยนพอร์ตจะไม่สร้าง config หรือ start service อัตโนมัติ"
        return 1
      }

      if ! svc_is_active stunnel4 &&
         ! svc_is_active stunnel; then
        log_error "Stunnel ไม่ได้ทำงานอยู่"
        log_warn "เมนูเปลี่ยนพอร์ตจะไม่ start service อัตโนมัติ"
        return 1
      fi
      ;;

    squid)
      command -v squid >/dev/null 2>&1 || {
        log_error "ยังไม่ได้ติดตั้ง Squid"
        log_warn \
          "เมนูเปลี่ยนพอร์ตจะไม่ติดตั้ง package อัตโนมัติ"
        return 1
      }

      if [[ ! -f /etc/squid/squid.conf &&
            ! -f /etc/squid3/squid.conf ]]; then
        log_error "ไม่พบ config Squid"
        return 1
      fi

      if ! svc_is_active squid &&
         ! svc_is_active squid3; then
        log_error "Squid ไม่ได้ทำงานอยู่"
        log_warn "เมนูเปลี่ยนพอร์ตจะไม่ start service อัตโนมัติ"
        return 1
      fi
      ;;

    *)
      log_error "target '$target' ไม่รองรับ"
      return 1
      ;;
  esac

  return 0
}

current_login_local_port() {
  local conn="${SSH_CONNECTION:-}"
  local remote_addr=""
  local remote_port=""
  local local_addr=""
  local port=""
  local extra=""
  local pid="${BASHPID:-$$}"
  local parent=""
  local depth=0

  #
  # sudo normally removes SSH_CONNECTION from the command's
  # environment, but the invoking sudo/shell ancestors still
  # retain it. Walk a small bounded parent chain to recover it.
  #
  if [[ -z "$conn" ]]; then
    while [[ "$depth" -lt 12 ]]; do
      [[ "$pid" =~ ^[1-9][0-9]*$ ]] ||
        break

      if [[ -r "/proc/${pid}/environ" ]]; then
        conn="$(
          tr '\0' '\n' \
            < "/proc/${pid}/environ" \
            2>/dev/null |
          awk '
            /^SSH_CONNECTION=/ {
              sub(/^SSH_CONNECTION=/, "")
              print
              exit
            }
          '
        )"

        [[ -n "$conn" ]] &&
          break
      fi

      parent="$(
        awk '
          /^PPid:/ {
            print $2
            exit
          }
        ' "/proc/${pid}/status" 2>/dev/null ||
        true
      )"

      [[ "$parent" =~ ^[1-9][0-9]*$ ]] ||
        break

      [[ "$parent" != "$pid" ]] ||
        break

      pid="$parent"
      depth=$((depth + 1))
    done
  fi

  [[ -n "$conn" ]] ||
    return 1

  read -r \
    remote_addr \
    remote_port \
    local_addr \
    port \
    extra <<< "$conn"

  [[ -n "$remote_addr" ]] ||
    return 1

  [[ -n "$local_addr" ]] ||
    return 1

  [[ -z "$extra" ]] ||
    return 1

  is_port "$remote_port" ||
    return 1

  is_port "$port" ||
    return 1

  printf '%s\n' "$port"
}

ssh_socket_activation_active() {
  command -v systemctl >/dev/null 2>&1 ||
    return 1

  if systemctl is-active \
       --quiet ssh.socket 2>/dev/null; then
    return 0
  fi

  if systemctl is-enabled \
       --quiet ssh.socket 2>/dev/null; then
    return 0
  fi

  return 1
}

rollback_port_config() {
  local backup="${1:-}"
  local target="${2:-}"

  [[ -n "$backup" ]] || return 1
  [[ -n "$target" ]] || return 1
  [[ -e "$backup" || -L "$backup" ]] ||
    return 1

  cp -a -- "$backup" "$target"
}

function_mode_connection() {
  while true; do
    clear_screen

    echo -e "${BLUE}┌──────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${BG_RED}        จัดการพอร์ต (PORTS)             ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}├──────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${WHITE} 1) เปลี่ยน Port SSH                      ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 2) เปลี่ยน Port Dropbear                 ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 3) เปลี่ยน Port Stunnel (SSL)            ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 4) เปลี่ยน Port Squid Proxy              ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 5) ดู Port ที่เปิดอยู่                   ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 0) ย้อนกลับ                              ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}└──────────────────────────────────────────┘${NC}"

    read -r -p "เลือก: " p_opt

    case "$p_opt" in
      1)
        require_port_service_ready ssh || {
          pause
          continue
        }

        local ssh_cfg="/etc/ssh/sshd_config"
        local curr_ssh=""
        local new_ssh=""
        local login_port=""
        local ssh_backup=""
        local sshd_bin=""

        curr_ssh="$(get_ssh_port)"

        echo -e \
          "Port ปัจจุบัน: ${GREEN}$curr_ssh${NC}"

        read -r -p "Port ใหม่: " new_ssh

        is_port "$new_ssh" || {
          log_error "Port ไม่ถูกต้อง"
          pause
          continue
        }

        if [[ "$new_ssh" == "$curr_ssh" ]]; then
          log_info "Port SSH เป็น $new_ssh อยู่แล้ว"
          pause
          continue
        fi

        if is_port_in_use "$new_ssh"; then
          log_error "Port $new_ssh ถูกใช้งานอยู่แล้ว"
          pause
          continue
        fi

        login_port="$(
          current_login_local_port 2>/dev/null ||
            true
        )"

        if [[ -n "$login_port" &&
              "$login_port" == "$curr_ssh" ]]; then
          log_error \
            "ปฏิเสธการเปลี่ยน SSH Port: session ปัจจุบันกำลังใช้ Port $curr_ssh"
          log_warn \
            "เชื่อมต่อผ่าน Dropbear/console ก่อน แล้วจึงเปลี่ยน SSH Port"
          pause
          continue
        fi

        if ssh_socket_activation_active; then
          log_error \
            "ตรวจพบ systemd ssh.socket active/enabled และอาจควบคุม SSH Port"
          log_warn \
            "เมนูนี้จะไม่แก้ ssh.socket อัตโนมัติเพื่อป้องกัน VPS หลุด"
          log_warn \
            "ต้องใช้ Safe SSH Socket Migration แยกต่างหาก"
          pause
          continue
        fi

        if svc_is_active sshplus-ws; then
          log_error \
            "WebSocket กำลังใช้งานและผูก backend กับ SSH Port ปัจจุบัน"
          log_warn \
            "หยุด/ย้าย WebSocket backend ก่อนเปลี่ยน SSH Port"
          pause
          continue
        fi

        ssh_backup="$(
          backup_file "$ssh_cfg"
        )" || {
          log_error "Backup sshd_config ไม่สำเร็จ"
          pause
          continue
        }

        if grep -qE \
             "^#?[[:space:]]*Port" \
             "$ssh_cfg"; then

          sed -i -E \
            "s/^#?[[:space:]]*Port.*/Port ${new_ssh}/g" \
            "$ssh_cfg"
        else
          printf 'Port %s\n' \
            "$new_ssh" >> "$ssh_cfg"
        fi

        sshd_bin="$(
          command -v sshd 2>/dev/null ||
            printf '/usr/sbin/sshd'
        )"

        if [[ ! -x "$sshd_bin" ]] ||
           ! "$sshd_bin" -t >/dev/null 2>&1; then

          rollback_port_config \
            "$ssh_backup" \
            "$ssh_cfg" || true

          log_error \
            "sshd config ไม่ผ่าน validation - rollback แล้ว"
          pause
          continue
        fi

        if ! restart_ssh_service; then
          rollback_port_config \
            "$ssh_backup" \
            "$ssh_cfg" || true

          restart_ssh_service >/dev/null 2>&1 ||
            true

          log_error \
            "Restart SSH ไม่สำเร็จ - rollback แล้ว"
          pause
          continue
        fi

        sleep 1

        if ! is_tcp_port_listening "$new_ssh"; then
          rollback_port_config \
            "$ssh_backup" \
            "$ssh_cfg" || true

          restart_ssh_service >/dev/null 2>&1 ||
            true

          log_error \
            "ไม่พบ SSH listener ที่ Port $new_ssh - rollback แล้ว"
          pause
          continue
        fi

        log_info \
          "เปลี่ยน SSH Port เป็น $new_ssh สำเร็จและตรวจ listener แล้ว"
        pause
        ;;

      2)
        require_port_service_ready dropbear || {
          pause
          continue
        }

        local cfg_drop=""
        local curr_drop=""
        local new_drop=""
        local login_port=""
        local drop_backup=""

        [[ -f /etc/default/dropbear ]] &&
          cfg_drop="/etc/default/dropbear"

        [[ -f /etc/sysconfig/dropbear ]] &&
          cfg_drop="/etc/sysconfig/dropbear"

        [[ -n "$cfg_drop" ]] || {
          log_error "ไม่พบ config Dropbear"
          pause
          continue
        }

        curr_drop="$(
          grep '^DROPBEAR_PORT=' "$cfg_drop" |
          tail -n1 |
          cut -d= -f2 ||
          true
        )"

        [[ -n "$curr_drop" ]] ||
          curr_drop="222"

        echo -e \
          "Port ปัจจุบัน: ${GREEN}$curr_drop${NC}"

        read -r -p "Port ใหม่: " new_drop

        is_port "$new_drop" || {
          log_error "Port ไม่ถูกต้อง"
          pause
          continue
        }

        if [[ "$new_drop" == "$curr_drop" ]]; then
          log_info "Dropbear ใช้ Port $new_drop อยู่แล้ว"
          pause
          continue
        fi

        if is_port_in_use "$new_drop"; then
          log_error "Port $new_drop ถูกใช้งานอยู่แล้ว"
          pause
          continue
        fi

        login_port="$(
          current_login_local_port 2>/dev/null ||
            true
        )"

        if [[ -n "$login_port" &&
              "$login_port" == "$curr_drop" ]]; then
          log_error \
            "ปฏิเสธการเปลี่ยน Dropbear Port: session ปัจจุบันกำลังใช้ Port $curr_drop"
          pause
          continue
        fi

        drop_backup="$(
          backup_file "$cfg_drop"
        )" || {
          log_error "Backup Dropbear config ไม่สำเร็จ"
          pause
          continue
        }

        if grep -q '^DROPBEAR_PORT=' "$cfg_drop"; then
          sed -i \
            "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=${new_drop}/g" \
            "$cfg_drop"
        else
          printf 'DROPBEAR_PORT=%s\n' \
            "$new_drop" >> "$cfg_drop"
        fi

        if ! svc_restart dropbear; then
          rollback_port_config \
            "$drop_backup" \
            "$cfg_drop" || true

          svc_restart dropbear >/dev/null 2>&1 ||
            true

          log_error \
            "Restart Dropbear ไม่สำเร็จ - rollback แล้ว"
          pause
          continue
        fi

        sleep 1

        if ! is_tcp_port_listening "$new_drop"; then
          rollback_port_config \
            "$drop_backup" \
            "$cfg_drop" || true

          svc_restart dropbear >/dev/null 2>&1 ||
            true

          log_error \
            "ไม่พบ Dropbear listener ที่ Port $new_drop - rollback แล้ว"
          pause
          continue
        fi

        log_info \
          "เปลี่ยน Dropbear Port เป็น $new_drop สำเร็จและตรวจ listener แล้ว"
        pause
        ;;

      3)
        require_port_service_ready stunnel || {
          pause
          continue
        }

        local cfg_st="/etc/stunnel/stunnel.conf"
        local curr_st=""
        local new_st=""
        local st_backup=""

        [[ -f "$cfg_st" ]] || {
          log_error "ไม่พบ config Stunnel"
          pause
          continue
        }

        curr_st="$(
          awk '
            /^accept[[:space:]]*=/ {
              print $3
              exit
            }
          ' "$cfg_st"
        )"

        [[ -n "$curr_st" ]] ||
          curr_st="443"

        echo -e \
          "Port ปัจจุบัน: ${GREEN}$curr_st${NC}"

        read -r -p "Port ใหม่: " new_st

        is_port "$new_st" || {
          log_error "Port ไม่ถูกต้อง"
          pause
          continue
        }

        if [[ "$new_st" == "$curr_st" ]]; then
          log_info "Stunnel ใช้ Port $new_st อยู่แล้ว"
          pause
          continue
        fi

        if is_port_in_use "$new_st"; then
          log_error "Port $new_st ถูกใช้งานอยู่แล้ว"
          pause
          continue
        fi

        st_backup="$(
          backup_file "$cfg_st"
        )" || {
          log_error "Backup Stunnel config ไม่สำเร็จ"
          pause
          continue
        }

        if grep -q '^accept' "$cfg_st"; then
          sed -i \
            "s/^accept.*/accept = ${new_st}/g" \
            "$cfg_st"
        else
          printf \
            '[ssh]\nclient = no\naccept = %s\nconnect = 127.0.0.1:%s\n' \
            "$new_st" \
            "$(get_ssh_port)" >> "$cfg_st"
        fi

        if ! svc_restart stunnel4 &&
           ! svc_restart stunnel; then

          rollback_port_config \
            "$st_backup" \
            "$cfg_st" || true

          svc_restart stunnel4 >/dev/null 2>&1 ||
            svc_restart stunnel >/dev/null 2>&1 ||
            true

          log_error \
            "Restart Stunnel ไม่สำเร็จ - rollback แล้ว"
          pause
          continue
        fi

        sleep 1

        if ! is_tcp_port_listening "$new_st"; then
          rollback_port_config \
            "$st_backup" \
            "$cfg_st" || true

          svc_restart stunnel4 >/dev/null 2>&1 ||
            svc_restart stunnel >/dev/null 2>&1 ||
            true

          log_error \
            "ไม่พบ Stunnel listener ที่ Port $new_st - rollback แล้ว"
          pause
          continue
        fi

        log_info \
          "เปลี่ยน Stunnel Port เป็น $new_st สำเร็จและตรวจ listener แล้ว"
        pause
        ;;

      4)
        require_port_service_ready squid || {
          pause
          continue
        }

        local cfg_sq=""
        local curr_sq=""
        local new_sq=""
        local sq_backup=""

        [[ -f /etc/squid/squid.conf ]] &&
          cfg_sq="/etc/squid/squid.conf"

        [[ -f /etc/squid3/squid.conf ]] &&
          cfg_sq="/etc/squid3/squid.conf"

        [[ -n "$cfg_sq" ]] || {
          log_error "ไม่พบ config Squid"
          pause
          continue
        }

        curr_sq="$(
          awk '
            /^http_port[[:space:]]+/ {
              print $2
              exit
            }
          ' "$cfg_sq"
        )"

        [[ -n "$curr_sq" ]] ||
          curr_sq="3128"

        echo -e \
          "Port ปัจจุบัน: ${GREEN}$curr_sq${NC}"

        read -r -p "Port ใหม่: " new_sq

        is_port "$new_sq" || {
          log_error "Port ไม่ถูกต้อง"
          pause
          continue
        }

        if [[ "$new_sq" == "$curr_sq" ]]; then
          log_info "Squid ใช้ Port $new_sq อยู่แล้ว"
          pause
          continue
        fi

        if is_port_in_use "$new_sq"; then
          log_error "Port $new_sq ถูกใช้งานอยู่แล้ว"
          pause
          continue
        fi

        sq_backup="$(
          backup_file "$cfg_sq"
        )" || {
          log_error "Backup Squid config ไม่สำเร็จ"
          pause
          continue
        }

        if grep -q '^http_port' "$cfg_sq"; then
          sed -i \
            "s/^http_port.*/http_port ${new_sq}/g" \
            "$cfg_sq"
        else
          printf 'http_port %s\n' \
            "$new_sq" >> "$cfg_sq"
        fi

        if command -v squid >/dev/null 2>&1; then
          if ! squid \
               -k parse \
               -f "$cfg_sq" \
               >/dev/null 2>&1; then

            rollback_port_config \
              "$sq_backup" \
              "$cfg_sq" || true

            log_error \
              "Squid config ไม่ผ่าน validation - rollback แล้ว"
            pause
            continue
          fi
        fi

        if ! svc_restart squid &&
           ! svc_restart squid3; then

          rollback_port_config \
            "$sq_backup" \
            "$cfg_sq" || true

          svc_restart squid >/dev/null 2>&1 ||
            svc_restart squid3 >/dev/null 2>&1 ||
            true

          log_error \
            "Restart Squid ไม่สำเร็จ - rollback แล้ว"
          pause
          continue
        fi

        sleep 1

        if ! is_tcp_port_listening "$new_sq"; then
          rollback_port_config \
            "$sq_backup" \
            "$cfg_sq" || true

          svc_restart squid >/dev/null 2>&1 ||
            svc_restart squid3 >/dev/null 2>&1 ||
            true

          log_error \
            "ไม่พบ Squid listener ที่ Port $new_sq - rollback แล้ว"
          pause
          continue
        fi

        log_info \
          "เปลี่ยน Squid Port เป็น $new_sq สำเร็จและตรวจ listener แล้ว"
        pause
        ;;

      5)
        clear_screen
        echo -e \
          "${WHITE}Protocol  Local Address         Program${NC}"
        echo -e \
          "${YELLOW}------------------------------------------${NC}"

        if command -v ss >/dev/null 2>&1; then
          ss -tulnp |
            grep LISTEN |
            awk '{print $1, $5, $7}' |
            column -t
        elif command -v netstat >/dev/null 2>&1; then
          netstat -tulnp |
            grep LISTEN |
            awk '{print $1, $4, $7}' |
            column -t
        fi

        pause
        ;;

      0)
        return
        ;;

      *)
        log_error "เลือกไม่ถูกต้อง"
        sleep 1
        ;;
    esac
  done
}

function_trafego() {
  clear_screen
  echo -e "${BLUE}┌──────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}│${BG_RED}           TRAFEGO DE REDE           ${NC}${BLUE}│${NC}"
  echo -e "${BLUE}├──────────────────────────────────────────┤${NC}"
  if command -v ss >/dev/null 2>&1; then
    ss -tuln | grep -E 'ESTABLISHED|LISTEN' || true
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tuln | grep -E 'ESTABLISHED|LISTEN' || true
  fi
  echo -e "${BLUE}└──────────────────────────────────────────┘${NC}"
  pause
}

function_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y ufw >/dev/null 2>&1 || true
  fi
  if ! command -v ufw >/dev/null 2>&1; then
    log_error "ติดตั้ง ufw ไม่สำเร็จ กรุณาติดตั้งเอง: apt install ufw"
    pause
    return
  fi
  while true; do
    clear_screen
    echo -e "${BLUE}│${WHITE} 1) เปิด Firewall (Safe Enable)  ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 2) ปิด Firewall                 ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 3) ดูสถานะ                      ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 4) อนุญาต Port                  ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 5) บล็อก Port                   ${NC}${BLUE}│${NC}"
    echo -e "${BLUE}│${WHITE} 0) ย้อนกลับ                     ${NC}${BLUE}│${NC}"
    read -r -p "เลือก: " opt
    case "$opt" in
      1) local sp; sp="$(get_ssh_port)"
         ufw allow "${sp}/tcp" >/dev/null 2>&1 || true
         ufw --force enable; log_info "Firewall เปิดแล้ว (SSH:$sp)"; pause ;;
      2) ufw disable; log_warn "Firewall ปิดแล้ว"; pause ;;
      3) ufw status verbose; pause ;;
      4) read -r -p "Port: " pa; is_port "$pa" && ufw allow "$pa" && log_info "อนุญาต $pa" || log_error "Port ผิด"; pause ;;
      5) read -r -p "Port: " pd; is_port "$pd" && ufw deny "$pd" && log_info "บล็อก $pd" || log_error "Port ผิด"; pause ;;
      0) return ;; *) sleep 1 ;;
    esac
  done
}

function_openvpn() {
  clear_screen
  echo -e "${BLUE}│${BG_RED}      OPENVPN MANAGER (AUTO)      ${NC}${BLUE}│${NC}"
  if [[ ! -s "$OPENVPN_SCRIPT" ]]; then
    log_warn "กำลังดาวน์โหลด OpenVPN installer..."
    download_verified_file "OpenVPN Installer" "$URL_OPENVPN" "$OPENVPN_SHA256" "$OPENVPN_SCRIPT" "700" || { log_error "Download ไม่สำเร็จ"; pause; return; }
  fi
  if [[ -e /etc/openvpn/server/server.conf || -e /etc/openvpn/server.conf ]]; then
    log_info "ตรวจพบ OpenVPN แล้ว!"
  else
    log_warn "กำลังติดตั้ง OpenVPN ใหม่..."
  fi
  sleep 2; bash "$OPENVPN_SCRIPT"; pause
}

function_v2ray_manager() {
  local XRAY_CONFIG="/usr/local/etc/xray/config.json"
  local XRAY_LINK="/usr/local/etc/xray/client_link.txt"
  while true; do
    clear_screen
    local sx; svc_is_active xray && sx="${GREEN}ONLINE${NC}" || { [[ -f /usr/local/bin/xray ]] && sx="${YELLOW}INSTALLED${NC}" || sx="${RED}NOT INSTALLED${NC}"; }
    echo -e "${BLUE}│${BG_RED}     XRAY MANAGER (VLESS+REALITY)  ${NC}${BLUE}│${NC}"
    echo -e "สถานะ: $sx"
    echo "1) ติดตั้ง  2) ดูลิงก์  3) ลบ  0) กลับ"
    read -r -p "เลือก: " x_opt
    case "$x_opt" in
      1)
        if [[ ! -f /usr/local/bin/xray ]]; then
          local xi; xi="$(mktemp "${TMP_BASE:-/tmp}/xray-inst.XXXXXX.sh")"
          download_verified_file "Xray Installer" "$URL_XRAY_INSTALL" "$XRAY_INSTALL_SHA256" "$xi" "700" || { rm -f "$xi"; pause; continue; }
          bash "$xi" install; rm -f "$xi"
        fi
        [[ -f /usr/local/bin/xray ]] || { log_error "ติดตั้ง Xray ไม่สำเร็จ"; pause; continue; }
        read -r -p "Port (443/8443): " xp; is_port "$xp" || xp=8443
        is_port_in_use "$xp" && { log_error "Port ถูกใช้แล้ว"; pause; continue; }
        command -v openssl >/dev/null 2>&1 || install_pkg "openssl" || true
        local xu xk xpr xpu xs
        xu="$(/usr/local/bin/xray uuid 2>/dev/null || uuidgen 2>/dev/null || true)"
        xk="$(/usr/local/bin/xray x25519 2>/dev/null || true)"
        xpr="$(awk -F': ' '/Private key:/{print $2}' <<< "$xk")"
        xpu="$(awk -F': ' '/Public key:/{print $2}' <<< "$xk")"
        xs="$(openssl rand -hex 8 2>/dev/null || true)"
        [[ -z "$xu" || -z "$xpr" || -z "$xpu" || -z "$xs" ]] && { log_error "สร้าง keys ไม่สำเร็จ"; pause; continue; }
        local sni="www.apple.com"
        mkdir -p "$(dirname "$XRAY_CONFIG")"
        cat <<XREOF > "$XRAY_CONFIG"
{"log":{"loglevel":"warning"},"inbounds":[{"listen":"0.0.0.0","port":${xp},"protocol":"vless","settings":{"clients":[{"id":"${xu}","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"${sni}:443","xver":0,"serverNames":["${sni}"],"privateKey":"${xpr}","shortIds":["${xs}"]}}}],"outbounds":[{"protocol":"freedom","tag":"direct"}]}
XREOF
        /usr/local/bin/xray -test -config "$XRAY_CONFIG" >/dev/null 2>&1 || { log_error "Config ไม่ผ่าน"; pause; continue; }
        svc_daemon_reload; svc_enable xray || true; svc_restart xray || true
        command -v ufw >/dev/null 2>&1 && ufw allow "$xp" >/dev/null 2>&1 || true
        local mip; mip="$(curl -s --max-time 5 ifconfig.me || echo '127.0.0.1')"
        echo "vless://${xu}@${mip}:${xp}?security=reality&encryption=none&pbk=${xpu}&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=${sni}&sid=${xs}#SSHPlus_Xray" > "$XRAY_LINK"
        chmod 600 "$XRAY_LINK"
        log_info "ติดตั้ง Xray สำเร็จ! Port:$xp SNI:$sni"; pause ;;
      2) [[ -f "$XRAY_LINK" ]] && { clear_screen; cat "$XRAY_LINK"; echo; } || log_error "ยังไม่ติดตั้ง Xray"; pause ;;
      3) svc_stop xray || true; svc_disable xray || true; svc_remove xray || true
         rm -rf /usr/local/etc/xray /usr/local/bin/xray; svc_daemon_reload
         log_info "ลบ Xray แล้ว"; pause ;;
      0) return ;; *) sleep 1 ;;
    esac
  done
}
