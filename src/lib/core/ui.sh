# ==================================================
# Core: UI Helpers
# Why: ฟังก์ชัน UI พื้นฐานสำหรับเมนู interactive
# ==================================================

# Why: reset สีก่อนหยุดรอ → ข้อความ "Press Enter" ไม่ติดพื้นสีค้าง
pause() {
  printf '\033[0m'
  read -r -p "Press Enter to continue..." _ || true
}

# Why: ล้างหน้าจอเฉพาะเมื่ออยู่บน terminal จริง
# Why: reset สีทุกครั้งก่อนลบจอ → ป้องกันพื้นสีค้างทาทั้งหน้าจอ
clear_screen() {
  printf '\033[0m'
  clear 2>/dev/null || printf '\033[2J\033[H'
}
