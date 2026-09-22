# ==================================================
# Feature: User Management (REAL)
# Why: จัดการ SSH user จริงจาก sshplusthai.sh
# ==================================================

function_create_user() {
  clear_screen
  echo -e "${MENU_BLUE:-}┌──────────────────────────────────────────┐${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}│          สร้างผู้ใช้งาน SSH              ${MENU_NC:-}${MENU_BLUE:-}│${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}└──────────────────────────────────────────┘${MENU_NC:-}"
  read -r -p "ชื่อผู้ใช้งาน (Username): " username
  [[ -z "$username" ]] && return
  if ! is_username "$username"; then log_error "ห้ามใช้อักขระพิเศษ! อนุญาตแค่ a-z, 0-9, _ และ -"; pause; return; fi
  if id "$username" >/dev/null 2>&1; then log_error "ชื่อ '$username' มีอยู่แล้ว!"; pause; return; fi
  local password="" confirm_password=""
  prompt_password "รหัสผ่าน (Password): " password
  prompt_password "ยืนยันรหัสผ่าน: " confirm_password
  if [[ -z "$password" ]]; then log_error "รหัสผ่านห้ามว่าง"; pause; return; fi
  if [[ "$password" != "$confirm_password" ]]; then log_error "รหัสผ่านไม่ตรงกัน"; pause; return; fi
  read -r -p "จำนวนวัน (Days): " days
  is_uint "$days" || days=30
  read -r -p "จำกัดการเชื่อมต่อ (Limit): " limit
  is_uint "$limit" || limit=1
  local expire_date
  expire_date="$(date -d "+${days} days" +%Y-%m-%d)" || { log_error "คำนวณวันหมดอายุไม่สำเร็จ"; pause; return; }
  useradd -M -s /bin/false -e "$expire_date" "$username"
  if [[ $? -ne 0 ]]; then log_error "สร้างผู้ใช้ไม่สำเร็จ"; pause; return; fi
  printf '%s:%s\n' "$username" "$password" | chpasswd
  if [[ $? -ne 0 ]]; then safe_userdel_local "$username" >/dev/null 2>&1 || true; log_error "ตั้งรหัสผ่านไม่สำเร็จ"; pause; return; fi
  if ! chage -M -1 "$username" >/dev/null 2>&1; then
    safe_userdel_local "$username" >/dev/null 2>&1 || true
    log_error "ตั้งค่า password aging ไม่สำเร็จ"
    pause
    return
  fi
  local expire_epoch
  expire_epoch="$(date -d "$expire_date" +%s)"
  db_write_user_record "$username" "$limit" "$expire_epoch"
  local server_ip
  server_ip="$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo 'N/A')"
  clear_screen
  echo -e "${MENU_GREEN:-}[INFO]${MENU_NC:-} สร้างบัญชีสำเร็จ!"
  echo -e "  Host/IP  : ${server_ip}"
  echo -e "  Username : ${username}"
  echo -e "  Password : ${password}"
  echo -e "  Limit    : ${limit}"
  echo -e "  Expire   : $(date -d "$expire_date" +%d/%m/%Y) (${days} วัน)"
  pause
}

function_create_test() {
  clear_screen
  echo -e "${MENU_BLUE:-}┌──────────────────────────────────────────┐${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}│       สร้างไอดีทดสอบ (24ชม.)            ${MENU_NC:-}${MENU_BLUE:-}│${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}└──────────────────────────────────────────┘${MENU_NC:-}"
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ทดสอบ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  if ! is_username "$username"; then log_error "ชื่อไม่ถูกต้อง"; pause; return; fi
  if id "$username" >/dev/null 2>&1; then log_error "ชื่อมีอยู่แล้ว!"; pause; return; fi
  local password="" confirm_password=""
  prompt_password "รหัสผ่าน: " password
  prompt_password "ยืนยัน: " confirm_password
  if [[ -z "$password" || "$password" != "$confirm_password" ]]; then log_error "รหัสผ่านว่างหรือไม่ตรงกัน"; pause; return; fi
  local expire_date
  expire_date="$(date -d "+1 days" +%Y-%m-%d)" || { log_error "คำนวณวันที่ไม่สำเร็จ"; pause; return; }
  useradd -M -s /bin/false -e "$expire_date" "$username" || { log_error "สร้างผู้ใช้ไม่สำเร็จ"; pause; return; }
  printf '%s:%s\n' "$username" "$password" | chpasswd || { safe_userdel_local "$username" >/dev/null 2>&1 || true; log_error "ตั้งรหัสผ่านไม่สำเร็จ"; pause; return; }
  if ! chage -M -1 "$username" >/dev/null 2>&1; then
    safe_userdel_local "$username" >/dev/null 2>&1 || true
    log_error "ตั้งค่า password aging ไม่สำเร็จ"
    pause
    return
  fi
  local expire_epoch
  expire_epoch="$(date -d "$expire_date" +%s)"
  db_write_user_record "$username" 1 "$expire_epoch"
  log_info "สร้างไอดีทดสอบสำเร็จ! Username: ${username} | Password: ${password}"
  pause
}

