# ==================================================
# Feature: User Management
# Why: เก็บฟังก์ชันเกี่ยวกับผู้ใช้ SSH
#      ตอนนี้เป็น stub เพื่อเตรียมย้ายโค้ดจริงจาก sshplusthai.sh
# ==================================================

# Why: stub สำหรับสร้างผู้ใช้ใหม่
function_create_user() {
  log_warn "TODO: move function_create_user from sshplusthai.sh"
  pause
}

# Why: stub สำหรับสร้างไอดีทดสอบ
function_create_test() {
  log_warn "TODO: move function_create_test from sshplusthai.sh"
  pause
}

# Why: stub สำหรับลบผู้ใช้
function_delete_user() {
  log_warn "TODO: move function_delete_user from sshplusthai.sh"
  pause
}

# Why: stub สำหรับต่ออายุผู้ใช้
function_renew_user() {
  log_warn "TODO: move function_renew_user from sshplusthai.sh"
  pause
}

# Why: stub สำหรับแสดงผู้ใช้กำลังออนไลน์
function_users_online() {
  log_warn "TODO: move function_users_online from sshplusthai.sh"
  pause
}

# Why: stub สำหรับแก้วันหมดอายุ
function_change_expiry() {
  log_warn "TODO: move function_change_expiry from sshplusthai.sh"
  pause
}

# Why: stub สำหรับแก้ limit
function_change_limit() {
  log_warn "TODO: move function_change_limit from sshplusthai.sh"
  pause
}

# Why: stub สำหรับเปลี่ยนรหัสผ่าน
function_change_pass() {
  log_warn "TODO: move function_change_pass from sshplusthai.sh"
  pause
}

# Why: เรียก db layer เพื่อล้างผู้ใช้หมดอายุ
function_remove_expired() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_warn "This function requires root privileges."
    pause
    return 0
  fi

  db_remove_expired
  pause
}

# Why: แสดงรายชื่อผู้ใช้จาก DB แบบพื้นฐาน
function_list_users() {
  clear_screen

  local db_file="${SSHPLUS_DB_FILE:-/root/usuarios.db}"

  if [[ ! -f "$db_file" ]]; then
    log_warn "DB file not found: $db_file"
    pause
    return 0
  fi

  printf '%-15s | %-10s | %-15s\n' "User" "Limit" "Expire"
  printf '%s\n' "------------------------------------------------"

  local user
  local limit
  local expire_epoch
  local expire_date

  while IFS=: read -r user limit expire_epoch || [[ -n "${user:-}" ]]; do
    if [[ -z "${user:-}" && -z "${limit:-}" && -z "${expire_epoch:-}" ]]; then
      continue
    fi

    expire_date="Never"

    if [[ "$expire_epoch" =~ ^[0-9]+$ ]] && [[ "$expire_epoch" -gt 0 ]]; then
      expire_date="$(date -d "@$expire_epoch" +%d/%m/%Y 2>/dev/null || echo "$expire_epoch")"
    fi

    printf '%-15s | %-10s | %-15s\n' "$user" "$limit" "$expire_date"
  done < <(db_list_users)

  pause
}

# Why: stub สำหรับ backup/restore DB
function_backup_users() {
  log_warn "TODO: move function_backup_users from sshplusthai.sh"
  pause
}
