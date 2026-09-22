# ==================================================
# Core: Runtime Script Refresh
# Why:
#   Generated runtime scripts can outlive the SSHPlus binary/source.
#   Refresh installed components from the newly installed binary itself
#   without enabling components that were previously disabled.
# ==================================================

_sshplus_runtime_component_present() {
  local service_name="${1:-}"
  local script_path="${2:-}"
  local extra_path="${3:-}"

  [[ -n "$service_name" && -n "$script_path" ]] || return 1

  [[ -f "$script_path" ||
     -f "/etc/systemd/system/${service_name}.service" ||
     -x "/etc/init.d/${service_name}" ||
     ( -n "$extra_path" && -f "$extra_path" ) ]]
}

_sshplus_extract_embedded_block() {
  local source_file="${1:-}"
  local tag="${2:-}"
  local output_file="${3:-}"

  [[ -r "$source_file" &&
     -n "$tag" &&
     -n "$output_file" ]] || return 1

  awk -v tag="$tag" '
    BEGIN {
      quote = sprintf("%c", 39)
      needle = "cat <<" quote tag quote
    }

    !capture && index($0, needle) {
      capture = 1
      next
    }

    capture && $0 == tag {
      ended = 1
      exit
    }

    capture {
      print
    }

    END {
      if (!capture || !ended) {
        exit 1
      }
    }
  ' "$source_file" > "$output_file"
}

