
<div align="center">

# 🚀 SSHPlus Manager Pro

**เครื่องมือจัดการ SSH/VPN/User แบบ All-in-One สำหรับ Linux VPS**

รองรับ Ubuntu • Debian • CentOS • AlmaLinux • Rocky Linux

[![CI](https://github.com/theptk1999/sshplus-manager/actions/workflows/ci.yml/badge.svg)](https://github.com/theptk1999/sshplus-manager/actions)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/bash-5.0+-green.svg)](https://www.gnu.org/software/bash/)

[ติดตั้ง](#-ติดตั้งด่วน) • [ฟีเจอร์](#-ฟีเจอร์) • [ใช้งาน](#-ใช้งาน) • [อัปเดต](#-อัปเดต) • [ถอนการติดตั้ง](#-ถอนการติดตั้ง)

</div>

---

## 📸 Preview

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                       ➱ SSHPLUS MANAGER PRO ➱
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  OS  : Ubuntu           TIME : 13:15:10
  CPU : 2 Core (68%)     RAM  : 11Gi (5%)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ● ออนไลน์: 3    ● หมดอายุ: 0    ● ทั้งหมด: 1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [01] • สร้างผู้ใช้งาน       [15] • ดูทราฟฟิก (Traffic)
  [02] • สร้างไอดีทดสอบ     [16] • จัดการ Firewall
  [03] • ลบผู้ใช้งาน         [17] • ข้อมูลระบบ (Info)
  [04] • ต่ออายุผู้ใช้งาน      [18] • ตั้งค่า Banner         ○
  [05] • แสดงคนออนไลน์     [19] • SSH Limiter         ○
  [06] • แก้วันหมดอายุ       [20] • BadVPN (Game)       ●
  [07] • แก้ไขลิมิตจอ        [21] • เมนูอัตโนมัติ           ○
  [08] • เปลี่ยนรหัสผ่าน      [22] • บอท Telegram        ●
  [09] • ลบคนหมดอายุ       [23] • เครื่องมือ (Tools)     →
  [10] • รายชื่อทั้งหมด       [24] • WebSocket (Proxy)   ●
  [11] • สำรองข้อมูล        [25] • OpenVPN Manager     ○
  [12] • จัดการพอร์ต        [26] • System Optimizer    →
  [13] • ทดสอบความเร็ว     [27] • Xray (Reality)      ○
  [14] • เคลียร์แรม/Cache   [28] • อัปเดต (GitHub)
  [00] • ออกจากเมนู        [29] • ถอนการติดตั้ง          ⚠
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 เลือกเมนู (Select Option): 
```

---

## ✨ ฟีเจอร์

### 👤 จัดการผู้ใช้ (User Management)
- สร้าง / ลบ / ต่ออายุ SSH user
- กำหนดวันหมดอายุ + จำกัดจำนวนจอ (limit)
- เปลี่ยนรหัสผ่าน / แก้ไขลิมิต / แก้ไขวันหมดอายุ
- ลบผู้ใช้หมดอายุอัตโนมัติ
- สำรอง / กู้คืนฐานข้อมูลผู้ใช้

### 🌐 เครือข่าย (Network)
- เปลี่ยน Port SSH / Dropbear / Stunnel / Squid
- ดูพอร์ตที่เปิดอยู่ทั้งหมด
- Firewall (UFW) แบบปลอดภัย ไม่ lock ตัวเอง
- WebSocket Proxy สำหรับ bypass
- OpenVPN Manager (ติดตั้ง + จัดการ)
- Xray VLESS + Reality (anti-detection)

### ⚙️ Services
- **SSH Limiter** — บังคับ limit การเชื่อมต่ออัตโนมัติ
- **BadVPN UDPGW** — รองรับ UDP สำหรับเกม
- **Telegram Bot** — สร้าง/ลบ/ดู user ผ่านแชท
- **Auto Menu** — เรียกเมนูอัตโนมัติเมื่อ SSH เข้า

### 🛠️ เครื่องมือ (Tools)
- Speedtest CLI
- System Info (CPU/RAM/Disk/IP)
- SSH Banner Manager
- TCP BBR + Network Tuning
- Swap RAM
- Certbot SSL
- Fail2ban
- Self-Update จาก GitHub
- Uninstall สะอาด

---

## 📋 Requirements

| รายการ | ขั้นต่ำ |
|--------|---------|
| OS | Ubuntu 20.04+ / Debian 11+ / CentOS 8+ |
| สิทธิ์ | **root** |
| RAM | 512 MB |
| Disk | 1 GB |
| Internet | ✅ ต้องมี |

---

## 🚀 ติดตั้งด่วน

### วิธีที่ 1: curl (แนะนำ)

```bash
COMMIT="<40-char trusted commit SHA>"

curl -fsSL \
  "https://raw.githubusercontent.com/theptk1999/sshplus-manager/${COMMIT}/install.sh" \
  | sudo env SSHPLUS_REF="$COMMIT" bash
```

### วิธีที่ 2: git clone

```bash
sudo apt update && sudo apt install -y git
COMMIT="<40-char trusted commit SHA>"

git clone https://github.com/theptk1999/sshplus-manager.git /opt/sshplus-manager
cd /opt/sshplus-manager

git fetch origin main
git checkout --detach "$COMMIT"

bash scripts/build.sh

cd dist
sha256sum -c sshplus.sh.sha256
cd ..

sudo install -m 755 dist/sshplus.sh /usr/local/sbin/sshplus
```

### วิธีที่ 3: ดาวน์โหลดไฟล์เดียว

ไปที่ [Releases](https://github.com/theptk1999/sshplus-manager/releases) แล้วดาวน์โหลด `sshplus.sh`

```bash
chmod +x sshplus.sh
sudo ./sshplus.sh
```

---

## 🎯 ใช้งาน

หลังติดตั้ง รันด้วยคำสั่ง:

```bash
sshplus
```

หรือ:

```bash
sudo /usr/local/sbin/sshplus
```

### ตัวอย่าง: สร้างผู้ใช้

```
เลือกเมนู: 01
ชื่อผู้ใช้งาน: user01
รหัสผ่าน: ********
จำนวนวัน: 30
จำกัดการเชื่อมต่อ: 2
```

### ตัวอย่าง: Telegram Bot

```
เลือกเมนู: 22
1. ตั้งค่า Token & ID
2. เปิดบอท

คำสั่งใน Telegram:
  /add user01 pass123 30 2
  /del user01
  /list
```

---

## 🔄 อัปเดต

### วิธีที่ 1: จากเมนู

```
เลือกเมนู: 28 (อัปเดต GitHub)
```

### วิธีที่ 2: curl

```bash
COMMIT="<40-char trusted commit SHA>"

curl -fsSL \
  "https://raw.githubusercontent.com/theptk1999/sshplus-manager/${COMMIT}/install.sh" \
  | sudo env SSHPLUS_REF="$COMMIT" bash
```

### วิธีที่ 3: อัปเดตด้วย commit ที่ระบุ

```bash
cd /opt/sshplus-manager

git fetch origin main

COMMIT="$(git rev-parse origin/main)"
echo "Candidate commit: $COMMIT"
git log -1 --oneline "$COMMIT"

git checkout --detach "$COMMIT"
bash scripts/build.sh

cd dist
sha256sum -c sshplus.sh.sha256
sudo install -m 755 sshplus.sh /usr/local/sbin/sshplus
```

---

## 🗑️ ถอนการติดตั้ง

```
เลือกเมนู: 29 (ถอนการติดตั้ง)
```

หรือรัน manual:

```bash
sudo systemctl stop sshplus-limiter badvpn sshplus-bot sshplus-ws 2>/dev/null
sudo rm -f /usr/local/sbin/sshplus
sudo rm -rf /opt/sshplus-manager /etc/sshplus
sudo rm -f /root/usuarios.db /root/limit_auto.sh /root/bot_auto.py /root/proxy_ws.py
```

> ⚠️ **หมายเหตุ:** SSH users จะไม่ถูกลบอัตโนมัติ ต้องลบเองด้วย `userdel --force username`

---

## 🏗️ โครงสร้างโปรเจกต์

```
sshplus-manager/
├── .github/workflows/ci.yml   # GitHub Actions CI/CD
├── bin/sshplus                 # Development entrypoint
├── scripts/
│   ├── build.sh                # Build single-file distribution
│   ├── install.sh              # System installer
│   └── termux-prepare.sh       # Termux/mobile dev helper
├── src/
│   ├── lib/
│   │   ├── core/               # Core infrastructure
│   │   │   ├── log.sh          #   Logging
│   │   │   ├── guard.sh        #   Root/OS detection
│   │   │   ├── validation.sh   #   Input validation
│   │   │   ├── package.sh      #   Package manager abstraction
│   │   │   ├── service.sh      #   Service manager abstraction
│   │   │   ├── download.sh     #   Secure download helpers
│   │   │   ├── constants.sh    #   Paths & URLs
│   │   │   ├── menu_ui.sh      #   Menu display
│   │   │   └── ui.sh           #   UI helpers (pause/clear)
│   │   ├── data/
│   │   │   └── user_db.sh      #   Database layer (atomic + flock)
│   │   └── features/
│   │       ├── 10_users.sh     #   User management
│   │       ├── 20_network.sh   #   Ports/Firewall/WS/VPN/Xray
│   │       ├── 30_services.sh  #   Limiter/BadVPN/Bot/AutoMenu
│   │       ├── 40_tools.sh     #   Speedtest/Info/Banner/Optimizer
│   │       └── 50_uninstall.sh #   Uninstall & Self-update
│   └── main.sh                 # Menu dispatcher
├── tests/smoke.bats            # Smoke tests
├── install.sh                  # curl installer
├── Makefile                    # Dev commands
└── README.md                   # This file
```

---

## 🔒 ความปลอดภัย

- ✅ ไม่เก็บรหัสผ่านในฐานข้อมูล
- ✅ DB file permission `600`
- ✅ ดาวน์โหลดไฟล์ภายนอกต้องยืนยัน SHA256
- ✅ Firewall enable แบบไม่ lock ตัวเอง (อนุญาต SSH port ก่อน)
- ✅ Bot token เก็บใน `/etc/sshplus/bot.env` (permission `600`)
- ✅ ใช้ `flock` ป้องกัน DB corruption
- ✅ Atomic file operations (mktemp + mv)

---

## 🤖 Telegram Bot Commands

| คำสั่ง | รายละเอียด | ตัวอย่าง |
|--------|-----------|---------|
| `/add` | สร้างผู้ใช้ | `/add user01 pass123 30 2` |
| `/del` | ลบผู้ใช้ | `/del user01` |
| `/list` | ดูรายชื่อทั้งหมด | `/list` |

---

## 📱 พัฒนาบนมือถือ (Termux)

โปรเจกต์นี้ออกแบบให้พัฒนาบน Termux + MT Manager ได้:

```bash
pkg install git bash
git clone https://github.com/theptk1999/sshplus-manager.git
cd sshplus-manager
bash scripts/termux-prepare.sh
bash dist/sshplus.sh
```

---

## 🙏 Credits

- OpenVPN installer by [Nyr](https://github.com/Nyr/openvpn-install)
- Xray Core by [XTLS](https://github.com/XTLS/Xray-install)
- BadVPN by [daybreakersx](https://github.com/daybreakersx/premscript)

---

## 📄 License

MIT License — ดูที่ [LICENSE](LICENSE)

---

<div align="center">

**Made with ❤️ for Thai VPS Community**

⭐ ถ้าโปรเจกต์นี้มีประโยชน์ กรุณากด Star ให้ด้วยครับ!

</div>
