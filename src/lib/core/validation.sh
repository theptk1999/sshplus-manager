# ==================================================
# Core: Validation Helpers
# Why: ตรวจสอบ input พื้นฐานก่อนทำงานจริง
# ==================================================

# Why: ตรวจสอบจำนวนเต็มบวกหรือศูนย์
is_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

# Why: ตรวจสอบ port ที่ถูกต้องตามช่วง TCP/UDP
is_port() {
  is_uint "${1:-}" && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# Why: ตรวจสอบ username ปลอดภัย และไม่ใช้ root
is_username() {
  [[ "${1:-}" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] && [[ "${1:-}" != "root" ]]
}

# Why: ตรวจสอบวันที่ที่ GNU date เข้าใจได้
is_date() {
  date -d "${1:-}" >/dev/null 2>&1
}

# Why: อ่าน password แบบซ่อนจาก terminal และคืนค่ากลับไปยังตัวแปรของ caller
prompt_password() {
  local prompt="$1"
  local result_var="$2"
  local __prompt_password_value=""

  # Why: อนุญาตเฉพาะชื่อตัวแปรที่ถูกต้องตามกฎของ Bash
  if [[ ! "$result_var" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    return 1
  fi

  # Why: ถ้าไม่ใช่ TTY ไม่ควรอ่าน secret
  if [[ ! -t 0 ]]; then
    return 1
  fi

  # Why:
  # - IFS= ป้องกันการตัดช่องว่างหน้า/หลังรหัสผ่าน
  # - -r ป้องกันการตีความ backslash
  # - -s ซ่อนรหัสผ่านขณะพิมพ์
  if ! IFS= read -r -s -p "$prompt" __prompt_password_value; then
    echo
    return 1
  fi

  # Why: ขึ้นบรรทัดใหม่หลังอ่านรหัสผ่านแบบซ่อน
  echo

  # Why: ส่งค่ากลับไปยังตัวแปรที่ caller ระบุ
  printf -v "$result_var" '%s' "$__prompt_password_value"
}

# Why: ยืนยันด้วย YES เท่านั้น ลดโอกาสพลาด
confirm_yes() {
  local prompt="${1:-Confirm? (YES/NO): }"
  local answer=""

  if [[ ! -t 0 ]]; then
    return 1
  fi

  read -r -p "$prompt" answer
  [[ "$answer" == "YES" ]]
}
