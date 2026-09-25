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

db_backup_name_is_safe() {
  local name="${1:-}"

  [[ "$name" =~ ^backup_users_[0-9]{8}_[0-9]{6}(_[A-Za-z0-9_-]+)?\.db$ ]]
}

db_validate_file() {
  local file="${1:-}"
  local line=""
  local username=""
  local limit=""
  local expire_epoch=""
  local line_no=0

  [[ -f "$file" ]] || return 1
  [[ ! -L "$file" ]] || return 1

  declare -A seen=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))

    if [[ -z "$line" ]]; then
      printf '[ERROR] DB line %d is empty\n' \
        "$line_no" >&2
      return 1
    fi

    # Exactly three fields are required:
    # username:limit:expire_epoch
    if [[ "$line" != *:*:* ||
          "$line" == *:*:*:* ]]; then
      printf '[ERROR] DB line %d has invalid field count\n' \
        "$line_no" >&2
      return 1
    fi

    IFS=: read -r \
      username \
      limit \
      expire_epoch <<< "$line"

    if ! is_username "$username"; then
      printf '[ERROR] DB line %d has unsafe username\n' \
        "$line_no" >&2
      return 1
    fi

    if [[ ! "$limit" =~ ^[1-9][0-9]*$ ||
          "${#limit}" -gt 9 ]]; then
      printf '[ERROR] DB line %d has invalid limit\n' \
        "$line_no" >&2
      return 1
    fi

    if [[ ! "$expire_epoch" =~ ^[1-9][0-9]*$ ||
          "${#expire_epoch}" -gt 18 ||
          "$expire_epoch" -gt 253402300799 ]]; then
      printf '[ERROR] DB line %d has invalid expiry\n' \
        "$line_no" >&2
      return 1
    fi

    if [[ -n "${seen[$username]+x}" ]]; then
      printf '[ERROR] DB line %d duplicates user %s\n' \
        "$line_no" "$username" >&2
      return 1
    fi

    seen["$username"]=1

    #
    # If this name already belongs to a local Linux account,
    # reject system/protected accounts.
    #
    if id "$username" >/dev/null 2>&1; then
      if ! is_safe_deletable_local_user "$username"; then
        printf '[ERROR] DB line %d references protected account %s\n' \
          "$line_no" "$username" >&2
        return 1
      fi

    fi
  done < "$file"

  return 0
}

db_validate_backup_file() {
  local file="${1:-}"
  local name=""
  local metadata=""
  local backup_dir="${SSHPLUS_BACKUP_DIR:-/root}"
  local backup_uid="${SSHPLUS_BACKUP_UID:-0}"
  local backup_gid="${SSHPLUS_BACKUP_GID:-0}"

  backup_dir="${backup_dir%/}"
  [[ -n "$backup_dir" ]] || backup_dir="/"

  name="${file##*/}"

  [[ "$file" == "$backup_dir/$name" ]] || return 1
  db_backup_name_is_safe "$name" || return 1

  [[ -d "$backup_dir" ]] || return 1
  [[ ! -L "$backup_dir" ]] || return 1
  [[ -f "$file" ]] || return 1
  [[ ! -L "$file" ]] || return 1

  metadata="$(
    stat -c '%u:%g:%a' -- "$file" 2>/dev/null
  )" || return 1

  [[ "$metadata" == "${backup_uid}:${backup_gid}:600" ]] ||
    return 1

  db_validate_file "$file"
}

DB_RESTORE_ADOPTION_COUNT=0

db_report_restore_adoptions() {
  local file="${1:-}"
  local username=""
  local limit=""
  local expire_epoch=""
  local count=0

  [[ -f "$file" ]] || return 1

  while IFS=: read -r \
    username \
    limit \
    expire_epoch ||
    [[ -n "${username:-}" ]]; do

    [[ -z "${username:-}" ]] && continue

    if id "$username" >/dev/null 2>&1 &&
       is_safe_deletable_local_user "$username" &&
       ! db_user_is_managed "$username"; then

      log_warn \
        "Backup จะนำ Linux user ที่ยังไม่ได้ managed กลับเข้า DB: $username"

      count=$((count + 1))
    fi
  done < "$file"

  DB_RESTORE_ADOPTION_COUNT="$count"

  if [[ "$count" -gt 0 ]]; then
    log_warn \
      "พบ $count Linux user ที่จะถูกนำกลับเข้า SSHPlus DB"
  fi

  return 0
}

DB_LAST_BACKUP=""
DB_RESTORE_SAFETY_BACKUP=""

