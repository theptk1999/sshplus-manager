# ==================================================
# Data: User DB Layer
# Why: จัดการ DB แบบ atomic + lock เพื่อความมั่นคงของข้อมูล
# ==================================================

# Why: กำหนด path DB กลาง และยอมให้ override ผ่าน environment
SSHPLUS_DB_FILE="${SSHPLUS_DB_FILE:-/root/usuarios.db}"
SSHPLUS_DB_LOCK_FILE="${SSHPLUS_DB_LOCK_FILE:-${SSHPLUS_DB_FILE}.lock}"

# Why: สร้าง DB file และกำหนดสิทธิ์ให้ปลอดภัย
ensure_db() {
  local db_dir
  db_dir="$(dirname "$SSHPLUS_DB_FILE")"

  mkdir -p "$db_dir" 2>/dev/null || true

  if [[ ! -f "$SSHPLUS_DB_FILE" ]]; then
    touch "$SSHPLUS_DB_FILE"
  fi

  chmod 600 "$SSHPLUS_DB_FILE" 2>/dev/null || true
}

# Why: migrate จาก schema เก่า username:password:limit:expire
#      ไปเป็น schema ใหม่ username:limit:expire
db_migrate_schema_if_needed() {
  [[ -f "$SSHPLUS_DB_FILE" ]] || return 0

  local temp_file
  temp_file="$(mktemp "${SSHPLUS_DB_FILE}.migrate.XXXXXX")" || return 1

  if ! (
    flock -x 200 || exit 1

    while IFS=: read -r field1 field2 field3 field4 extra || [[ -n "${field1:-}" ]]; do
      if [[ -z "${field1:-}" && -z "${field2:-}" && -z "${field3:-}" && -z "${field4:-}" ]]; then
        continue
      fi

      if [[ -n "${extra:-}" ]]; then
        continue
      fi

      # Why: schema เก่า 4 ช่อง -> username:limit:expire
      if [[ -n "${field4:-}" ]]; then
        printf '%s:%s:%s\n' "$field1" "$field3" "$field4" >> "$temp_file"
        continue
      fi

      # Why: schema ใหม่ 3 ช่อง -> เก็บตามเดิม
      if [[ -n "${field3:-}" ]]; then
        printf '%s:%s:%s\n' "$field1" "$field2" "$field3" >> "$temp_file"
        continue
      fi
    done < "$SSHPLUS_DB_FILE"

    chmod 600 "$temp_file"
    mv "$temp_file" "$SSHPLUS_DB_FILE"
  ) 200>"$SSHPLUS_DB_LOCK_FILE"; then
    rm -f "$temp_file"
    return 1
  fi
}

