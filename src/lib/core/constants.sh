# ==================================================
# Core: Constants & Global State
# Why: รวม path/URL/global state ไว้ที่เดียว
# ==================================================

# Why: path กลางสำหรับ DB และ service scripts
DB_FILE="${SSHPLUS_DB_FILE:-/root/usuarios.db}"
DB_LOCK_FILE="${SSHPLUS_DB_LOCK_FILE:-${DB_FILE}.lock}"
INSTALL_LOG="/var/log/sshplus_install.log"
LIMIT_SCRIPT="/root/limit_auto.sh"
BOT_SCRIPT="/root/bot_auto.py"
WS_SCRIPT="/root/proxy_ws.py"
BADVPN_BIN="/usr/bin/badvpn-udpgw"
OPENVPN_SCRIPT="/root/openvpn-install.sh"
BOT_ENV_DIR="/etc/sshplus"
BOT_ENV_FILE="${BOT_ENV_DIR}/bot.env"

# Why: URL ภายนอกสำหรับดาวน์โหลด
URL_BADVPN="https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
URL_BADVPN_BACKUP="https://raw.githubusercontent.com/theptk1999/BadVPN/main/badvpn-udpgw64"
URL_OPENVPN="https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh"
URL_XRAY_INSTALL="https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh"

# Why: runtime state
GLOBAL_APT_UPDATED=0
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
TMP_BASE="${TMPDIR:-/tmp}"
