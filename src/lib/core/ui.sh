# ==================================================
# Core: UI Helpers
# Why: ฟังก์ชัน UI พื้นฐานสำหรับเมนู interactive
# ==================================================

# Why: หยุดรอผู้ใช้กด Enter เฉพาะเมื่อเป็น interactive shell
pause() {
  if [[ ! -t 0 ]]; then
    return 0
  fi

  read -r -p "Press Enter to continue..."
}

# Why: ล้างหน้าจอเฉพาะเมื่ออยู่บน terminal จริง
# Why: reset สีทุกครั้งก่อนลบจอ → ป้องกันพื้นสีค้างทาทั้งหน้าจอ
clear_screen() {
  printf '\033[0m'
  clear 2>/dev/null || printf '\033[2J\033[H'
}
