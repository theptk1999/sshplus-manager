# ==================================================
# Feature: Services (REAL)
# Why: จัดการ limiter, badvpn, bot, auto menu, tools, websocket
# ==================================================

# Why: เปิด/ปิด SSH Limiter service
function_toggle_limit() {
  if svc_is_active sshplus-limiter; then
    svc_stop sshplus-limiter
    svc_disable sshplus-limiter
    svc_remove sshplus-limiter
    log_warn "หยุด SSH Limiter แล้ว"
    sleep 1
    return
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
  svc_daemon_reload
  svc_enable sshplus-limiter
  svc_start sshplus-limiter
  svc_is_active sshplus-limiter && log_info "เปิด SSH Limiter แล้ว!" || log_error "เริ่ม Limiter ไม่สำเร็จ"
  sleep 1
}

# Why: เปิด/ปิด BadVPN UDPGW
function_toggle_badvpn() {
  clear_screen
  if svc_is_active badvpn; then
    svc_stop badvpn
    svc_disable badvpn
    svc_remove badvpn
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
    svc_daemon_reload
    svc_enable badvpn
    svc_start badvpn
    svc_is_active badvpn && log_info "เปิด BadVPN แล้ว! (Port 7300)" || log_error "เริ่ม BadVPN ไม่สำเร็จ"
  fi
  sleep 1
}

# Why: เมนูจัดการ Telegram bot
function_toggle_bot() {
  clear_screen
  local sb
  svc_is_active sshplus-bot && sb="${GREEN}ONLINE${NC}" || sb="${RED}OFFLINE${NC}"
  echo -e "สถานะ Bot: $sb"
  echo "1) เปิด/ปิด  2) ตั้งค่า Token  3) Log  0) กลับ"
  read -r -p "เลือก: " bo
  case "$bo" in
    1)
      if svc_is_active sshplus-bot; then
        svc_stop sshplus-bot
        svc_disable sshplus-bot
        svc_remove sshplus-bot
        log_warn "หยุด Bot แล้ว"
      else
        [[ -f "$BOT_SCRIPT" && -f "$BOT_ENV_FILE" ]] || { log_error "ตั้งค่า Token ก่อน (เมนู 2)"; pause; return; }
        chmod 700 "$BOT_SCRIPT"
        svc_provision "sshplus-bot" "SSHPlus Bot" "/usr/bin/python3 $BOT_SCRIPT" "$BOT_ENV_FILE" "RestartSec=10
NoNewPrivileges=true
ReadWritePaths=/var/log"
        svc_daemon_reload
        svc_enable sshplus-bot
        svc_start sshplus-bot
        svc_is_active sshplus-bot && log_info "เปิด Bot แล้ว!" || log_error "เริ่ม Bot ไม่สำเร็จ"
      fi
      sleep 1
      ;;
    2)
      read -r -p "Bot Token: " bt
      read -r -p "Chat ID: " ci
      [[ -z "$bt" || -z "$ci" ]] && { log_error "ข้อมูลไม่ครบ"; pause; return; }
      mkdir -p "$BOT_ENV_DIR"
      chmod 700 "$BOT_ENV_DIR"
      printf 'BOT_TOKEN=%s\nADMIN_ID=%s\n' "$bt" "$ci" > "$BOT_ENV_FILE"
      chmod 600 "$BOT_ENV_FILE"
      cat <<'BOTPY' > "$BOT_SCRIPT"
#!/usr/bin/env python3
import os,sys,subprocess,time,datetime,fcntl,logging,re,html
LOG="/var/log/sshplus_bot.log"
DB="/root/usuarios.db"
LK=DB+".lock"
TK=os.environ.get("BOT_TOKEN","").strip()
AI=os.environ.get("ADMIN_ID","").strip()
if not TK or not AI:
    sys.exit(1)
logging.basicConfig(filename=LOG,level=logging.INFO,format="%(asctime)s %(levelname)s %(message)s")
try:
    import requests
except ImportError:
    subprocess.run([sys.executable,"-m","pip","install","requests","--break-system-packages"],check=False,capture_output=True)
    import requests
def rc(a,i=None):
    return subprocess.run(a,input=i,text=True,capture_output=True,check=False)
def ue(u):
    return rc(["id",u]).returncode==0
def rl():
    if not os.path.exists(DB):
        return []
    with open(DB) as f:
        return [l.strip() for l in f if l.strip()]
