#!/usr/bin/env bash
set -euo pipefail
log_info() { echo "[INFO] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
write_file() {
  local path="$1" mode="${2:-644}" dir temp
  dir="$(dirname "$path")"; mkdir -p "$dir"
  temp="$(mktemp "${dir}/.tmp.XXXXXX")"
  cat > "$temp"; chmod "$mode" "$temp"; mv "$temp" "$path"
}
[[ -d src ]] || die "Run from repo root."

# ==================================================
# colors compat
# ==================================================
log_info "Creating src/lib/core/colors_compat.sh"
write_file "src/lib/core/colors_compat.sh" 644 <<'XEOF'
# Why: alias สีจาก log.sh ให้ตรงกับโค้ดเดิมที่ใช้ $RED $GREEN etc.
RED="${SSHPLUS_RED:-}"
GREEN="${SSHPLUS_GREEN:-}"
YELLOW="${SSHPLUS_YELLOW:-}"
BLUE="${SSHPLUS_BLUE:-}"
CYAN="${SSHPLUS_CYAN:-}"
WHITE="${SSHPLUS_WHITE:-}"
BG_RED="${SSHPLUS_BG_RED:-\033[41;1;37m}"
NC="${SSHPLUS_NC:-}"
ON="${GREEN}●${NC}"
OFF="${RED}○${NC}"
XEOF

# ==================================================
# 20_network.sh REAL
# ==================================================
log_info "Creating src/lib/features/20_network.sh (REAL)"
write_file "src/lib/features/20_network.sh" 644 <<'XEOF'
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
XEOF

# ==================================================
# 30_services.sh REAL
# ==================================================
log_info "Creating src/lib/features/30_services.sh (REAL)"
write_file "src/lib/features/30_services.sh" 644 <<'XEOF'
# ==================================================
# Feature: Services (REAL)
# ==================================================

function_toggle_limit() {
  if svc_is_active sshplus-limiter; then
    svc_stop sshplus-limiter; svc_disable sshplus-limiter; svc_remove sshplus-limiter
    log_warn "หยุด SSH Limiter แล้ว"; sleep 1; return
  fi
  log_info "กำลังสร้าง SSH Limiter..."
  cat <<'LIMEOF' > "$LIMIT_SCRIPT"
#!/bin/bash
DB_FILE="/root/usuarios.db"
trap 'exit 0' SIGTERM
while true; do
  if [[ -f "$DB_FILE" ]]; then
    while IFS=: read -r user limit expire_epoch || [[ -n "${user:-}" ]]; do
      [[ -z "${user:-}" || -z "${limit:-}" ]] && continue
      [[ "$user" == "root" ]] && continue
      [[ "$limit" =~ ^[0-9]+$ ]] || continue
      count="$(pgrep -u "$user" -f "sshd:" 2>/dev/null | wc -l)"
      if [[ "$count" -gt "$limit" ]]; then
        pkill -TERM -u "$user" -f "sshd:" 2>/dev/null || true
        sleep 1
        pkill -KILL -u "$user" -f "sshd:" 2>/dev/null || true
      fi
    done < "$DB_FILE"
  fi
  sleep 4
done
LIMEOF
  chmod 700 "$LIMIT_SCRIPT"
  svc_provision "sshplus-limiter" "SSHPlus Limiter" "/bin/bash $LIMIT_SCRIPT" "" "LimitNOFILE=51200
NoNewPrivileges=true"
  svc_daemon_reload; svc_enable sshplus-limiter; svc_start sshplus-limiter
  svc_is_active sshplus-limiter && log_info "เปิด SSH Limiter แล้ว!" || log_error "เริ่ม Limiter ไม่สำเร็จ"
  sleep 1
}

function_toggle_badvpn() {
  clear_screen
  if svc_is_active badvpn; then
    svc_stop badvpn; svc_disable badvpn; svc_remove badvpn
    log_warn "หยุด BadVPN แล้ว"
  else
    if [[ ! -s "$BADVPN_BIN" ]]; then
      download_with_user_confirmation "BadVPN (primary)" "$URL_BADVPN" "$BADVPN_BIN" "755" || \
      download_with_user_confirmation "BadVPN (backup)" "$URL_BADVPN_BACKUP" "$BADVPN_BIN" "755" || \
      { log_error "ดาวน์โหลด BadVPN ไม่สำเร็จ"; rm -f "$BADVPN_BIN"; pause; return; }
    fi
    [[ -x "$BADVPN_BIN" ]] || { log_error "BadVPN ไม่พร้อม"; pause; return; }
    svc_provision "badvpn" "BadVPN UDPGW" "$BADVPN_BIN --loglevel none --listen-addr 127.0.0.1:7300 --max-clients 1000" "" "LimitNOFILE=51200
NoNewPrivileges=true"
    svc_daemon_reload; svc_enable badvpn; svc_start badvpn
    svc_is_active badvpn && log_info "เปิด BadVPN แล้ว! (Port 7300)" || log_error "เริ่ม BadVPN ไม่สำเร็จ"
  fi
  sleep 1
}

function_toggle_bot() {
  clear_screen
  local sb; svc_is_active sshplus-bot && sb="${GREEN}ONLINE${NC}" || sb="${RED}OFFLINE${NC}"
  echo -e "สถานะ Bot: $sb"
  echo "1) เปิด/ปิด  2) ตั้งค่า Token  3) Log  0) กลับ"
  read -r -p "เลือก: " bo
  case "$bo" in
    1)
      if svc_is_active sshplus-bot; then
        svc_stop sshplus-bot; svc_disable sshplus-bot; svc_remove sshplus-bot; log_warn "หยุด Bot แล้ว"
      else
        [[ -f "$BOT_SCRIPT" && -f "$BOT_ENV_FILE" ]] || { log_error "ตั้งค่า Token ก่อน (เมนู 2)"; pause; return; }
        chmod 700 "$BOT_SCRIPT"
        svc_provision "sshplus-bot" "SSHPlus Bot" "/usr/bin/python3 $BOT_SCRIPT" "$BOT_ENV_FILE" "RestartSec=10
NoNewPrivileges=true
ReadWritePaths=/var/log"
        svc_daemon_reload; svc_enable sshplus-bot; svc_start sshplus-bot
        svc_is_active sshplus-bot && log_info "เปิด Bot แล้ว!" || log_error "เริ่ม Bot ไม่สำเร็จ"
      fi; sleep 1 ;;
    2)
      read -r -p "Bot Token: " bt; read -r -p "Chat ID: " ci
      [[ -z "$bt" || -z "$ci" ]] && { log_error "ข้อมูลไม่ครบ"; pause; return; }
      mkdir -p "$BOT_ENV_DIR"; chmod 700 "$BOT_ENV_DIR"
      printf 'BOT_TOKEN=%s\nADMIN_ID=%s\n' "$bt" "$ci" > "$BOT_ENV_FILE"; chmod 600 "$BOT_ENV_FILE"
      cat <<'BOTPY' > "$BOT_SCRIPT"
