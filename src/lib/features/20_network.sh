# ==================================================
# Feature: Network / Ports / Proxy / VPN (REAL)
# ==================================================

ensure_port_service_installed() {
  local target="${1:-}"
  case "$target" in
    ssh)
      command -v sshd >/dev/null 2>&1 || [[ -f /etc/ssh/sshd_config ]] && return 0
      log_warn "กำลังติดตั้ง OpenSSH Server..."
      install_pkg "openssh-server" || return 1
      svc_enable ssh || svc_enable sshd || true
      svc_start ssh || svc_start sshd || true
      ;;
    dropbear)
      command -v dropbear >/dev/null 2>&1 && return 0
      [[ -f /etc/default/dropbear || -f /etc/sysconfig/dropbear ]] && return 0
      install_pkg "dropbear" || return 1
      local cfg=""
      if [[ -f /etc/default/dropbear ]]; then cfg="/etc/default/dropbear"
      elif [[ -f /etc/sysconfig/dropbear ]]; then cfg="/etc/sysconfig/dropbear"
      else
        cfg="/etc/default/dropbear"
        mkdir -p /etc/default
        printf 'DROPBEAR_PORT=222\nDROPBEAR_EXTRA_ARGS=\n' > "$cfg"
      fi
      svc_enable dropbear || true; svc_start dropbear || true
      ;;
    stunnel)
      command -v stunnel >/dev/null 2>&1 || command -v stunnel4 >/dev/null 2>&1 && return 0
      [[ -f /etc/stunnel/stunnel.conf ]] && return 0
      local pkg="stunnel"
      [[ "${OS:-}" == "ubuntu" || "${OS:-}" == "debian" ]] && pkg="stunnel4"
      install_pkg "$pkg" || return 1
      mkdir -p /etc/stunnel
      [[ -f /etc/stunnel/stunnel.conf ]] || cat <<STUNEOF > /etc/stunnel/stunnel.conf