db_create_backup() {
  local db="${DB_FILE:-/root/usuarios.db}"
  local lock="${DB_LOCK_FILE:-${db}.lock}"
  local backup_dir="${SSHPLUS_BACKUP_DIR:-/root}"
  local backup_uid="${SSHPLUS_BACKUP_UID:-0}"
  local backup_gid="${SSHPLUS_BACKUP_GID:-0}"
  local stamp=""
  local final=""
  local temp=""

  DB_LAST_BACKUP=""

  backup_dir="${backup_dir%/}"
  [[ -n "$backup_dir" ]] || backup_dir="/"

  [[ -d "$backup_dir" ]] || return 1
  [[ ! -L "$backup_dir" ]] || return 1

  ensure_db || return 1

  stamp="$(date +%Y%m%d_%H%M%S)" || return 1

  final="${backup_dir}/backup_users_${stamp}_$$_${RANDOM}.db"
  temp="$(
    mktemp "${backup_dir}/.backup_users_${stamp}.XXXXXX"
  )" || return 1

  exec 200>"$lock"

  if ! flock -s 200; then
    rm -f -- "$temp"
    exec 200>&-
    return 1
  fi

  if ! cp -- "$db" "$temp"; then
    rm -f -- "$temp"
    flock -u 200
    exec 200>&-
    return 1
  fi

  flock -u 200
  exec 200>&-

  if ! chmod 600 "$temp" ||
     ! chown "${backup_uid}:${backup_gid}" "$temp"; then
    rm -f -- "$temp"
    return 1
  fi

  if ! db_validate_file "$temp"; then
    rm -f -- "$temp"
    return 1
  fi

  if ! mv -- "$temp" "$final"; then
    rm -f -- "$temp"
    return 1
  fi

  DB_LAST_BACKUP="$final"
  return 0
}

db_restore_backup() {
  local source="${1:-}"
  local adopt_approval="${2:-}"
  local db="${DB_FILE:-/root/usuarios.db}"
  local lock="${DB_LOCK_FILE:-${db}.lock}"
  local backup_dir="${SSHPLUS_BACKUP_DIR:-/root}"
  local backup_uid="${SSHPLUS_BACKUP_UID:-0}"
  local backup_gid="${SSHPLUS_BACKUP_GID:-0}"
  local db_uid="${SSHPLUS_DB_UID:-0}"
  local db_gid="${SSHPLUS_DB_GID:-0}"
  local stamp=""
  local restore_temp=""
  local safety_temp=""
  local safety_final=""

  DB_RESTORE_SAFETY_BACKUP=""

  backup_dir="${backup_dir%/}"
  [[ -n "$backup_dir" ]] || backup_dir="/"

  [[ -d "$backup_dir" ]] || return 1
  [[ ! -L "$backup_dir" ]] || return 1

  db_validate_backup_file "$source" || return 1

  restore_temp="$(
    mktemp "${db}.restore.XXXXXX"
  )" || return 1

  if ! cp -- "$source" "$restore_temp"; then
    rm -f -- "$restore_temp"
    return 1
  fi

  if ! chmod 600 "$restore_temp" ||
     ! chown "${db_uid}:${db_gid}" "$restore_temp"; then
    rm -f -- "$restore_temp"
    return 1
  fi

  #
  # Validate the exact temporary copy that will become the DB.
  # This prevents validation/copy time-of-check differences.
  #
  if ! db_validate_file "$restore_temp"; then
    rm -f -- "$restore_temp"
    return 1
  fi

  #
  # Defense in depth:
  # enforce ADOPT against the exact validated copy that will
  # become the live DB, not against the mutable source path.
  #
  if ! db_report_restore_adoptions "$restore_temp" >/dev/null 2>&1; then
    rm -f -- "$restore_temp"
    return 1
  fi

  if [[ "$DB_RESTORE_ADOPTION_COUNT" -gt 0 &&
        "$adopt_approval" != "ADOPT" ]]; then
    rm -f -- "$restore_temp"
    return 2
  fi

  ensure_db || {
    rm -f -- "$restore_temp"
    return 1
  }

  stamp="$(date +%Y%m%d_%H%M%S)" || {
    rm -f -- "$restore_temp"
    return 1
  }

  safety_final="${backup_dir}/backup_users_${stamp}_pre_restore_$$_${RANDOM}.db"

  safety_temp="$(
    mktemp "${backup_dir}/.backup_users_pre_restore_${stamp}.XXXXXX"
  )" || {
    rm -f -- "$restore_temp"
    return 1
  }

  exec 200>"$lock"

  if ! flock -x 200; then
    rm -f -- "$restore_temp" "$safety_temp"
    exec 200>&-
    return 1
  fi

  #
  # Always preserve the current DB before replacement.
  #
  if ! cp -- "$db" "$safety_temp" ||
     ! chmod 600 "$safety_temp" ||
     ! chown "${backup_uid}:${backup_gid}" "$safety_temp" ||
     ! mv -- "$safety_temp" "$safety_final"; then

    rm -f -- "$restore_temp" "$safety_temp"
    flock -u 200
    exec 200>&-
    return 1
  fi

  #
  # restore_temp lives beside the DB, therefore mv is an
  # atomic replacement on the same filesystem.
  #
  if ! mv -- "$restore_temp" "$db"; then
    rm -f -- "$restore_temp"
    flock -u 200
    exec 200>&-
    return 1
  fi

  flock -u 200
  exec 200>&-

  DB_RESTORE_SAFETY_BACKUP="$safety_final"
  return 0
}

