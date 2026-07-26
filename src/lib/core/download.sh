# ==================================================
# Core: Secure Download Helpers
# Why: ดาวน์โหลดไฟล์ภายนอกอย่างปลอดภัย
# ==================================================

download_to_temp_file() {
  local url="${1:-}" temp_file="${2:-}"
  [[ -z "$url" || -z "$temp_file" ]] && return 1
  rm -f "$temp_file"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 300 "$url" -o "$temp_file"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$temp_file" "$url"
  else log_error "ไม่พบ curl หรือ wget"; return 1; fi
  [[ -s "$temp_file" ]] || { log_error "ดาวน์โหลดไม่สำเร็จ"; rm -f "$temp_file"; return 1; }
}

file_sha256() {
  local f="${1:-}"
  [[ -z "$f" || ! -f "$f" ]] && return 1
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$f" | awk '{print $1}'; return 0; fi
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$f" | awk '{print $1}'; return 0; fi
  return 1
}

confirm_trust_download() {
  local label="${1:-}" source_url="${2:-}" file_path="${3:-}"
  [[ -z "$label" || -z "$source_url" || -z "$file_path" || ! -f "$file_path" ]] && return 1
  local sha
  sha="$(file_sha256 "$file_path" || true)"
  clear_screen 2>/dev/null || clear
  echo -e "${MENU_BLUE:-}┌──────────────────────────────────────────────────────────────┐${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}│${MENU_BG_RED:-}              DOWNLOAD SECURITY CONFIRMATION                 ${MENU_NC:-}${MENU_BLUE:-}│${MENU_NC:-}"
  echo -e "${MENU_BLUE:-}├──────────────────────────────────────────────────────────────┤${MENU_NC:-}"
  echo -e "  รายการ : ${label}"
  echo -e "  URL    : ${source_url}"
  echo -e "  SHA256 : ${sha:-ไม่สามารถคำนวณได้}"
  echo -e "${MENU_BLUE:-}└──────────────────────────────────────────────────────────────┘${MENU_NC:-}"
  local answer
  read -r -p "ยืนยันหรือไม่ (YES/NO): " answer
  [[ "$answer" == "YES" ]]
}

download_with_user_confirmation() {
  local label="${1:-}" source_url="${2:-}" destination_path="${3:-}" chmod_mode="${4:-}"
  [[ -z "$label" || -z "$source_url" || -z "$destination_path" ]] && return 1
  local temp_file
  temp_file="$(mktemp "${TMP_BASE:-/tmp}/secure-download.XXXXXX")" || return 1
  if ! download_to_temp_file "$source_url" "$temp_file"; then rm -f "$temp_file"; return 1; fi
  if ! confirm_trust_download "$label" "$source_url" "$temp_file"; then rm -f "$temp_file"; return 1; fi
  mv "$temp_file" "$destination_path"
  [[ -n "$chmod_mode" ]] && chmod "$chmod_mode" "$destination_path"
}
