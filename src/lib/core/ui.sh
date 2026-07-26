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
clear_screen() {
  if [[ -t 1 ]]; then
    clear
  fi
}