db_report_restore_mismatches() {
  local username=""
  local limit=""
  local expire_epoch=""
  local db_date=""
  local shadow_days=""
  local shadow_epoch=""
  local linux_date=""
  local mismatch_count=0

  while IFS=: read -r \
    username \
    limit \
    expire_epoch ||
    [[ -n "${username:-}" ]]; do

    [[ -z "${username:-}" ]] && continue

    if ! id "$username" >/dev/null 2>&1; then
      log_warn \
        "Restore DB มี $username แต่ไม่พบ Linux user"
      mismatch_count=$((mismatch_count + 1))
      continue
    fi

    db_date="$(
      date -u \
        -d "@$expire_epoch" \
        +%Y-%m-%d 2>/dev/null
    )" || {
      log_warn \
        "อ่าน expiry ใน DB ของ $username ไม่สำเร็จ"
      mismatch_count=$((mismatch_count + 1))
      continue
    }

    shadow_days="$(
      getent shadow "$username" 2>/dev/null |
      awk -F: 'NR == 1 { print $8 }'
    )"

    if [[ -z "$shadow_days" ]]; then
      log_warn \
        "$username: Linux account expiry=never แต่ DB=$db_date"
      mismatch_count=$((mismatch_count + 1))
      continue
    fi

    if [[ ! "$shadow_days" =~ ^[0-9]+$ ]]; then
      log_warn \
        "$username: อ่าน Linux account expiry ไม่สำเร็จ"
      mismatch_count=$((mismatch_count + 1))
      continue
    fi

    shadow_epoch=$((10#$shadow_days * 86400))

    linux_date="$(
      date -u \
        -d "@$shadow_epoch" \
        +%Y-%m-%d 2>/dev/null
    )" || {
      log_warn \
        "$username: แปลง Linux account expiry ไม่สำเร็จ"
      mismatch_count=$((mismatch_count + 1))
      continue
    }

    if [[ "$db_date" != "$linux_date" ]]; then
      log_warn \
        "$username: DB=$db_date Linux=$linux_date"
      mismatch_count=$((mismatch_count + 1))
    fi
  done < <(db_list_users)

  if [[ "$mismatch_count" -eq 0 ]]; then
    log_info \
      "DB และ Linux account expiry ตรงกันทุกบัญชีที่มีอยู่"
  else
    log_warn \
      "พบ $mismatch_count รายการที่ต้องตรวจสอบหลัง Restore"
  fi

  return 0
}

db_write_user_record() {
  local username="${1:-}" limit="${2:-1}" expire_epoch="${3-}"
  local db="${DB_FILE:-/root/usuarios.db}"
  local lock="${DB_LOCK_FILE:-${db}.lock}"
  is_username "$username" || return 1
  [[ "$limit" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "${#limit}" -le 9 ]] || return 1
  [[ "$expire_epoch" =~ ^[0-9]+$ ]] || return 1
  [[ "$expire_epoch" -gt 0 ]] || return 1
  [[ "$expire_epoch" -le 253402300799 ]] || return 1
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
  local db="${DB_FILE:-/root/usuarios.db}"
  local lock="${DB_LOCK_FILE:-${db}.lock}"
  is_username "$username" || return 1
  local temp_file
  temp_file="$(mktemp "${db}.delete.XXXXXX")" || return 1
  if ! ( flock -x 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 != u' "$db" > "$temp_file"
    chmod 600 "$temp_file"; mv "$temp_file" "$db"
  ) 200>"$lock"; then rm -f "$temp_file"; return 1; fi
}