#!/usr/bin/env python3
import os,sys,subprocess,time,datetime,fcntl,logging,re,html
LOG="/var/log/sshplus_bot.log";DB="/root/usuarios.db";LK=DB+".lock"
TK=os.environ.get("BOT_TOKEN","").strip();AI=os.environ.get("ADMIN_ID","").strip()
if not TK or not AI:sys.exit(1)
logging.basicConfig(filename=LOG,level=logging.INFO,format="%(asctime)s %(levelname)s %(message)s")
try:import requests
except ImportError:
 subprocess.run([sys.executable,"-m","pip","install","requests","--break-system-packages"],check=False,capture_output=True)
 import requests
def rc(a,i=None):return subprocess.run(a,input=i,text=True,capture_output=True,check=False)
def ue(u):return rc(["id",u]).returncode==0
def rl():
 if not os.path.exists(DB):return[]
 with open(DB) as f:return[l.strip() for l in f if l.strip()]
def wl(ls):
 t=DB+".tmp"
 with open(t,"w") as f:f.write("\n".join(ls)+"\n" if ls else "")
 os.chmod(t,0o600);os.replace(t,DB)
def ups(u,li,ex):
 with open(LK,"w") as lf:
  fcntl.flock(lf,fcntl.LOCK_EX);ls=rl()
  ls=[l for l in ls if not l.startswith(f"{u}:")]
  ls.append(f"{u}:{li}:{ex}");wl(ls);fcntl.flock(lf,fcntl.LOCK_UN)
