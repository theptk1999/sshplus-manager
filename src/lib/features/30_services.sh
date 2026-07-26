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
