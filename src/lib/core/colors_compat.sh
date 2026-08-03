# Why: alias ชื่อสั้นให้ไฟล์ features ที่ยังใช้ชื่อเดิม
#      ถ้า NC ว่าง โค้ดสีจะไม่ถูก reset → พื้นสีค้างติดทั้งจอ
NC="${SSHPLUS_NC:-\033[0m}"
RED="${SSHPLUS_RED:-\033[0;31m}"
GREEN="${SSHPLUS_GREEN:-\033[0;32m}"
YELLOW="${SSHPLUS_YELLOW:-\033[0;33m}"
BLUE="${SSHPLUS_BLUE:-\033[0;34m}"
CYAN="${SSHPLUS_CYAN:-\033[0;36m}"
WHITE="${SSHPLUS_WHITE:-\033[1;37m}"
BG_RED="${SSHPLUS_BG_RED:-\033[41m}"
