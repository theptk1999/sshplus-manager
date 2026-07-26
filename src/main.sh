# ==================================================
# Application Main
# Why: เมนูหลักและ dispatcher แบบสคริปต์เดิม
# ==================================================

# Why: bootstrap เบาๆ แล้วเข้าเมนู
main() {
  detect_os
  log_info "OS detected: ${SSHPLUS_OS_ID:-unknown}"

  # Why: ถ้ารันด้วย root ให้เตรียม DB ไว้ล่วงหน้า
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    ensure_db || true
    db_migrate_schema_if_needed || true
  fi

  # Why: ถ้าไม่ใช่ interactive shell ให้จบเลย
  #      เพื่อป้องกัน CI หรือ automation hang
  if [[ ! -t 0 ]]; then
    echo "SSHPlus Manager - Original menu ready"
    return 0
  fi

  local option

  while true; do
    show_menu

    if ! read -r option; then
      break
    fi

    case "$option" in
      01|1) function_create_user ;;
      02|2) function_create_test ;;
      03|3) function_delete_user ;;
      04|4) function_renew_user ;;
      05|5) function_users_online ;;
      06|6) function_change_expiry ;;
      07|7) function_change_limit ;;
      08|8) function_change_pass ;;
      09|9) function_remove_expired ;;
      10) function_list_users ;;
      11) function_backup_users ;;
      12) function_mode_connection ;;
      13) function_speedtest ;;
      14) function_otimizar ;;
      15) function_trafego ;;
      16) function_firewall ;;
      17) function_info_sistema ;;
      18) function_banner ;;
      19) function_toggle_limit ;;
      20) function_toggle_badvpn ;;
      21) function_auto_menu ;;
      22) function_toggle_bot ;;
      23) function_ferramentas ;;
      24) function_websocket ;;
      25) function_openvpn ;;
      26) function_optimize_system ;;
      27) function_v2ray_manager ;;
      00|0)
        if declare -F clear_screen >/dev/null 2>&1; then
          clear_screen
        fi
        log_info "Good Bye!"
        return 0
        ;;
      *)
        log_error "เลือกไม่ถูกต้อง!"
        sleep 0.5
        ;;
    esac
  done
}