def wl(ls):
    t=DB+".tmp"
    with open(t,"w") as f:
        f.write("\n".join(ls)+"\n" if ls else "")
    os.chmod(t,0o600)
    os.replace(t,DB)
def ups(u,li,ex):
    with open(LK,"w") as lf:
        fcntl.flock(lf,fcntl.LOCK_EX)
        ls=rl()
        ls=[l for l in ls if not l.startswith(f"{u}:")]
        ls.append(f"{u}:{li}:{ex}")
        wl(ls)
        fcntl.flock(lf,fcntl.LOCK_UN)
def dele(u):
    with open(LK,"w") as lf:
        fcntl.flock(lf,fcntl.LOCK_EX)
        ls=rl()
        ls=[l for l in ls if not l.startswith(f"{u}:")]
        wl(ls)
        fcntl.flock(lf,fcntl.LOCK_UN)
def sm(t,cid=None):
    try:
        requests.post(f"https://api.telegram.org/bot{TK}/sendMessage",data={"chat_id":cid or AI,"text":t,"parse_mode":"HTML"},timeout=10)
    except Exception as e:
        logging.error(e)
def gu(o):
    try:
        r=requests.get(f"https://api.telegram.org/bot{TK}/getUpdates",params={"offset":o,"timeout":30},timeout=35)
        return r.json()
    except Exception:
        time.sleep(5)
        return None
def ca(a):
    if len(a)<4:
        return "รูปแบบ: /add user pass days limit"
    u,p,d,l=a[0],a[1],a[2],a[3]
    if not re.match(r"^[a-zA-Z0-9_-]+$",u) or u=="root":
        return "❌ ชื่อไม่ถูกต้อง"
    if not d.isdigit() or int(d)<=0:
        return "❌ วันต้อง > 0"
    if not l.isdigit() or int(l)<=0:
        return "❌ ลิมิตต้อง > 0"
    if ue(u):
        return "❌ มีอยู่แล้ว"
    di,li=int(d),int(l)
    ed=rc(["date","-d",f"+{di} days","+%Y-%m-%d"]).stdout.strip()
    if rc(["useradd","-M","-s","/bin/false","-e",ed,u]).returncode!=0:
        return "❌ สร้างไม่สำเร็จ"
    if rc(["chpasswd"],i=f"{u}:{p}\n").returncode!=0:
        rc(["userdel","--force",u])
        return "❌ ตั้งรหัสไม่สำเร็จ"
    ex=int(time.time())+(di*86400)
    try:
        ups(u,li,ex)
    except Exception as e:
        rc(["userdel","--force",u])
        return f"❌ DB error: {html.escape(str(e))}"
    eh=datetime.datetime.fromtimestamp(ex).strftime("%d/%m/%Y")
    return f"✅ <b>{html.escape(u)}</b>\nรหัส: {html.escape(p)}\nวัน: {di}\nจอ: {li}\nหมดอายุ: {eh}"
def cd(a):
    if len(a)<1:
        return "รูปแบบ: /del user"
    u=a[0]
    if not ue(u):
        return f"❌ ไม่พบ: {html.escape(u)}"
    rc(["userdel","--force",u])
    dele(u)
    return f"🗑 ลบ {html.escape(u)} แล้ว"
def cl():
    try:
        with open(LK,"w") as lf:
            fcntl.flock(lf,fcntl.LOCK_EX)
            ls=rl()
            fcntl.flock(lf,fcntl.LOCK_UN)
        if not ls:
            return "ไม่มีผู้ใช้"
        m="<b>📂 ผู้ใช้:</b>\n"
        for l in ls:
            p=l.split(":")
            if len(p)>=3:
                try:
                    eh=datetime.datetime.fromtimestamp(int(p[2])).strftime("%d/%m/%Y")
                except Exception:
                    eh="N/A"
                m+=f"- <code>{html.escape(p[0])}</code> จอ:{html.escape(p[1])} หมดอายุ:{eh}\n"
        return m
    except Exception as e:
        return f"❌ {html.escape(str(e))}"
