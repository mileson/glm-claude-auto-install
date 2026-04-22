#!/bin/bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

OLD_ROOT="$HOME/.glm-coding-installer"
RC_FILE="$HOME/.zshrc"

ok() { printf '✅ %s\n' "$*"; }
err() { printf '❌ %s\n' "$*" >&2; }
log() { printf '🔹 %s\n' "$*"; }

pause_and_exit() {
  local code="${1:-0}"
  echo
  read -r -p "按回车键关闭窗口..." _ || true
  exit "$code"
}

system_install_ready() {
  command -v node >/dev/null 2>&1 || return 1
  command -v npm >/dev/null 2>&1 || return 1
  command -v npx >/dev/null 2>&1 || return 1
  command -v claude >/dev/null 2>&1 || return 1
  case "$(command -v node) $(command -v npm) $(command -v npx) $(command -v claude)" in
    *"$OLD_ROOT"*) return 1 ;;
  esac
  return 0
}

remove_old_zshrc_path_block() {
  [[ -f "$RC_FILE" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk '
    $0 == "# >>> glm-coding-plan-installer >>>" { skip=1; next }
    $0 == "# <<< glm-coding-plan-installer <<<" { skip=0; next }
    !skip { print }
  ' "$RC_FILE" > "$tmp"
  mv "$tmp" "$RC_FILE"
}

main() {
  clear || true
  echo "========================================"
  echo "  清理旧的本地托管 GLM Node 安装"
  echo "========================================"
  echo

  if ! system_install_ready; then
    err "还没有检测到系统级 Node + Claude。"
    err "请先运行 scripts/macos/install-glm-claude.command 完成系统级安装，再执行本清理脚本。"
    pause_and_exit 1
  fi

  log "检测到系统级环境："
  ok "node -> $(command -v node)"
  ok "npm -> $(command -v npm)"
  ok "npx -> $(command -v npx)"
  ok "claude -> $(command -v claude)"

  remove_old_zshrc_path_block
  if [[ -d "$OLD_ROOT" ]]; then
    sudo rm -rf "$OLD_ROOT"
  fi

  ok "已移除旧的 ~/.glm-coding-installer"
  ok "已移除 ~/.zshrc 中旧 PATH 注入"
  pause_and_exit 0
}

main "$@"
