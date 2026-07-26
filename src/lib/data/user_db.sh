# ==================================================
# Data: User DB Layer
# Why: จัดการ DB แบบ atomic + lock
# ==================================================

ensure_db() {
  local db="${DB_FILE:-/root/usuarios.db}"
  [[ -f "$db" ]] || touch "$db"
  chmod 600 "$db" 2>/dev/null || true
}

db_migrate_schema_if_needed() {
  local db="${DB_FILE:-/root/usuarios.db}"
  [[ -f "$db" ]] || return 0
  local temp_file
  temp_file="$(mktemp "${db}.migrate.XXXXXX")" || return 1
  if ! ( flock -x 200 || exit 1
    while IFS=: read -r f1 f2 f3 f4 extra || [[ -n "${f1:-}" ]]; do
      [[ -z "${f1:-}" && -z "${f2:-}" && -z "${f3:-}" && -z "${f4:-}" ]] && continue
      [[ -n "${extra:-}" ]] && continue
      if [[ -n "${f4:-}" ]]; then printf '%s:%s:%s\n' "$f1" "$f3" "$f4" >> "$temp_file"; continue; fi
      if [[ -n "${f3:-}" ]]; then printf '%s:%s:%s\n' "$f1" "$f2" "$f3" >> "$temp_file"; continue; fi
    done < "$db"
    chmod 600 "$temp_file"
    mv "$temp_file" "$db"
  ) 200>"${DB_LOCK_FILE:-${db}.lock}"; then rm -f "$temp_file"; return 1; fi
}

db_write_user_record() {
  local username="${1:-}" limit="${2:-1}" expire_epoch="${3:-0}"
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  [[ "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || return 1
  [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
  [[ "$expire_epoch" =~ ^[0-9]+$ ]] || expire_epoch=0
  local temp_file
  temp_file="$(mktemp "${db}.write.XXXXXX")" || return 1
  if ! ( flock -x 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 != u' "$db" > "$temp_file"
    printf '%s:%s:%s\n' "$username" "$limit" "$expire_epoch" >> "$temp_file"
    chmod 600 "$temp_file"; mv "$temp_file" "$db"
  ) 200>"$lock"; then rm -f "$temp_file"; return 1; fi
}

db_delete_user_record() {
  local username="${1:-}"
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  [[ "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || return 1
  local temp_file
  temp_file="$(mktemp "${db}.delete.XXXXXX")" || return 1
  if ! ( flock -x 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 != u' "$db" > "$temp_file"
    chmod 600 "$temp_file"; mv "$temp_file" "$db"
  ) 200>"$lock"; then rm -f "$temp_file"; return 1; fi
}

db_get_user_record() {
  local username="${1:-}"
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  [[ "$username" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || return 1
  ( flock -s 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 == u' "$db" 2>/dev/null | head -n1
  ) 200>"$lock"
}

db_get_field() {
  local username="${1:-}" field="${2:-2}" line
  line="$(db_get_user_record "$username")"
  [[ -z "$line" ]] && return 0
  echo "$line" | cut -d: -f"$field"
}

db_list_users() {
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  ( flock -s 200 || exit 1; [[ -f "$db" ]] && cat "$db" ) 200>"$lock"
}

db_remove_expired() {
  local db="${DB_FILE:-/root/usuarios.db}" lock="${DB_LOCK_FILE:-${db}.lock}"
  local current_time count=0 temp_db
  current_time="$(date +%s)"
  [[ "${EUID:-$(id -u)}" -ne 0 ]] && { log_warn "db_remove_expired requires root"; return 1; }
  temp_db="$(mktemp "${db}.expire.XXXXXX")" || return 1
  exec 200>"$lock"
  if ! flock -x 200; then rm -f "$temp_db"; exec 200>&-; return 1; fi
  if [[ -f "$db" ]]; then
    while IFS=: read -r user lim expire_epoch || [[ -n "${user:-}" ]]; do
      [[ -z "${user:-}" && -z "${lim:-}" && -z "${expire_epoch:-}" ]] && continue
      if [[ "$user" == "root" ]]; then printf '%s:%s:%s\n' "$user" "$lim" "$expire_epoch" >> "$temp_db"; continue; fi
      if [[ "$expire_epoch" =~ ^[0-9]+$ ]] && [[ "$expire_epoch" -gt 0 ]] && [[ "$current_time" -ge "$expire_epoch" ]]; then
        log_info "ลบ user หมดอายุ: $user"
        userdel --force "$user" >/dev/null 2>&1 || true
        count=$((count + 1))
      else printf '%s:%s:%s\n' "$user" "$lim" "$expire_epoch" >> "$temp_db"; fi
    done < "$db"
    chmod 600 "$temp_db"; mv "$temp_db" "$db"
  else rm -f "$temp_db"; fi
  flock -u 200; exec 200>&-
  [[ "$count" -eq 0 ]] && log_info "ไม่มีบัญชีหมดอายุ" || log_info "ลบไป $count บัญชี"
}