def main():
    logging.info("Bot started")
    sm("🤖 บอทเริ่มทำงาน!\n/add ชื่อ รหัส วัน จอ\n/del ชื่อ\n/list")
    o=0
    while True:
        u=gu(o)
        if u and "result" in u:
            for it in u["result"]:
                o=it["update_id"]+1
                if "message" not in it:
                    continue
                ci=str(it["message"]["chat"]["id"])
                tx=it["message"].get("text","")
                if ci!=AI:
                    logging.warning(f"Unauthorized: {ci}")
                    continue
                ps=tx.split()
                if not ps:
                    continue
                cm=ps[0].split("@")[0].lower()
                try:
                    if cm=="/start":
                        sm("สวัสดี! บอทพร้อมใช้งาน")
                    elif cm=="/add":
                        sm(ca(ps[1:]))
                    elif cm=="/del":
                        sm(cd(ps[1:]))
                    elif cm=="/list":
                        sm(cl())
                    else:
                        sm("❌ คำสั่ง: /add /del /list")
                except Exception as e:
                    logging.critical(e)
                    sm(f"⚠️ {html.escape(str(e))}")
        time.sleep(1)
if __name__=="__main__":
    main()
BOTPY
      chmod 700 "$BOT_SCRIPT"
      svc_daemon_reload
      svc_is_active sshplus-bot && svc_restart sshplus-bot
      log_info "บันทึก Token แล้ว!"
      pause
      ;;
    3)
      svc_logs sshplus-bot 80
      pause
      ;;
    0)
      return
      ;;
    *)
      sleep 1
      ;;
  esac
}

# Why: เปิด/ปิด auto menu — เรียก SSHPlus อัตโนมัติเมื่อ login แบบ interactive
#      ใช้ /etc/profile.d เพื่อให้มีผลกับทุก user (root และ user ที่มี sudo)
function_auto_menu() {
  clear_screen
  local profile="/etc/profile.d/zz-sshplus-automenu.sh"
  local bashrc="/root/.bashrc"
  local marker="# SSHPlus_AutoMenu_Marker"

  # Why: ถ้าเปิดอยู่แล้ว → ปิด (ลบทั้ง profile.d และ hook เก่าใน .bashrc)
  if [[ -f "$profile" ]] || grep -q "$marker" "$bashrc" 2>/dev/null; then
    rm -f "$profile"
    sed -i "/$marker/d" "$bashrc" 2>/dev/null || true
    log_info "ปิด Auto Menu แล้ว"
  else
    # Why: เขียน profile script ที่ตรวจว่า shell เป็น interactive + มี tty จริง
    #      root → รันตรง, user อื่น → รันผ่าน sudo (ถ้ามี NOPASSWD sudo)
    cat <<'AMEOF' > "$profile"
# SSHPlus_AutoMenu_Marker
if [ -n "$PS1" ] && [ -t 0 ] && [ -x /usr/local/sbin/sshplus ]; then
  if [ "$(id -u)" = "0" ]; then
    /usr/local/sbin/sshplus
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo /usr/local/sbin/sshplus
  fi
fi
AMEOF
    chmod 644 "$profile"
    # Why: ลบ hook เก่าที่ค้างใน .bashrc กันเมนูเด้งซ้ำ 2 รอบ
    sed -i "/$marker/d" "$bashrc" 2>/dev/null || true
    log_info "เปิด Auto Menu แล้ว! (มีผลเมื่อ login ครั้งถัดไป)"
  fi
  sleep 1
}

# Why: รวมเครื่องมือเสริม
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
      log_info "อัปเดต Auto-start แล้ว"
      pause
      ;;
    5)
      read -r -p "YES เพื่อยืนยัน: " cr
      [[ "$cr" == "YES" ]] && { log_warn "Rebooting..."; sleep 3; reboot; } || { log_warn "ยกเลิก"; pause; }
      ;;
    0) return ;;
    *) pause ;;
  esac
}

# Why: เมนู WebSocket proxy v2.1 รองรับ RFC 6455 + Smart Detection
function_websocket() {
  clear_screen
  local status_ws
  svc_is_active sshplus-ws && status_ws="${GREEN}ONLINE${NC}" || status_ws="${RED}OFFLINE${NC}"
  echo -e "สถานะ WebSocket: $status_ws"
  echo "1) เปิด  2) ปิด  3) Log  0) กลับ"
  read -r -p "เลือก: " ws_opt
  case "$ws_opt" in
    1)
      svc_is_active sshplus-ws && { log_warn "ทำงานอยู่แล้ว"; pause; return; }
      read -r -p "Listen Port (80): " ws_port
      [[ -z "$ws_port" ]] && ws_port=80
      is_port "$ws_port" || { log_error "Port ผิด"; pause; return; }
      is_port_in_use "$ws_port" && { log_error "Port ถูกใช้แล้ว"; pause; return; }
      local csp
      csp="$(get_ssh_port)"
      log_info "Generating WS Proxy v2.1..."
      cat <<'WSEOF' > "$WS_SCRIPT"
