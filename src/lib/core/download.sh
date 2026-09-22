# ==================================================
# Core: Verified Download Helpers
# Why: ดาวน์โหลดไฟล์ภายนอกแบบ fail-closed
# ==================================================

is_sha256() {
  [[ "${1:-}" =~ ^[a-fA-F0-9]{64}$ ]]
}

download_to_temp_file() {
  local url="${1:-}"
  local temp_file="${2:-}"

  [[ -n "$url" && -n "$temp_file" ]] || return 1

  case "$url" in
    https://*)
      ;;
    *)
      log_error "ปฏิเสธ URL ที่ไม่ใช่ HTTPS: $url"
      return 1
      ;;
  esac

  rm -f -- "$temp_file"

  if command -v curl >/dev/null 2>&1; then
    curl \
      --proto '=https' \
      --proto-redir '=https' \
      --fail \
      --location \
      --silent \
      --show-error \
      --retry 3 \
      --retry-delay 1 \
      --connect-timeout 10 \
      --max-time 300 \
      --output "$temp_file" \
      "$url" || {
        rm -f -- "$temp_file"
        return 1
      }

  elif command -v wget >/dev/null 2>&1; then

    if ! wget --help 2>&1 | grep -q -- '--https-only'; then
      log_error "wget รุ่นนี้ไม่รองรับ --https-only"
      log_error "ติดตั้ง curl เพื่อดาวน์โหลดอย่างปลอดภัย"
      return 1
    fi

    wget \
      --https-only \
      --quiet \
      --output-document="$temp_file" \
      "$url" || {
        rm -f -- "$temp_file"
        return 1
      }

  else
    log_error "ไม่พบ curl หรือ wget ที่รองรับ HTTPS"
    return 1
  fi

  if [[ ! -s "$temp_file" ]]; then
    log_error "ดาวน์โหลดไม่สำเร็จหรือได้ไฟล์ว่าง"
    rm -f -- "$temp_file"
    return 1
  fi

  return 0
}

file_sha256() {
  local file="${1:-}"

  [[ -n "$file" && -f "$file" ]] || return 1

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi

  return 1
}

verify_file_sha256() {
  local file="${1:-}"
  local expected="${2:-}"
  local label="${3:-file}"
  local actual=""

  [[ -f "$file" ]] || {
    log_error "ไม่พบไฟล์สำหรับตรวจ SHA256: $label"
    return 1
  }

  if ! is_sha256 "$expected"; then
    log_error "Trusted SHA256 ไม่ถูกต้อง: $label"
    return 1
  fi

  actual="$(file_sha256 "$file")" || {
    log_error "ไม่สามารถคำนวณ SHA256: $label"
    return 1
  }

  expected="$(printf '%s' "$expected" | tr 'A-F' 'a-f')"
  actual="$(printf '%s' "$actual" | tr 'A-F' 'a-f')"

  if [[ "$actual" != "$expected" ]]; then
    log_error "SHA256 mismatch: $label"
    log_error "Expected: $expected"
    log_error "Actual  : $actual"
    return 1
  fi

  return 0
}

confirm_verified_download() {
  local label="${1:-}"
  local source_url="${2:-}"
  local file_path="${3:-}"
  local expected_sha="${4:-}"
  local actual_sha=""

  [[ -f "$file_path" ]] || return 1

  actual_sha="$(file_sha256 "$file_path")" || return 1

  clear_screen 2>/dev/null || clear 2>/dev/null || true

  echo -e "${MENU_BLUE:-}┌──────────────────────────────────────────────────────────────┐${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}│               VERIFIED DOWNLOAD                             │${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}├──────────────────────────────────────────────────────────────┤${MENU_NC:-}"
  echo -e "  รายการ : ${label}"
  echo -e "  URL    : ${source_url}"
  echo -e "  SHA256 : ${actual_sha}"
  echo -e "  Status : VERIFIED ✓"
  echo -e "${MENU_BLUE:-}└──────────────────────────────────────────────────────────────┘${MENU_NC:-}"

  local answer=""
  read -r -p "ติดตั้งไฟล์ที่ตรวจสอบแล้วหรือไม่ (YES/NO): " answer

  [[ "$answer" == "YES" ]]
}

download_verified_file() {
  local label="${1:-}"
  local source_url="${2:-}"
  local expected_sha="${3:-}"
  local destination_path="${4:-}"
  local chmod_mode="${5:-}"
  local destination_dir=""
  local temp_file=""

  if [[ -z "$label" ||
        -z "$source_url" ||
        -z "$expected_sha" ||
        -z "$destination_path" ]]; then
    log_error "download_verified_file: argument ไม่ครบ"
    return 1
  fi

  if ! is_sha256 "$expected_sha"; then
    log_error "Trusted SHA256 ไม่ถูกต้อง: $label"
    return 1
  fi

  destination_dir="$(dirname -- "$destination_path")"

  if [[ ! -d "$destination_dir" ]]; then
    mkdir -p -- "$destination_dir" || return 1
  fi

  temp_file="$(
    mktemp "${destination_dir}/.sshplus-download.XXXXXX"
  )" || return 1

  if ! download_to_temp_file "$source_url" "$temp_file"; then
    log_error "ดาวน์โหลดไม่สำเร็จ: $label"
    rm -f -- "$temp_file"
    return 1
  fi

  if ! verify_file_sha256 \
       "$temp_file" \
       "$expected_sha" \
       "$label"; then

    log_error "ไฟล์ถูกปฏิเสธและจะไม่ถูกติดตั้ง"
    rm -f -- "$temp_file"
    return 1
  fi

  log_info "SHA256 verified: $label"

  if ! confirm_verified_download \
       "$label" \
       "$source_url" \
       "$temp_file" \
       "$expected_sha"; then

    log_warn "ยกเลิกการติดตั้ง: $label"
    rm -f -- "$temp_file"
    return 1
  fi

  if [[ -n "$chmod_mode" ]]; then
    chmod "$chmod_mode" "$temp_file" || {
      rm -f -- "$temp_file"
      return 1
    }
  fi

  if ! mv -f -- "$temp_file" "$destination_path"; then
    rm -f -- "$temp_file"
    return 1
  fi

  return 0
}