foreground = no
[ssh]
client = no
accept = 443
connect = 127.0.0.1:$(get_ssh_port)
STUNEOF
      svc_enable stunnel4 || svc_enable stunnel || true
      svc_start stunnel4 || svc_start stunnel || true
      ;;
    squid)
      command -v squid >/dev/null 2>&1 && return 0
      [[ -f /etc/squid/squid.conf || -f /etc/squid3/squid.conf ]] && return 0
      install_pkg "squid" || return 1
      svc_enable squid || svc_enable squid3 || true
      svc_start squid || svc_start squid3 || true
      ;;
    *) log_error "target '$target' ไม่รองรับ"; return 1 ;;
  esac
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
        ensure_port_service_installed ssh || { pause; continue; }
        local ssh_cfg="/etc/ssh/sshd_config" curr_ssh
        curr_ssh="$(get_ssh_port)"
        echo -e "Port ปัจจุบัน: ${GREEN}$curr_ssh${NC}"
        read -r -p "Port ใหม่: " new_ssh
        is_port "$new_ssh" || { log_error "Port ไม่ถูกต้อง"; pause; continue; }
        local ssh_backup; ssh_backup="$(backup_file "$ssh_cfg")"
        if grep -qE "^#?[[:space:]]*Port" "$ssh_cfg"; then
          sed -i -E "s/^#?[[:space:]]*Port.*/Port ${new_ssh}/g" "$ssh_cfg"
        else echo "Port ${new_ssh}" >> "$ssh_cfg"; fi
        local sshd_bin; sshd_bin="$(command -v sshd 2>/dev/null || echo /usr/sbin/sshd)"
        if [[ -x "$sshd_bin" ]] && ! "$sshd_bin" -t >/dev/null 2>&1; then
          cp -a "$ssh_backup" "$ssh_cfg" 2>/dev/null || true
          log_error "Config ไม่ผ่าน validation - rollback แล้ว"
        else restart_ssh_service; log_info "เปลี่ยน SSH Port เป็น $new_ssh แล้ว!"; fi
        pause ;;
      2)
        ensure_port_service_installed dropbear || { pause; continue; }
        local cfg_drop=""
        [[ -f /etc/default/dropbear ]] && cfg_drop="/etc/default/dropbear"
        [[ -f /etc/sysconfig/dropbear ]] && cfg_drop="/etc/sysconfig/dropbear"
        [[ -z "$cfg_drop" ]] && { log_error "ไม่พบ config Dropbear"; pause; continue; }
        local curr_drop; curr_drop="$(grep "^DROPBEAR_PORT=" "$cfg_drop" | cut -d= -f2 || true)"
        [[ -z "$curr_drop" ]] && curr_drop="222"
        echo -e "Port ปัจจุบัน: ${GREEN}$curr_drop${NC}"
        read -r -p "Port ใหม่: " new_drop
        is_port "$new_drop" || { log_error "Port ไม่ถูกต้อง"; pause; continue; }
        backup_file "$cfg_drop" >/dev/null
        if grep -q "^DROPBEAR_PORT=" "$cfg_drop"; then
          sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=${new_drop}/g" "$cfg_drop"
        else echo "DROPBEAR_PORT=${new_drop}" >> "$cfg_drop"; fi
        svc_restart dropbear; log_info "เปลี่ยน Dropbear Port เป็น $new_drop แล้ว!"; pause ;;
      3)
        ensure_port_service_installed stunnel || { pause; continue; }
        local cfg_st="/etc/stunnel/stunnel.conf"
        [[ -f "$cfg_st" ]] || { log_error "ไม่พบ config Stunnel"; pause; continue; }
        local curr_st; curr_st="$(grep "^accept" "$cfg_st" | head -n1 | awk '{print $3}')"
        [[ -z "$curr_st" ]] && curr_st="443"
        echo -e "Port ปัจจุบัน: ${GREEN}$curr_st${NC}"
        read -r -p "Port ใหม่: " new_st
        is_port "$new_st" || { log_error "Port ไม่ถูกต้อง"; pause; continue; }
        backup_file "$cfg_st" >/dev/null
        if grep -q "^accept" "$cfg_st"; then
          sed -i "s/^accept.*/accept = ${new_st}/g" "$cfg_st"
        else printf "[ssh]\nclient = no\naccept = %s\nconnect = 127.0.0.1:%s\n" "$new_st" "$(get_ssh_port)" >> "$cfg_st"; fi
        svc_restart stunnel4 || svc_restart stunnel
        log_info "เปลี่ยน Stunnel Port เป็น $new_st แล้ว!"; pause ;;
      4)
        ensure_port_service_installed squid || { pause; continue; }
        local cfg_sq=""
        [[ -f /etc/squid/squid.conf ]] && cfg_sq="/etc/squid/squid.conf"
        [[ -f /etc/squid3/squid.conf ]] && cfg_sq="/etc/squid3/squid.conf"
        [[ -z "$cfg_sq" ]] && { log_error "ไม่พบ config Squid"; pause; continue; }
        local curr_sq; curr_sq="$(grep "^http_port" "$cfg_sq" | head -n1 | awk '{print $2}')"
        [[ -z "$curr_sq" ]] && curr_sq="3128"
        echo -e "Port ปัจจุบัน: ${GREEN}$curr_sq${NC}"
        read -r -p "Port ใหม่: " new_sq
        is_port "$new_sq" || { log_error "Port ไม่ถูกต้อง"; pause; continue; }
        backup_file "$cfg_sq" >/dev/null
        if grep -q "^http_port" "$cfg_sq"; then
          sed -i "s/^http_port.*/http_port ${new_sq}/g" "$cfg_sq"
        else echo "http_port ${new_sq}" >> "$cfg_sq"; fi
        svc_restart squid || svc_restart squid3
        log_info "เปลี่ยน Squid Port เป็น $new_sq แล้ว!"; pause ;;
      5)
        clear_screen
        echo -e "${WHITE}Protocol  Local Address         Program${NC}"
        echo -e "${YELLOW}------------------------------------------${NC}"
        if command -v ss >/dev/null 2>&1; then
          ss -tulnp | grep LISTEN | awk '{print $1, $5, $7}' | column -t
        elif command -v netstat >/dev/null 2>&1; then
          netstat -tulnp | grep LISTEN | awk '{print $1, $4, $7}' | column -t
        fi
        pause ;;
      0) return ;;
      *) log_error "เลือกไม่ถูกต้อง"; sleep 1 ;;
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
  command -v ufw >/dev/null 2>&1 || install_pkg "ufw"
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