db_get_user_record() {
  local username="${1:-}"
  local db="${DB_FILE:-/root/usuarios.db}"
  local lock="${DB_LOCK_FILE:-${db}.lock}"
  is_username "$username" || return 1
  ( flock -s 200 || exit 1
    [[ -f "$db" ]] && awk -F: -v u="$username" '$1 == u' "$db" 2>/dev/null | head -n1
  ) 200>"$lock"
}

db_user_is_managed() {
  local username="${1:-}"
  local record=""

  is_username "$username" || return 1
  record="$(db_get_user_record "$username")"
  [[ -n "$record" ]]
}

db_delete_managed_user() {
  local username="${1:-}"

  is_username "$username" || return 2
  db_user_is_managed "$username" || return 3

  if id "$username" >/dev/null 2>&1; then
    is_safe_deletable_local_user "$username" || return 4

    if ! safe_userdel_local "$username" >/dev/null 2>&1; then
      return 5
    fi
  fi

  db_delete_user_record "$username" || return 6
  return 0
}

db_get_field() {
  local username="${1:-}" field="${2:-2}" line
  line="$(db_get_user_record "$username")"
  [[ -z "$line" ]] && return 0
  echo "$line" | cut -d: -f"$field"
}

db_list_users() {
  local db="${DB_FILE:-/root/usuarios.db}"
  local lock="${DB_LOCK_FILE:-${db}.lock}"
  ( flock -s 200 || exit 1; [[ -f "$db" ]] && cat "$db" ) 200>"$lock"
}

db_remove_expired() {
  local db="${DB_FILE:-/root/usuarios.db}"
  local lock="${DB_LOCK_FILE:-${db}.lock}"
  local current_time count=0 temp_db
  local user lim expire_epoch

  current_time="$(date +%s)"

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_warn "db_remove_expired requires root"
    return 1
  fi

  temp_db="$(mktemp "${db}.expire.XXXXXX")" || return 1

  exec 200>"$lock"

  if ! flock -x 200; then
    rm -f "$temp_db"
    exec 200>&-
    return 1
  fi

  if [[ ! -f "$db" ]]; then
    rm -f "$temp_db"
    flock -u 200
    exec 200>&-
    return 0
  fi

  while IFS=: read -r user lim expire_epoch ||
        [[ -n "${user:-}" ]]; do

    if [[ -z "${user:-}" &&
          -z "${lim:-}" &&
          -z "${expire_epoch:-}" ]]; then
      continue
    fi

    if ! is_username "$user"; then
      log_warn "ข้าม record ที่ username ไม่ปลอดภัย: $user"
      printf '%s:%s:%s\n'         "$user" "$lim" "$expire_epoch" >> "$temp_db"
      continue
    fi

    if [[ ! "$expire_epoch" =~ ^[0-9]+$ ]] ||
       [[ "$expire_epoch" -le 0 ]] ||
       [[ "$current_time" -lt "$expire_epoch" ]]; then

      printf '%s:%s:%s\n'         "$user" "$lim" "$expire_epoch" >> "$temp_db"
      continue
    fi

    if ! id "$user" >/dev/null 2>&1; then
      log_info "cleanup DB ของ user หมดอายุที่ไม่มีในระบบ: $user"
      count=$((count + 1))
      continue
    fi

    if ! is_safe_deletable_local_user "$user"; then
      log_warn "ปฏิเสธการลบ protected/system account: $user"
      printf '%s:%s:%s\n'         "$user" "$lim" "$expire_epoch" >> "$temp_db"
      continue
    fi

    if safe_userdel_local "$user" >/dev/null 2>&1; then
      log_info "ลบ user หมดอายุ: $user"
      count=$((count + 1))
      continue
    fi

    log_warn "userdel ไม่สำเร็จ จึงเก็บ DB record ไว้: $user"

    printf '%s:%s:%s\n'       "$user" "$lim" "$expire_epoch" >> "$temp_db"

  done < "$db"

  chmod 600 "$temp_db" || {
    rm -f "$temp_db"
    flock -u 200
    exec 200>&-
    return 1
  }

  if ! mv "$temp_db" "$db"; then
    rm -f "$temp_db"
    flock -u 200
    exec 200>&-
    return 1
  fi

  flock -u 200
  exec 200>&-

  if [[ "$count" -eq 0 ]]; then
    log_info "ไม่มีบัญชีหมดอายุ"
  else
    log_info "ลบ/cleanup ไป $count บัญชี"
  fi
}