function_delete_user() {
  local username=""
  local user_line=""
  local confirm_delete=""
  local delete_rc=0

  clear_screen
  function_list_users "inline"

  read -r -p "ชื่อผู้ใช้ที่จะลบ (พิมพ์ 0 เพื่อยกเลิก): " username

  [[ -z "$username" || "$username" == "0" ]] && return

  if ! is_username "$username"; then
    log_error "ชื่อผู้ใช้ไม่ผ่าน safety check"
    pause
    return
  fi

  user_line="$(db_get_user_record "$username")"

  if [[ -z "$user_line" ]]; then
    log_error "ไม่พบผู้ใช้นี้ในฐานข้อมูล SSHPlus"
    pause
    return
  fi

  read -r -p "ยืนยันลบ $username ? (YES/NO): " confirm_delete

  if [[ "$confirm_delete" != "YES" ]]; then
    log_warn "ยกเลิก"
    pause
    return
  fi

  db_delete_managed_user "$username"
  delete_rc=$?

  case "$delete_rc" in
    0)
      log_info "ลบ $username เรียบร้อย!"
      ;;
    2)
      log_error "ชื่อผู้ใช้ไม่ผ่าน safety check"
      ;;
    3)
      log_error "ไม่พบ $username ในฐานข้อมูล SSHPlus"
      ;;
    4)
      log_error "ปฏิเสธการลบ system/protected account"
      ;;
    5)
      log_error "userdel ไม่สำเร็จ ฐานข้อมูลยังคงถูกเก็บไว้"
      ;;
    6)
      log_error "ลบ Linux user แล้ว แต่ cleanup DB ไม่สำเร็จ"
      ;;
    *)
      log_error "ลบผู้ใช้ไม่สำเร็จ (code: $delete_rc)"
      ;;
  esac

  pause
}

function_renew_user() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ที่จะต่ออายุ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  local user_line
  user_line="$(db_get_user_record "$username")"
  if [[ -z "$user_line" ]]; then log_error "ไม่พบผู้ใช้นี้!"; pause; return; fi
  local old_limit old_expire now
  old_limit="$(echo "$user_line" | cut -d: -f2)"
  old_expire="$(echo "$user_line" | cut -d: -f3)"
  now="$(date +%s)"
  read -r -p "จำนวนวันที่ต้องการเพิ่ม: " days
  if ! is_uint "$days" || [[ "$days" -le 0 ]]; then log_error "ต้องเป็นตัวเลข > 0"; pause; return; fi
  local new_expire
  if is_uint "$old_expire" && [[ "$old_expire" -ge "$now" ]]; then
    new_expire="$(date -d "@$old_expire + $days days" +%s)"
  else
    new_expire="$(date -d "+$days days" +%s)"
  fi
  local final_date_str
  final_date_str="$(date -d "@$new_expire" +%Y-%m-%d)"
  chage -E "$final_date_str" "$username" >/dev/null 2>&1 || true
  chage -M -1 "$username" >/dev/null 2>&1 || true
  db_write_user_record "$username" "$old_limit" "$new_expire"
  log_info "ต่ออายุสำเร็จ! Expire ใหม่: $(date -d "@$new_expire" +%d/%m/%Y)"
  pause
}

function_users_online() {
  clear_screen
  printf "%-20s | %-10s | %-15s\n" "User" "PID" "Time"
  echo "------------------------------------------------"
  local found=0
  while read -r line; do
    local user pid etime
    user="$(sed -n 's/.*sshd: \([a-zA-Z0-9_-]*\).*/\1/p' <<< "$line")"
    pid="$(awk '{print $1}' <<< "$line")"
    etime="$(awk '{print $2}' <<< "$line")"
    if [[ -n "$user" && "$user" != "root" ]]; then
      printf "%-20s | %-10s | %-15s\n" "$user" "$pid" "$etime"
      found=1
    fi
  done < <(ps -eo pid,etime,args 2>/dev/null | grep "sshd: " | grep -v "grep" | grep -v "priv" || true)
  [[ "$found" -eq 0 ]] && echo "ไม่มีผู้ใช้กำลังออนไลน์"
  pause
}

function_change_expiry() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  local user_line
  user_line="$(db_get_user_record "$username")"
  [[ -z "$user_line" ]] && { log_error "ไม่พบ!"; pause; return; }
  read -r -p "วันหมดอายุใหม่ (YYYY-MM-DD): " new_date
  is_date "$new_date" || { log_error "รูปแบบวันที่ผิด!"; pause; return; }
  local new_epoch limit
  new_epoch="$(date -d "$new_date" +%s)"
  limit="$(echo "$user_line" | cut -d: -f2)"
  db_write_user_record "$username" "$limit" "$new_epoch"
  chage -E "$new_date" "$username" >/dev/null 2>&1 || true
  chage -M -1 "$username" >/dev/null 2>&1 || true
  log_info "อัปเดตวันหมดอายุเป็น: $new_date"
  pause
}