#!/usr/bin/env python3
import socket,threading,select,signal,sys,time,struct,hashlib,base64,logging
BIND_ADDR="0.0.0.0"
SSH_ADDR="127.0.0.1"
BUFFER_SIZE=8192
IDLE_TIMEOUT=300
MAX_CONNECTIONS=1000
WS_MAGIC="258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
logging.basicConfig(level=logging.INFO,format="%(asctime)s [%(levelname)s] %(message)s",datefmt="%Y-%m-%d %H:%M:%S")
logger=logging.getLogger("ws-proxy")
class Stats:
    def __init__(self):
        self._lock=threading.Lock()
        self.active=0
        self.total=0
        self.rejected=0
        self.start_time=time.time()
    def connect(self):
        with self._lock:
            self.active+=1
            self.total+=1
    def disconnect(self):
        with self._lock:
            self.active=max(0,self.active-1)
    def reject(self):
        with self._lock:
            self.rejected+=1
    def summary(self):
        with self._lock:
            uptime=int(time.time()-self.start_time)
            h,m=divmod(uptime,3600)
            m//=60
            return f"uptime={h}h{m}m active={self.active} total={self.total} rejected={self.rejected}"
stats=Stats()
shutdown_event=threading.Event()
def signal_handler(signum,frame):
    sig_name=signal.Signals(signum).name
    logger.info(f"Received {sig_name}, shutting down...")
    logger.info(f"Final stats: {stats.summary()}")
    shutdown_event.set()
signal.signal(signal.SIGTERM,signal_handler)
signal.signal(signal.SIGINT,signal_handler)
def close_socket(sock):
    try:
        sock.shutdown(socket.SHUT_RDWR)
    except OSError:
        pass
    finally:
        try:
            sock.close()
        except OSError:
            pass
def set_keepalive(sock):
    try:
        sock.setsockopt(socket.SOL_SOCKET,socket.SO_KEEPALIVE,1)
        if hasattr(socket,"TCP_KEEPIDLE"):
            sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_KEEPIDLE,60)
        if hasattr(socket,"TCP_KEEPINTVL"):
            sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_KEEPINTVL,10)
        if hasattr(socket,"TCP_KEEPCNT"):
            sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_KEEPCNT,3)
    except OSError:
        pass
def ws_accept_key(key):
    digest=hashlib.sha1((key.strip()+WS_MAGIC).encode()).digest()
    return base64.b64encode(digest).decode()
def parse_http_headers(data):
    headers={}
    try:
        text=data.decode("utf-8",errors="ignore")
        for line in text.split("\r\n")[1:]:
            if ":" in line:
                k,v=line.split(":",1)
                headers[k.strip().lower()]=v.strip()
    except Exception:
        pass
    return headers
def _recv_exact(sock,n):
    data=bytearray()
    while len(data)<n:
        try:
            chunk=sock.recv(n-len(data))
            if not chunk:
                return None
            data.extend(chunk)
        except OSError:
            return None
    return bytes(data)
def read_ws_frame(sock):
    try:
        header=_recv_exact(sock,2)
        if header is None:
            return None
        fin=bool(header[0]&0x80)
        opcode=header[0]&0x0F
        masked=bool(header[1]&0x80)
        length=header[1]&0x7F
        if length==126:
            raw=_recv_exact(sock,2)
            if raw is None:
                return None
            length=struct.unpack("!H",raw)[0]
        elif length==127:
            raw=_recv_exact(sock,8)
            if raw is None:
                return None
            length=struct.unpack("!Q",raw)[0]
        if length>10*1024*1024:
            logger.warning(f"WS frame too large: {length}")
            return None
        mask_key=b""
        if masked:
            mask_key=_recv_exact(sock,4)
            if mask_key is None:
                return None
        payload=b""
        if length>0:
            payload=_recv_exact(sock,length)
            if payload is None:
                return None
        if masked and mask_key:
            payload=bytes(b^mask_key[i%4] for i,b in enumerate(payload))
        return opcode,payload,fin
    except (OSError,struct.error):
        return None
