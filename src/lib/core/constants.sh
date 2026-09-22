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

# Why: pin upstream ด้วย immutable commit + trusted SHA256
OPENVPN_COMMIT="00f7a862f60e168cba5f6d7717b41d1323c78e7f"
OPENVPN_SHA256="44bb99a8426eda139e7fe0e628eb72e0c01de86ced7dc5b11710c6ab72033203"
URL_OPENVPN="https://raw.githubusercontent.com/Nyr/openvpn-install/${OPENVPN_COMMIT}/openvpn-install.sh"

XRAY_INSTALL_COMMIT="e741a4f56d368afbb9e5be3361b40c4552d3710d"
XRAY_INSTALL_SHA256="7f70c95f6b418da8b4f4883343d602964915e28748993870fd554383afdbe555"
URL_XRAY_INSTALL="https://raw.githubusercontent.com/XTLS/Xray-install/${XRAY_INSTALL_COMMIT}/install-release.sh"

BADVPN_PRIMARY_COMMIT="2c22d71eca1cdba48ba8b38dc20075dfce07bbbf"
BADVPN_PRIMARY_SHA256="48832133b7bdff20261bac41713e3ea231404b85764c1143d2095311867fb43f"
URL_BADVPN="https://raw.githubusercontent.com/daybreakersx/premscript/${BADVPN_PRIMARY_COMMIT}/badvpn-udpgw64"

BADVPN_BACKUP_COMMIT="ce95ee1bd4504bbdd1028094c79fe8b71fef2891"
BADVPN_BACKUP_SHA256="48832133b7bdff20261bac41713e3ea231404b85764c1143d2095311867fb43f"
URL_BADVPN_BACKUP="https://raw.githubusercontent.com/theptk1999/BadVPN/${BADVPN_BACKUP_COMMIT}/badvpn-udpgw64"

# Why: runtime state
GLOBAL_APT_UPDATED=0
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
TMP_BASE="${TMPDIR:-/tmp}"