function_change_limit() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  local user_line
  user_line="$(db_get_user_record "$username")"
  [[ -z "$user_line" ]] && { log_error "ไม่พบ!"; pause; return; }
  local expire_epoch
  expire_epoch="$(echo "$user_line" | cut -d: -f3)"
  read -r -p "ลิมิตใหม่: " new_limit
  if ! is_uint "$new_limit" || [[ "$new_limit" -le 0 ]]; then log_error "ต้องเป็นตัวเลข > 0"; pause; return; fi
  db_write_user_record "$username" "$new_limit" "$expire_epoch"
  log_info "อัปเดตลิมิตเป็น: $new_limit"
  pause
}

function_change_pass() {
  clear_screen
  function_list_users "inline"
  read -r -p "ชื่อผู้ใช้ (พิมพ์ 0 เพื่อยกเลิก): " username
  [[ -z "$username" || "$username" == "0" ]] && return
  id "$username" >/dev/null 2>&1 || { log_error "ไม่พบผู้ใช้ในระบบ!"; pause; return; }
  local newpass="" confirmpass=""
  prompt_password "รหัสผ่านใหม่: " newpass
  prompt_password "ยืนยัน: " confirmpass
  [[ -z "$newpass" ]] && { log_error "รหัสผ่านห้ามว่าง"; pause; return; }
  [[ "$newpass" != "$confirmpass" ]] && { log_error "ไม่ตรงกัน"; pause; return; }
  printf '%s:%s\n' "$username" "$newpass" | chpasswd || { log_error "เปลี่ยนรหัสผ่านไม่สำเร็จ"; pause; return; }
  chage -M -1 "$username" >/dev/null 2>&1 || true
  log_info "เปลี่ยนรหัสผ่านสำเร็จ!"
  pause
}

function_remove_expired() {
  log_info "กำลังตรวจสอบบัญชีที่หมดอายุ..."
  db_remove_expired
  sleep 1
}

function_list_users() {
  local display_mode="${1:-}"
  [[ "$display_mode" != "inline" ]] && clear_screen
  printf "%-15s | %-10s | %-15s\n" "User" "Limit" "Expire"
  echo "------------------------------------------------"
  local user_count=0
  if [[ -f "${DB_FILE:-/root/usuarios.db}" ]]; then
    while IFS=: read -r user lim expire_epoch || [[ -n "${user:-}" ]]; do
      [[ -z "${user:-}" && -z "${lim:-}" && -z "${expire_epoch:-}" ]] && continue
      local exp_date="N/A"
      is_uint "$expire_epoch" && exp_date="$(date -d "@$expire_epoch" +%d/%m/%Y 2>/dev/null || echo 'N/A')"
      printf "%-15s | %-10s | %-15s\n" "$user" "$lim" "$exp_date"
      user_count=$((user_count + 1))
    done < "${DB_FILE:-/root/usuarios.db}"
  fi
  [[ "$user_count" -eq 0 ]] && echo "ไม่มีผู้ใช้งานในระบบ"
  [[ "$display_mode" != "inline" ]] && pause
}

function_backup_users() {
  while true; do
    clear_screen
    echo "1) สร้าง Backup"
    echo "2) Restore Backup"
    echo "0) ย้อนกลับ"
    read -r -p "เลือก: " b_opt
    case "$b_opt" in
      1)
        local backup_name=""
        backup_name="backup_users_$(date +%Y%m%d_%H%M%S).db"
        if ( flock -s 200 || exit 1; cp "${DB_FILE:-/root/usuarios.db}" "/root/$backup_name"; chmod 600 "/root/$backup_name" ) 200>"${DB_LOCK_FILE:-/root/usuarios.db.lock}"; then
          log_info "Backup: /root/$backup_name"
        else log_error "Backup ไม่สำเร็จ"; fi
        pause ;;
      2)
        ls /root/backup_users_*.db 2>/dev/null || log_error "ไม่มีไฟล์ Backup"
        read -r -p "ชื่อไฟล์ (0=ยกเลิก): " restore_file
        [[ "$restore_file" == "0" || -z "$restore_file" ]] && continue
        local restore_name="${restore_file##*/}"
        [[ -f "/root/$restore_name" ]] || { log_error "ไม่พบไฟล์"; pause; continue; }
        read -r -p "YES เพื่อยืนยัน: " confirm_restore
        [[ "$confirm_restore" != "YES" ]] && continue
        if ( flock -x 200 || exit 1; cp "/root/$restore_name" "${DB_FILE:-/root/usuarios.db}"; chmod 600 "${DB_FILE:-/root/usuarios.db}" ) 200>"${DB_LOCK_FILE:-/root/usuarios.db.lock}"; then
          db_migrate_schema_if_needed || true
          log_info "Restore สำเร็จ!"
        else log_error "Restore ไม่สำเร็จ"; fi
        pause ;;
      0) return ;;
      *) log_error "เลือกไม่ถูกต้อง"; sleep 1 ;;
    esac
  done
}