function_websocket() {
  clear_screen
  local status_ws; svc_is_active sshplus-ws && status_ws="${GREEN}ONLINE${NC}" || status_ws="${RED}OFFLINE${NC}"
  echo -e "สถานะ WebSocket: $status_ws"
  echo "1) เปิด  2) ปิด  3) Log  0) กลับ"
  read -r -p "เลือก: " ws_opt
  case "$ws_opt" in
    1)
      svc_is_active sshplus-ws && { log_warn "ทำงานอยู่แล้ว"; pause; return; }
      read -r -p "Listen Port (80): " ws_port; [[ -z "$ws_port" ]] && ws_port=80
      is_port "$ws_port" || { log_error "Port ผิด"; pause; return; }
      is_port_in_use "$ws_port" && { log_error "Port ถูกใช้แล้ว"; pause; return; }
      local csp; csp="$(get_ssh_port)"
      cat <<'PYEOF' > "$WS_SCRIPT"
#!/usr/bin/env python3
import socket,threading,select,sys,logging
logging.basicConfig(level=logging.INFO,format="%(asctime)s %(levelname)s %(message)s")
BIND="0.0.0.0";SSH="127.0.0.1";BUF=4096;TMO=300;MAXC=1000
sem=threading.BoundedSemaphore(MAXC)
def close(s):
 try:s.shutdown(socket.SHUT_RDWR)
 except:pass
 finally:
  try:s.close()
  except:pass
def handler(cs,ca,sp):
 if not sem.acquire(blocking=False):close(cs);return
 ts=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
 try:
  ts.settimeout(10);ts.connect((SSH,sp));ts.settimeout(None)
  cs.settimeout(10);fp=cs.recv(BUF);cs.settimeout(None)
  if not fp:return
  rh=fp.decode("utf-8",errors="ignore")
  if rh.startswith("GET") or rh.startswith("CONNECT") or "HTTP/1." in rh:
   cs.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
  else:ts.sendall(fp)
  while True:
   r,_,_=select.select([cs,ts],[],[],TMO)
   if not r:break
   if cs in r:
    d=cs.recv(BUF)
    if not d:break
    ts.sendall(d)
   if ts in r:
    d=ts.recv(BUF)
    if not d:break
    cs.sendall(d)
 except Exception as e:logging.debug(f"{ca}: {e}")
 finally:close(cs);close(ts);sem.release()
def server(lp,sp):
 s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
 s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
 s.bind((BIND,lp));s.listen(1024)
 logging.info(f"WS {lp} -> SSH {sp}")
 while True:
  try:
   c,a=s.accept()
   threading.Thread(target=handler,args=(c,a,sp),daemon=True).start()
  except KeyboardInterrupt:break
  except Exception as e:logging.error(e)
if __name__=="__main__":
 if len(sys.argv)<3:sys.exit(1)
 server(int(sys.argv[1]),int(sys.argv[2]))
PYEOF
      chmod 700 "$WS_SCRIPT"
      svc_provision "sshplus-ws" "SSHPlus WS Proxy" "/usr/bin/python3 $WS_SCRIPT $ws_port $csp" "" "LimitNOFILE=51200
NoNewPrivileges=true"
      svc_daemon_reload; svc_enable sshplus-ws; svc_start sshplus-ws
      svc_is_active sshplus-ws && log_info "WS เริ่มแล้ว ($ws_port -> SSH:$csp)" || log_error "เริ่ม WS ไม่สำเร็จ"
      command -v ufw >/dev/null 2>&1 && ufw allow "$ws_port" >/dev/null 2>&1 || true
      pause ;;
    2) svc_is_active sshplus-ws && { svc_stop sshplus-ws; svc_disable sshplus-ws; svc_remove sshplus-ws; log_warn "หยุด WS แล้ว"; } || log_warn "WS ไม่ได้ทำงาน"; sleep 1 ;;
    3) svc_logs sshplus-ws 80; pause ;;
    0) return ;; *) sleep 1 ;;
  esac
}

function_openvpn() {
  clear_screen
  echo -e "${BLUE}│${BG_RED}      OPENVPN MANAGER (AUTO)      ${NC}${BLUE}│${NC}"
  if [[ ! -s "$OPENVPN_SCRIPT" ]]; then
    log_warn "กำลังดาวน์โหลด OpenVPN installer..."
    download_with_user_confirmation "OpenVPN Installer" "$URL_OPENVPN" "$OPENVPN_SCRIPT" "700" || { log_error "Download ไม่สำเร็จ"; pause; return; }
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
          download_with_user_confirmation "Xray Installer" "$URL_XRAY_INSTALL" "$xi" "700" || { rm -f "$xi"; pause; continue; }
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