def dele(u):
 with open(LK,"w") as lf:
  fcntl.flock(lf,fcntl.LOCK_EX);ls=rl()
  ls=[l for l in ls if not l.startswith(f"{u}:")]
  wl(ls);fcntl.flock(lf,fcntl.LOCK_UN)
def sm(t,cid=None):
 try:requests.post(f"https://api.telegram.org/bot{TK}/sendMessage",data={"chat_id":cid or AI,"text":t,"parse_mode":"HTML"},timeout=10)
 except Exception as e:logging.error(e)
def gu(o):
 try:
  r=requests.get(f"https://api.telegram.org/bot{TK}/getUpdates",params={"offset":o,"timeout":30},timeout=35)
  return r.json()
 except:time.sleep(5);return None
def ca(a):
 if len(a)<4:return "รูปแบบ: /add user pass days limit"
 u,p,d,l=a[0],a[1],a[2],a[3]
 if not re.match(r"^[a-zA-Z0-9_-]+$",u) or u=="root":return "❌ ชื่อไม่ถูกต้อง"
 if not d.isdigit() or int(d)<=0:return "❌ วันต้อง > 0"
 if not l.isdigit() or int(l)<=0:return "❌ ลิมิตต้อง > 0"
 if ue(u):return "❌ มีอยู่แล้ว"
 di,li=int(d),int(l)
 ed=rc(["date","-d",f"+{di} days","+%Y-%m-%d"]).stdout.strip()
 if rc(["useradd","-M","-s","/bin/false","-e",ed,u]).returncode!=0:return "❌ สร้างไม่สำเร็จ"
 if rc(["chpasswd"],i=f"{u}:{p}\n").returncode!=0:
  rc(["userdel","--force",u]);return "❌ ตั้งรหัสไม่สำเร็จ"
 ex=int(time.time())+(di*86400)
 try:ups(u,li,ex)
 except Exception as e:rc(["userdel","--force",u]);return f"❌ DB error: {html.escape(str(e))}"
 eh=datetime.datetime.fromtimestamp(ex).strftime("%d/%m/%Y")
 return f"✅ <b>{html.escape(u)}</b>\nรหัส: {html.escape(p)}\nวัน: {di}\nจอ: {li}\nหมดอายุ: {eh}"
def cd(a):
 if len(a)<1:return "รูปแบบ: /del user"
 u=a[0]
 if not ue(u):return f"❌ ไม่พบ: {html.escape(u)}"
 rc(["userdel","--force",u]);dele(u)
 return f"🗑 ลบ {html.escape(u)} แล้ว"
def cl():
 try:
  with open(LK,"w") as lf:fcntl.flock(lf,fcntl.LOCK_EX);ls=rl();fcntl.flock(lf,fcntl.LOCK_UN)
  if not ls:return "ไม่มีผู้ใช้"
  m="<b>📂 ผู้ใช้:</b>\n"
  for l in ls:
   p=l.split(":")
   if len(p)>=3:
    try:eh=datetime.datetime.fromtimestamp(int(p[2])).strftime("%d/%m/%Y")
    except:eh="N/A"
    m+=f"- <code>{html.escape(p[0])}</code> จอ:{html.escape(p[1])} หมดอายุ:{eh}\n"
  return m
 except Exception as e:return f"❌ {html.escape(str(e))}"
