# ==================================================
# Core: Validation Helpers
# Why: ตรวจสอบ input พื้นฐานก่อนทำงานจริง
# ==================================================

is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

is_port() {
  is_uint "${1:-}" && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

is_username() {
  local username="${1:-}"
  [[ "$username" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_-]{0,31}$ ]] &&
    [[ "$username" != "root" ]]
}

get_uid_min() {
  local uid_min=""

  if [[ -r /etc/login.defs ]]; then
    uid_min="$(
      awk '
        /^[[:space:]]*#/ { next }
        $1 == "UID_MIN" && $2 ~ /^[0-9]+$/ {
          print $2
          exit
        }
      ' /etc/login.defs 2>/dev/null
    )"
  fi

  [[ "$uid_min" =~ ^[0-9]+$ ]] || uid_min=1000
  printf '%s\n' "$uid_min"
}

is_safe_deletable_local_user() {
  local username="${1:-}"
  local uid=""
  local uid_min=""

  is_username "$username" || return 1

  id "$username" >/dev/null 2>&1 || return 1

  uid="$(id -u "$username" 2>/dev/null)" || return 1
  [[ "$uid" =~ ^[0-9]+$ ]] || return 1

  uid_min="$(get_uid_min)"
  [[ "$uid_min" =~ ^[0-9]+$ ]] || uid_min=1000

  (( uid >= uid_min )) || return 1
  (( uid != 0 )) || return 1
  (( uid != 65534 )) || return 1

  return 0
}

safe_userdel_local() {
  local username="${1:-}"

  is_safe_deletable_local_user "$username" || return 1
  userdel --force -- "$username"
}

is_date() {
  date -d "${1:-}" >/dev/null 2>&1
}

prompt_password() {
  local prompt="$1"
  local result_var="$2"
  local __prompt_password_value=""
  if [[ ! "$result_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    return 1
  fi
  if [[ ! -t 0 ]]; then
    return 1
  fi
  if ! IFS= read -r -s -p "$prompt" __prompt_password_value; then
    echo
    return 1
  fi
  echo
  printf -v "$result_var" '%s' "$__prompt_password_value"
}

confirm_yes() {
  local prompt="${1:-Confirm? (YES/NO): }"
  local answer=""
  if [[ ! -t 0 ]]; then
    return 1
  fi
  read -r -p "$prompt" answer
  [[ "$answer" == "YES" ]]
}

get_ssh_port() {
  local cfg="/etc/ssh/sshd_config"
  local port="22"
  if [[ -f "$cfg" ]]; then
    port="$(awk '/^Port/ {print $2; exit}' "$cfg" 2>/dev/null || true)"
  fi
  if is_port "$port"; then
    echo "$port"
  else
    echo "22"
  fi
}

is_port_in_use() {
  local port="${1:-}"
  is_port "$port" || return 1
  if command -v ss >/dev/null 2>&1; then
    ss -tuln 2>/dev/null | grep -q ":${port} "
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tuln 2>/dev/null | grep -q ":${port} "
  else
    return 1
  fi
}

is_tcp_port_listening() {
  local port="${1:-}"

  is_port "$port" || return 1

  if command -v ss >/dev/null 2>&1; then
    ss -H -ltn 2>/dev/null |
      awk -v port="$port" '
        {
          address=$4
          sub(/^.*:/, "", address)

          if (address == port) {
            found=1
            exit
          }
        }

        END {
          exit(found ? 0 : 1)
        }
      '
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null |
      awk -v port="$port" '
        NR > 2 {
          address=$4
          sub(/^.*:/, "", address)

          if (address == port) {
            found=1
            exit
          }
        }

        END {
          exit(found ? 0 : 1)
        }
      '
    return $?
  fi

  return 1
}

backup_file() {
  local file="${1:-}"
  local stamp=""
  local backup=""

  [[ -f "$file" ]] || return 1

  stamp="$(date +%Y%m%d_%H%M%S)" || return 1

  backup="${file}.bak.${stamp}.$$.${RANDOM}"

  cp -a -- "$file" "$backup" 2>/dev/null ||
    return 1

  [[ -e "$backup" || -L "$backup" ]] ||
    return 1

  printf '%s\n' "$backup"
}