def build_ws_frame(opcode,payload):
    frame=bytearray()
    frame.append(0x80|opcode)
    length=len(payload)
    if length<126:
        frame.append(length)
    elif length<65536:
        frame.append(126)
        frame.extend(struct.pack("!H",length))
    else:
        frame.append(127)
        frame.extend(struct.pack("!Q",length))
    frame.extend(payload)
    return bytes(frame)
def raw_tcp_relay(client,target):
    try:
        while not shutdown_event.is_set():
            r,_,_=select.select([client,target],[],[],5)
            if not r:
                continue
            if client in r:
                data=client.recv(BUFFER_SIZE)
                if not data:
                    break
                target.sendall(data)
            if target in r:
                data=target.recv(BUFFER_SIZE)
                if not data:
                    break
                client.sendall(data)
    except OSError:
        pass
def ws_frame_relay(client,target):
    try:
        while not shutdown_event.is_set():
            r,_,_=select.select([client,target],[],[],5)
            if not r:
                continue
            if client in r:
                result=read_ws_frame(client)
                if result is None:
                    break
                opcode,payload,fin=result
                if opcode==0x8:
                    close_frame=build_ws_frame(0x8,payload[:2] if len(payload)>=2 else b"")
                    client.sendall(close_frame)
                    break
                elif opcode==0x9:
                    pong=build_ws_frame(0xA,payload)
                    client.sendall(pong)
                    continue
                elif opcode==0xA:
                    continue
                elif opcode in (0x1,0x2,0x0):
                    if payload:
                        target.sendall(payload)
                else:
                    break
            if target in r:
                data=target.recv(BUFFER_SIZE)
                if not data:
                    break
                ws_frame=build_ws_frame(0x2,data)
                client.sendall(ws_frame)
    except OSError:
        pass
def handler(client_socket,client_addr,ssh_port):
    stats.connect()
    peer=f"{client_addr[0]}:{client_addr[1]}"
    target_socket=None
    try:
        set_keepalive(client_socket)
        client_socket.settimeout(15)
        first_payload=bytearray()
        chunk=client_socket.recv(BUFFER_SIZE)
        if chunk:
            first_payload.extend(chunk)
        if first_payload:
            first_line=first_payload.split(b"\r\n")[0].decode("utf-8",errors="ignore")
            looks_http=(first_line.startswith("GET ") or first_line.startswith("POST ") or
                        first_line.startswith("CONNECT ") or first_line.startswith("HEAD ") or
                        "HTTP/1." in first_line)
            if looks_http and b"\r\n\r\n" not in first_payload:
                client_socket.settimeout(5)
                try:
                    while b"\r\n\r\n" not in first_payload and len(first_payload)<BUFFER_SIZE:
                        chunk=client_socket.recv(BUFFER_SIZE)
                        if not chunk:
                            break
                        first_payload.extend(chunk)
                except socket.timeout:
                    pass
        client_socket.settimeout(None)
        if not first_payload:
            return
        first_payload=bytes(first_payload)
        header_text=first_payload.decode("utf-8",errors="ignore")
        fl=header_text.split("\r\n")[0]
        is_http=fl[:4] in ("GET ","POST","HEAD") or fl[:8]=="CONNECT " or "HTTP/1." in fl
        target_socket=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        set_keepalive(target_socket)
        try:
            target_socket.settimeout(10)
            target_socket.connect((SSH_ADDR,ssh_port))
            target_socket.settimeout(None)
        except Exception as e:
            logger.error(f"[{peer}] Backend failed (Port {ssh_port}): {e}")
            if is_http:
                err502=b"HTTP/1.1 502 Bad Gateway\r\n"
                err502+=b"Connection: close\r\n\r\n"
                client_socket.sendall(err502)
            return
        if is_http:
            headers=parse_http_headers(first_payload)
            ws_key=headers.get("sec-websocket-key","")
            upgrade=headers.get("upgrade","").lower()
            if "websocket" in upgrade and ws_key:
                accept=ws_accept_key(ws_key)
                ws_handshake=("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "+accept+"\r\n\r\n")
                client_socket.sendall(ws_handshake.encode("utf-8"))
                logger.info(f"[WS] {peer} -> SSH:{ssh_port}")
                ws_frame_relay(client_socket,target_socket)
            else:
                http_response="HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
                client_socket.sendall(http_response.encode("utf-8"))
                logger.info(f"[HTTP] {peer} -> SSH:{ssh_port}")
                raw_tcp_relay(client_socket,target_socket)
        else:
            logger.info(f"[RAW] {peer} -> SSH:{ssh_port}")
            target_socket.sendall(first_payload)
            raw_tcp_relay(client_socket,target_socket)
    except ConnectionRefusedError:
        logger.error(f"[{peer}] SSH refused on port {ssh_port}")
    except socket.timeout:
        logger.warning(f"[{peer}] Timeout")
    except OSError as exc:
        logger.debug(f"[{peer}] Error: {exc}")
    except Exception as exc:
        logger.error(f"[{peer}] Unexpected: {exc}")
    finally:
        close_socket(client_socket)
        if target_socket:
            try:
                close_socket(target_socket)
            except Exception:
                pass
        stats.disconnect()