def main():
 logging.info("Bot started");sm("🤖 บอทเริ่มทำงาน!\n/add ชื่อ รหัส วัน จอ\n/del ชื่อ\n/list")
 o=0
 while True:
  u=gu(o)
  if u and "result" in u:
   for it in u["result"]:
    o=it["update_id"]+1
    if "message" not in it:continue
    ci=str(it["message"]["chat"]["id"]);tx=it["message"].get("text","")
    if ci!=AI:logging.warning(f"Unauthorized: {ci}");continue
    ps=tx.split()
    if not ps:continue
    cm=ps[0].split("@")[0].lower()
    try:
     if cm=="/start":sm("สวัสดี! บอทพร้อมใช้งาน")
     elif cm=="/add":sm(ca(ps[1:]))
     elif cm=="/del":sm(cd(ps[1:]))
     elif cm=="/list":sm(cl())
     else:sm("❌ คำสั่ง: /add /del /list")
    except Exception as e:logging.critical(e);sm(f"⚠️ {html.escape(str(e))}")
  time.sleep(1)
if __name__=="__main__":main()
BOTPY
      chmod 700 "$BOT_SCRIPT"; svc_daemon_reload
      svc_is_active sshplus-bot && svc_restart sshplus-bot
      log_info "บันทึก Token แล้ว!"; pause ;;
    3) svc_logs sshplus-bot 80; pause ;;
    0) return ;; *) sleep 1 ;;
  esac
}

function_auto_menu() {
  clear_screen
  local bashrc="/root/.bashrc" marker="# SSHPlus_AutoMenu_Marker"
  [[ -f "$bashrc" ]] || touch "$bashrc"
  if grep -q "$marker" "$bashrc"; then
    sed -i "/$marker/d" "$bashrc"
    log_info "ปิด Auto Menu แล้ว"
  else
    echo "[[ \"\$-\" == *i* ]] && bash '${SCRIPT_PATH:-/usr/local/sbin/sshplus}' ${marker}" >> "$bashrc"
    log_info "เปิด Auto Menu แล้ว!"
  fi
  sleep 1
}

function_ferramentas() {
  clear_screen
  echo "1) Speedtest  2) Fail2ban  3) UFW  4) Auto-Start  5) Reboot  0) กลับ"
  read -r -p "เลือก: " opt
  case "$opt" in
    1) install_pkg "speedtest-cli"; pause ;;
    2) install_pkg "fail2ban"; pause ;;
    3) install_pkg "ufw"; pause ;;
    4)
      for s in sshplus-limiter badvpn sshplus-bot sshplus-ws; do
        [[ -f "/etc/systemd/system/${s}.service" || -f "/etc/init.d/${s}" ]] && svc_enable "$s" && log_info "[OK] $s"
      done
      log_info "อัปเดต Auto-start แล้ว"; pause ;;
    5) read -r -p "YES เพื่อยืนยัน: " cr
       [[ "$cr" == "YES" ]] && { log_warn "Rebooting..."; sleep 3; reboot; } || { log_warn "ยกเลิก"; pause; } ;;
    0) return ;; *) pause ;;
  esac
}
XEOF

# ==================================================
# 40_tools.sh REAL
# ==================================================
log_info "Creating src/lib/features/40_tools.sh (REAL)"
write_file "src/lib/features/40_tools.sh" 644 <<'XEOF'
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
XEOF

log_info "Phase 5 completed. All features are now REAL."
echo
echo "Next:"
echo "  bash scripts/termux-prepare.sh"
echo "  bash dist/sshplus.sh"
echo "  git add . && git commit -m 'feat: all features real code' && git push"