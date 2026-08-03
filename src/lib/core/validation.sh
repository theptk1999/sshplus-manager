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
  [[ "${1:-}" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] && [[ "${1:-}" != "root" ]]
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

backup_file() {
  local file="${1:-}"
  [[ -f "$file" ]] || return 1
  local stamp
  stamp="$(date +%Y%m%d_%H%M%S)"
  cp -a "$file" "${file}.bak.${stamp}" 2>/dev/null || true
  echo "${file}.bak.${stamp}"
}