# Why: เขียน/อัปเดต user record แบบ atomic และป้องกัน race condition
db_write_user_record() {
  local username="${1:-}"
  local limit="${2:-1}"
  local expire_epoch="${3:-0}"
  local temp_file

  # Why: ป้องกัน username ไม่ปลอดภัยตั้งแต่ชั้น DB
  if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
    return 1
  fi

  [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
  [[ "$expire_epoch" =~ ^[0-9]+$ ]] || expire_epoch=0

  temp_file="$(mktemp "${SSHPLUS_DB_FILE}.write.XXXXXX")" || return 1

  if ! (
    flock -x 200 || exit 1

    if [[ -f "$SSHPLUS_DB_FILE" ]]; then
      awk -F: -v u="$username" '$1 != u' "$SSHPLUS_DB_FILE" > "$temp_file" || exit 1
    fi

    printf '%s:%s:%s\n' "$username" "$limit" "$expire_epoch" >> "$temp_file" || exit 1

    chmod 600 "$temp_file"
    mv "$temp_file" "$SSHPLUS_DB_FILE"
  ) 200>"$SSHPLUS_DB_LOCK_FILE"; then
    rm -f "$temp_file"
    return 1
  fi
}

# Why: ลบ user record แบบ atomic และป้องกัน race condition
db_delete_user_record() {
  local username="${1:-}"
  local temp_file

  if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
    return 1
  fi

  temp_file="$(mktemp "${SSHPLUS_DB_FILE}.delete.XXXXXX")" || return 1

  if ! (
    flock -x 200 || exit 1

    if [[ -f "$SSHPLUS_DB_FILE" ]]; then
      awk -F: -v u="$username" '$1 != u' "$SSHPLUS_DB_FILE" > "$temp_file" || exit 1
    fi

    chmod 600 "$temp_file"
    mv "$temp_file" "$SSHPLUS_DB_FILE"
  ) 200>"$SSHPLUS_DB_LOCK_FILE"; then
    rm -f "$temp_file"
    return 1
  fi
}

# Why: อ่าน record ของ user เดียวแบบ shared lock
db_get_user_record() {
  local username="${1:-}"

  if [[ ! "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
    return 1
  fi

  (
    flock -s 200 || exit 1

    if [[ -f "$SSHPLUS_DB_FILE" ]]; then
      awk -F: -v u="$username" '$1 == u' "$SSHPLUS_DB_FILE" 2>/dev/null | head -n1 || true
    fi
  ) 200>"$SSHPLUS_DB_LOCK_FILE"
}

# Why: ดึง field ที่ต้องการจาก record username:limit:expire_epoch
db_get_field() {
  local username="${1:-}"
  local field="${2:-2}"
  local line

  line="$(db_get_user_record "$username")"
  [[ -z "$line" ]] && return 0

  echo "$line" | cut -d: -f"$field"
}

# Why: อ่าน DB ทั้งหมดแบบ shared lock สำหรับแสดงผล
db_list_users() {
  (
    flock -s 200 || exit 1

    if [[ -f "$SSHPLUS_DB_FILE" ]]; then
      cat "$SSHPLUS_DB_FILE"
    fi
  ) 200>"$SSHPLUS_DB_LOCK_FILE"
}

# Why: ลบบัญชีที่หมดอายุออกจาก OS และ DB อย่างปลอดภัย
db_remove_expired() {
  local current_time
  local count=0
  local temp_file

  current_time="$(date +%s)"

  # Why: ถ้าไม่ใช่ root ไม่ควรแตะ OS user
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if declare -F log_warn >/dev/null 2>&1; then
      log_warn "db_remove_expired requires root privileges."
    fi
    return 1
  fi

  temp_file="$(mktemp "${SSHPLUS_DB_FILE}.expire.XXXXXX")" || return 1

  exec 200>"$SSHPLUS_DB_LOCK_FILE"

  if ! flock -x 200; then
    rm -f "$temp_file"
    exec 200>&-
    return 1
  fi

  if [[ -f "$SSHPLUS_DB_FILE" ]]; then
    while IFS=: read -r user lim expire_epoch || [[ -n "${user:-}" ]]; do
      if [[ -z "${user:-}" && -z "${lim:-}" && -z "${expire_epoch:-}" ]]; then
        continue
      fi

      if [[ "$user" == "root" ]]; then
        printf '%s:%s:%s\n' "$user" "$lim" "$expire_epoch" >> "$temp_file"
        continue
      fi

      # Why: expire_epoch = 0 ให้ถือว่าไม่มีกำหนดลบอัตโนมัติ ป้องกันลบพลาด
      if [[ "$expire_epoch" =~ ^[0-9]+$ ]] && [[ "$expire_epoch" -gt 0 ]] && [[ "$current_time" -ge "$expire_epoch" ]]; then
        if declare -F log_info >/dev/null 2>&1; then
          log_info "Removing expired user: $user"
        fi

        userdel --force "$user" >/dev/null 2>&1 || true
        count=$((count + 1))
      else
        printf '%s:%s:%s\n' "$user" "$lim" "$expire_epoch" >> "$temp_file"
      fi
    done < "$SSHPLUS_DB_FILE"

    chmod 600 "$temp_file"
    mv "$temp_file" "$SSHPLUS_DB_FILE"
  else
    rm -f "$temp_file"
  fi

  flock -u 200
  exec 200>&-

  if declare -F log_info >/dev/null 2>&1; then
    if [[ "$count" -eq 0 ]]; then
      log_info "No expired users found."
    else
      log_info "Removed $count expired user(s)."
    fi
  fi
}