_sshplus_python_compile() {
  local script="${1:-}"

  [[ -r "$script" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$script" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

compile(
    path.read_text(encoding="utf-8"),
    str(path),
    "exec",
)
PY
}

_sshplus_restore_runtime_file() {
  local target="${1:-}"
  local backup="${2:-}"
  local had_original="${3:-0}"

  [[ -n "$target" ]] || return 1

  if [[ "$had_original" -eq 1 && -f "$backup" ]]; then
    cp -p -- "$backup" "$target"
  else
    rm -f -- "$target"
  fi
}

refresh_runtime_scripts() {
  require_root

  local source_file="${SCRIPT_PATH:-$0}"
  local temp_dir=""

  local refresh_limiter=0
  local refresh_bot=0
  local refresh_ws=0

  local limiter_active=0
  local bot_active=0
  local ws_active=0

  local limiter_had=0
  local bot_had=0
  local ws_had=0

  local limiter_candidate=""
  local bot_candidate=""
  local ws_candidate=""

  local limiter_backup="${LIMIT_SCRIPT}.sshplus-prev"
  local bot_backup="${BOT_SCRIPT}.sshplus-prev"
  local ws_backup="${WS_SCRIPT}.sshplus-prev"

  local restart_failed=0

  [[ -r "$source_file" ]] || {
    log_error "ไม่สามารถอ่าน SSHPlus binary สำหรับ runtime refresh"
    return 1
  }

  if _sshplus_runtime_component_present \
       "sshplus-limiter" \
       "$LIMIT_SCRIPT"; then
    refresh_limiter=1
  fi

  if _sshplus_runtime_component_present \
       "sshplus-bot" \
       "$BOT_SCRIPT" \
       "$BOT_ENV_FILE"; then
    refresh_bot=1
  fi

  if _sshplus_runtime_component_present \
       "sshplus-ws" \
       "$WS_SCRIPT"; then
    refresh_ws=1
  fi

  if (( refresh_limiter == 0 &&
        refresh_bot == 0 &&
        refresh_ws == 0 )); then
    log_info "ไม่มี generated runtime component ที่ต้อง refresh"
    return 0
  fi

  svc_is_active sshplus-limiter &&
    limiter_active=1 || true

  svc_is_active sshplus-bot &&
    bot_active=1 || true

  svc_is_active sshplus-ws &&
    ws_active=1 || true

  temp_dir="$(
    mktemp -d \
      "${TMP_BASE:-/tmp}/sshplus-runtime-refresh.XXXXXX"
  )" || {
    log_error "สร้าง runtime refresh staging ไม่สำเร็จ"
    return 1
  }

  limiter_candidate="${temp_dir}/limit_auto.sh"
  bot_candidate="${temp_dir}/bot_auto.py"
  ws_candidate="${temp_dir}/proxy_ws.py"

  if (( refresh_limiter == 1 )); then
    if ! _sshplus_extract_embedded_block \
         "$source_file" \
         "LIMEOF" \
         "$limiter_candidate"; then
      rm -rf -- "$temp_dir"
      log_error "Extract limiter runtime ไม่สำเร็จ"
      return 1
    fi

    if ! bash -n "$limiter_candidate"; then
      rm -rf -- "$temp_dir"
      log_error "Limiter runtime syntax ไม่ผ่าน"
      return 1
    fi
  fi

  if (( refresh_bot == 1 )); then
    if ! _sshplus_extract_embedded_block \
         "$source_file" \
         "BOTPY" \
         "$bot_candidate"; then
      rm -rf -- "$temp_dir"
      log_error "Extract Telegram bot runtime ไม่สำเร็จ"
      return 1
    fi

    if ! _sshplus_python_compile "$bot_candidate"; then
      rm -rf -- "$temp_dir"
      log_error "Telegram bot runtime syntax ไม่ผ่าน"
      return 1
    fi
  fi

  if (( refresh_ws == 1 )); then
    if ! _sshplus_extract_embedded_block \
         "$source_file" \
         "WSEOF" \
         "$ws_candidate"; then
      rm -rf -- "$temp_dir"
      log_error "Extract WebSocket runtime ไม่สำเร็จ"
      return 1
    fi

    if ! _sshplus_python_compile "$ws_candidate"; then
      rm -rf -- "$temp_dir"
      log_error "WebSocket runtime syntax ไม่ผ่าน"
      return 1
    fi
  fi

  #
  # Back up current runtime files before replacing anything.
  #
  if (( refresh_limiter == 1 )); then
    if [[ -f "$LIMIT_SCRIPT" ]]; then
      cp -p -- "$LIMIT_SCRIPT" "$limiter_backup" || {
        rm -rf -- "$temp_dir"
        log_error "Backup limiter runtime ไม่สำเร็จ"
        return 1
      }
      limiter_had=1
    else
      rm -f -- "$limiter_backup"
    fi
  fi

  if (( refresh_bot == 1 )); then
    if [[ -f "$BOT_SCRIPT" ]]; then
      cp -p -- "$BOT_SCRIPT" "$bot_backup" || {
        rm -rf -- "$temp_dir"
        log_error "Backup bot runtime ไม่สำเร็จ"
        return 1
      }
      bot_had=1
    else
      rm -f -- "$bot_backup"
    fi
  fi

  if (( refresh_ws == 1 )); then
    if [[ -f "$WS_SCRIPT" ]]; then
      cp -p -- "$WS_SCRIPT" "$ws_backup" || {
        rm -rf -- "$temp_dir"
        log_error "Backup WebSocket runtime ไม่สำเร็จ"
        return 1
      }
      ws_had=1
    else
      rm -f -- "$ws_backup"
    fi
  fi

  #
  # Install validated runtime scripts atomically.
  #
  if (( refresh_limiter == 1 )); then
    if ! install \
         -m 700 \
         "$limiter_candidate" \
         "${LIMIT_SCRIPT}.new.$$" ||
       ! mv -f \
         "${LIMIT_SCRIPT}.new.$$" \
         "$LIMIT_SCRIPT"; then

      rm -f -- "${LIMIT_SCRIPT}.new.$$"

      _sshplus_restore_runtime_file \
        "$LIMIT_SCRIPT" \
        "$limiter_backup" \
        "$limiter_had" || true

      rm -rf -- "$temp_dir"
      log_error "ติดตั้ง limiter runtime ไม่สำเร็จ"
      return 1
    fi
  fi

  if (( refresh_bot == 1 )); then
    if ! install \
         -m 700 \
         "$bot_candidate" \
         "${BOT_SCRIPT}.new.$$" ||
       ! mv -f \
         "${BOT_SCRIPT}.new.$$" \
         "$BOT_SCRIPT"; then

      rm -f -- "${BOT_SCRIPT}.new.$$"

      _sshplus_restore_runtime_file \
        "$LIMIT_SCRIPT" \
        "$limiter_backup" \
        "$limiter_had" || true

      _sshplus_restore_runtime_file \
        "$BOT_SCRIPT" \
        "$bot_backup" \
        "$bot_had" || true

      rm -rf -- "$temp_dir"
      log_error "ติดตั้ง bot runtime ไม่สำเร็จ"
      return 1
    fi
  fi

  if (( refresh_ws == 1 )); then
    if ! install \
         -m 700 \
         "$ws_candidate" \
         "${WS_SCRIPT}.new.$$" ||
       ! mv -f \
         "${WS_SCRIPT}.new.$$" \
         "$WS_SCRIPT"; then

      rm -f -- "${WS_SCRIPT}.new.$$"

      _sshplus_restore_runtime_file \
        "$LIMIT_SCRIPT" \
        "$limiter_backup" \
        "$limiter_had" || true

      _sshplus_restore_runtime_file \
        "$BOT_SCRIPT" \
        "$bot_backup" \
        "$bot_had" || true

      _sshplus_restore_runtime_file \
        "$WS_SCRIPT" \
        "$ws_backup" \
        "$ws_had" || true

      rm -rf -- "$temp_dir"
      log_error "ติดตั้ง WebSocket runtime ไม่สำเร็จ"
      return 1
    fi
  fi

  #
  # Restart only services that were already active.
  # Never enable or start a previously disabled service.
  #
  if (( limiter_active == 1 )); then
    svc_restart sshplus-limiter ||
      restart_failed=1
  fi

  if (( bot_active == 1 )); then
    svc_restart sshplus-bot ||
      restart_failed=1
  fi

  if (( ws_active == 1 )); then
    svc_restart sshplus-ws ||
      restart_failed=1
  fi

  if (( restart_failed == 1 )); then
    log_error "Runtime service restart ล้มเหลว กำลัง rollback"

    if (( refresh_limiter == 1 )); then
      _sshplus_restore_runtime_file \
        "$LIMIT_SCRIPT" \
        "$limiter_backup" \
        "$limiter_had" || true
    fi

    if (( refresh_bot == 1 )); then
      _sshplus_restore_runtime_file \
        "$BOT_SCRIPT" \
        "$bot_backup" \
        "$bot_had" || true
    fi

    if (( refresh_ws == 1 )); then
      _sshplus_restore_runtime_file \
        "$WS_SCRIPT" \
        "$ws_backup" \
        "$ws_had" || true
    fi

    (( limiter_active == 1 )) &&
      svc_restart sshplus-limiter || true

    (( bot_active == 1 )) &&
      svc_restart sshplus-bot || true

    (( ws_active == 1 )) &&
      svc_restart sshplus-ws || true

    rm -rf -- "$temp_dir"
    return 1
  fi

  rm -rf -- "$temp_dir"

  (( refresh_limiter == 1 )) &&
    log_info "Refreshed: $LIMIT_SCRIPT"

  (( refresh_bot == 1 )) &&
    log_info "Refreshed: $BOT_SCRIPT"

  (( refresh_ws == 1 )) &&
    log_info "Refreshed: $WS_SCRIPT"

  log_info "Runtime refresh สำเร็จ"
  return 0
}