def stats_reporter():
    while not shutdown_event.is_set():
        shutdown_event.wait(300)
        if not shutdown_event.is_set():
            logger.info(f"[STATS] {stats.summary()}")
def server(listen_port,ssh_port):
    semaphore=threading.BoundedSemaphore(MAX_CONNECTIONS)
    server_socket=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    server_socket.settimeout(2)
    try:
        server_socket.bind((BIND_ADDR,listen_port))
    except OSError as exc:
        logger.critical(f"Cannot bind to port {listen_port}: {exc}")
        sys.exit(1)
    server_socket.listen(1024)
    logger.info("SSHPlus WS Proxy v2.1 started")
    logger.info(f"Listening: {BIND_ADDR}:{listen_port} -> SSH {SSH_ADDR}:{ssh_port}")
    logger.info("Modes: Raw TCP | HTTP Upgrade | WebSocket (RFC 6455)")
    stats_thread=threading.Thread(target=stats_reporter,daemon=True)
    stats_thread.start()
    while not shutdown_event.is_set():
        try:
            client_socket,client_addr=server_socket.accept()
        except socket.timeout:
            continue
        except OSError:
            if shutdown_event.is_set():
                break
            continue
        acquired=semaphore.acquire(blocking=False)
        if not acquired:
            stats.reject()
            logger.warning(f"Max connections reached, rejecting {client_addr[0]}")
            close_socket(client_socket)
            continue
        def wrapped_handler(cs=client_socket,ca=client_addr):
            try:
                handler(cs,ca,ssh_port)
            finally:
                semaphore.release()
        t=threading.Thread(target=wrapped_handler,daemon=True)
        t.start()
    logger.info("Shutting down...")
    close_socket(server_socket)
    logger.info(f"Server stopped. {stats.summary()}")
if __name__=="__main__":
    if len(sys.argv)<3:
        print("Usage: proxy_ws.py <Listen Port> <SSH Port>")
        sys.exit(1)
    try:
        p_listen=int(sys.argv[1])
        p_ssh=int(sys.argv[2])
    except ValueError:
        logger.critical("Ports must be integers.")
        sys.exit(1)
    if not (1<=p_listen<=65535) or not (1<=p_ssh<=65535):
        logger.critical("Ports must be 1-65535.")
        sys.exit(1)
    server(p_listen,p_ssh)
WSEOF
      chmod 700 "$WS_SCRIPT"
      svc_provision "sshplus-ws" "SSHPlus WS Proxy v2.1" "/usr/bin/python3 $WS_SCRIPT $ws_port $csp" "" "LimitNOFILE=51200
NoNewPrivileges=true"
      svc_daemon_reload
      svc_enable sshplus-ws
      svc_start sshplus-ws
      svc_is_active sshplus-ws && log_info "WS เริ่มแล้ว ($ws_port -> SSH:$csp)" || log_error "เริ่ม WS ไม่สำเร็จ"
      command -v ufw >/dev/null 2>&1 && ufw allow "$ws_port" >/dev/null 2>&1 || true
      pause
      ;;
    2)
      svc_is_active sshplus-ws && { svc_stop sshplus-ws; svc_disable sshplus-ws; svc_remove sshplus-ws; log_warn "หยุด WS แล้ว"; } || log_warn "WS ไม่ได้ทำงาน"
      sleep 1
      ;;
    3)
      svc_logs sshplus-ws 80
      pause
      ;;
    0)
      return
      ;;
    *)
      sleep 1
      ;;
  esac
}
