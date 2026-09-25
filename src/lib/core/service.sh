# ==================================================
# Core: Service Manager Abstraction (Full)
# Why: จัดการ service ข้าม init system
# ==================================================

svc_daemon_reload() { command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 || true; }

svc_logs() {
  local svc="${1:-}"
  local lines="${2:-50}"
  local clean_svc="${svc%.service}"
  [[ -z "${svc:-}" ]] && return 1
  if command -v journalctl >/dev/null 2>&1; then journalctl -u "${svc:-}" -n "$lines" --no-pager
  elif [[ -f /var/log/syslog ]]; then tail -n "$lines" /var/log/syslog | grep -i "${clean_svc:-}" || true
  elif [[ -f /var/log/messages ]]; then tail -n "$lines" /var/log/messages | grep -i "${clean_svc:-}" || true
  fi
}

svc_start() {
  local svc="${1:-}"
  local clean_svc="${svc%.service}"
  [[ -z "${svc:-}" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl start "${svc:-}" >/dev/null 2>&1 && return 0
  command -v service >/dev/null 2>&1 && service "${clean_svc:-}" start >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "${clean_svc:-}" start >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" start >/dev/null 2>&1 && return 0
  return 1
}

svc_stop() {
  local svc="${1:-}"
  local clean_svc="${svc%.service}"
  [[ -z "${svc:-}" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl stop "${svc:-}" >/dev/null 2>&1 && return 0
  command -v service >/dev/null 2>&1 && service "${clean_svc:-}" stop >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "${clean_svc:-}" stop >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" stop >/dev/null 2>&1 && return 0
  return 1
}

svc_restart() {
  local svc="${1:-}"
  local clean_svc="${svc%.service}"
  [[ -z "${svc:-}" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl restart "${svc:-}" >/dev/null 2>&1 && return 0
  command -v service >/dev/null 2>&1 && service "${clean_svc:-}" restart >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "${clean_svc:-}" restart >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" restart >/dev/null 2>&1 && return 0
  return 1
}

svc_enable() {
  local svc="${1:-}"
  local clean_svc="${svc%.service}"
  [[ -z "${svc:-}" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl enable "${svc:-}" >/dev/null 2>&1 && return 0
  command -v chkconfig >/dev/null 2>&1 && chkconfig "${clean_svc:-}" on >/dev/null 2>&1 && return 0
  command -v update-rc.d >/dev/null 2>&1 && update-rc.d "${clean_svc:-}" defaults >/dev/null 2>&1 && return 0
  command -v rc-update >/dev/null 2>&1 && rc-update add "${clean_svc:-}" default >/dev/null 2>&1 && return 0
  return 1
}

svc_disable() {
  local svc="${1:-}"
  local clean_svc="${svc%.service}"
  [[ -z "${svc:-}" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl disable "${svc:-}" >/dev/null 2>&1 && return 0
  command -v chkconfig >/dev/null 2>&1 && chkconfig "${clean_svc:-}" off >/dev/null 2>&1 && return 0
  command -v update-rc.d >/dev/null 2>&1 && update-rc.d -f "${clean_svc:-}" remove >/dev/null 2>&1 && return 0
  command -v rc-update >/dev/null 2>&1 && rc-update del "${clean_svc:-}" default >/dev/null 2>&1 && return 0
  return 1
}

svc_is_active() {
  local svc="${1:-}"
  local clean_svc="${svc%.service}"
  [[ -z "${svc:-}" ]] && return 1
  command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "${svc:-}" 2>/dev/null && return 0
  command -v service >/dev/null 2>&1 && service "${clean_svc:-}" status >/dev/null 2>&1 && return 0
  command -v rc-service >/dev/null 2>&1 && rc-service "${clean_svc:-}" status >/dev/null 2>&1 && return 0
  [[ -x "/etc/init.d/${clean_svc}" ]] && "/etc/init.d/${clean_svc}" status >/dev/null 2>&1 && return 0
  pgrep -f "${clean_svc:-}" >/dev/null 2>&1
}

svc_provision() {
  local name="${1:-}" desc="${2:-}" cmd="${3:-}" env_file="${4:-}" sysd_ext="${5:-}"
  [[ -z "${name:-}" || -z "$desc" || -z "$cmd" ]] && return 1
  local sysd_env="" sysv_env_load=""
  if [[ -n "$env_file" ]]; then
    sysd_env="EnvironmentFile=${env_file}"
    sysv_env_load="[ -f \"${env_file}\" ] && . \"${env_file}\""
  fi
  if command -v systemctl >/dev/null 2>&1; then
    cat <<SVCEOF > "/etc/systemd/system/${name}.service"
[Unit]
Description=${desc}
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root
ExecStart=${cmd}
Restart=always
RestartSec=3
KillMode=mixed
TimeoutStopSec=10
${sysd_env}
${sysd_ext}
[Install]
WantedBy=multi-user.target
SVCEOF
    chmod 644 "/etc/systemd/system/${name}.service"
    svc_daemon_reload
  else
    cat <<SVCEOF > "/etc/init.d/${name}"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          ${name}
# Required-Start:    \$network \$local_fs
# Required-Stop:     \$network \$local_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: ${desc}
### END INIT INFO
PIDFILE="/run/${name}.pid"
start() {
  if [ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null; then return 1; fi
  ${sysv_env_load}
  nohup ${cmd} >/dev/null 2>&1 &
  echo \$! > "\$PIDFILE"
}
stop() {
  if [ -f "\$PIDFILE" ]; then kill "\$(cat "\$PIDFILE")" 2>/dev/null || true; rm -f "\$PIDFILE"; fi
}
case "\$1" in
  start) start ;; stop) stop ;; restart) stop; sleep 2; start ;;
  status) [ -f "\$PIDFILE" ] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null && exit 0 || exit 1 ;;
  *) echo "Usage: \$0 {start|stop|restart|status}"; exit 1 ;;
esac
SVCEOF
    chmod +x "/etc/init.d/${name}"
  fi
}

svc_remove() {
  local name="${1:-}"
  [[ -z "${name:-}" ]] && return 1
  svc_stop "${name:-}" || true
  svc_disable "${name:-}" || true
  if command -v systemctl >/dev/null 2>&1; then
    rm -f "/etc/systemd/system/${name}.service"
    svc_daemon_reload
  else
    rm -f "/etc/init.d/${name}"
  fi
}

restart_ssh_service() {
  svc_restart ssh ||
    svc_restart sshd
}
