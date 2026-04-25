#!/bin/bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_NAME="GLM Claude Code 一键安装（macOS）"
NODE_DIST_BASE="https://nodejs.org/dist/latest-jod"
DEFAULT_NPM_REGISTRY="https://registry.npmjs.org/"
HELPER_PKG="@z_ai/coding-helper"
CLAUDE_PKG="@anthropic-ai/claude-code"
DEFAULT_PLAN="glm_coding_plan_china"
DEFAULT_LANG="zh_CN"
SUDO_BIN="${SUDO_BIN:-sudo}"
CURL_BIN="${CURL_BIN:-curl}"

log() { printf '🔹 %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*"; }
err() { printf '❌ %s\n' "$*" >&2; }

pause_and_exit() {
  local code="${1:-0}"
  echo
  if [[ "${NO_PAUSE:-0}" == "1" ]]; then
    exit "$code"
  fi
  read -r -p "按回车键关闭窗口..." _ || true
  exit "$code"
}

on_error() {
  local line="$1"
  err "安装失败（第 ${line} 行）。"
  pause_and_exit 1
}
trap 'on_error $LINENO' ERR

need_command() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少系统命令：$1"; pause_and_exit 1; }
}

need_command "$CURL_BIN"
need_command awk
need_command shasum
need_command sed
need_command grep
need_command mktemp
need_command sudo

pick_plan() {
  GLM_PLAN="${GLM_PLAN:-$DEFAULT_PLAN}"
  API_VALIDATE_URL="https://open.bigmodel.cn/api/coding/paas/v4/models"
  BASE_URL="https://open.bigmodel.cn/api/anthropic"
}

load_existing_api_key() {
  local config="$HOME/.chelper/config.yaml"
  if [[ -f "$config" ]]; then
    EXISTING_API_KEY="$(awk -F': ' '/^api_key:/ {print $2}' "$config" | tail -1 | tr -d '"' || true)"
  else
    EXISTING_API_KEY=""
  fi
}

prompt_api_key() {
  if [[ -n "${GLM_API_KEY:-}" ]]; then
    return
  fi
  load_existing_api_key
  echo
  if [[ -n "$EXISTING_API_KEY" ]]; then
    read -r -s -p "请输入 API Key（直接回车复用已保存的 Key）：" input_key
    echo
    GLM_API_KEY="${input_key:-$EXISTING_API_KEY}"
  else
    read -r -s -p "请输入 API Key：" input_key
    echo
    GLM_API_KEY="$input_key"
  fi
  [[ -n "$GLM_API_KEY" ]] || { err "API Key 不能为空。"; pause_and_exit 1; }
}

mask_key() {
  local key="$1"
  local len=${#key}
  if (( len <= 8 )); then
    printf '%s' '********'
  else
    printf '%s' "${key:0:4}********************************${key:len-4:4}"
  fi
}

validate_api_key() {
  log "校验 API Key..."
  local status
  status="$("$CURL_BIN" -sS -o /tmp/glm_api_validate.$$.json -w '%{http_code}' \
    -H "Authorization: Bearer $GLM_API_KEY" \
    -H 'Content-Type: application/json' \
    "$API_VALIDATE_URL")"
  case "$status" in
    200) ok "API Key 校验通过" ;;
    401) err "API Key 无效或已过期"; rm -f /tmp/glm_api_validate.$$.json; pause_and_exit 1 ;;
    *) err "API 校验失败，HTTP $status"; [[ -f /tmp/glm_api_validate.$$.json ]] && cat /tmp/glm_api_validate.$$.json; rm -f /tmp/glm_api_validate.$$.json; pause_and_exit 1 ;;
  esac
  rm -f /tmp/glm_api_validate.$$.json
}

node_usable() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
    case "$(command -v node) $(command -v npm) $(command -v npx)" in
      *"$HOME/.glm-coding-installer"*) return 1 ;;
    esac
    local major
    major="$(node --version | sed 's/^v//' | cut -d. -f1)"
    [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 18 ))
  else
    return 1
  fi
}

find_latest_pkg_name() {
  "$CURL_BIN" -fsSL "$NODE_DIST_BASE/" | grep -Eo 'node-v[0-9.]+\.pkg' | head -1
}

install_system_node() {
  if node_usable; then
    NODE_BIN="$(command -v node)"
    NPM_BIN="$(command -v npm)"
    NPX_BIN="$(command -v npx)"
    ok "检测到可用 Node.js：$(node --version)"
    return
  fi

  log "未检测到可用 Node.js，开始系统级安装..."
  local pkg_name checksum_url expected_sha tmp_dir pkg_path actual_sha
  pkg_name="$(find_latest_pkg_name)"
  [[ -n "$pkg_name" ]] || { err "无法获取 Node.js 安装包名称"; pause_and_exit 1; }
  checksum_url="$NODE_DIST_BASE/SHASUMS256.txt"
  expected_sha="$("$CURL_BIN" -fsSL "$checksum_url" | awk -v name="$pkg_name" '$2 == name {print $1}')"
  [[ -n "$expected_sha" ]] || { err "无法获取 Node.js 校验值"; pause_and_exit 1; }

  tmp_dir="$(mktemp -d)"
  pkg_path="$tmp_dir/$pkg_name"
  log "下载官方 Node.js 安装包：$pkg_name"
  "$CURL_BIN" -fL --retry 3 --retry-delay 2 -o "$pkg_path" "$NODE_DIST_BASE/$pkg_name"
  actual_sha="$(shasum -a 256 "$pkg_path" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || { err "Node.js 安装包校验失败"; rm -rf "$tmp_dir"; pause_and_exit 1; }
  ok "Node.js 安装包校验通过"

  log "开始系统级安装 Node.js（会弹出管理员授权）..."
  "$SUDO_BIN" installer -pkg "$pkg_path" -target /
  rm -rf "$tmp_dir"

  hash -r
  NODE_BIN="$(command -v node)"
  NPM_BIN="$(command -v npm)"
  NPX_BIN="$(command -v npx)"
  ok "Node.js 已安装：$("$NODE_BIN" --version)"
  ok "npm 已安装：$("$NPM_BIN" --version)"
}

show_npm_network_help() {
  local registry="$1"
  err "无法连接 npm 源：$registry"
  warn "这通常是当前网络、DNS 或代理导致的，工具还没有开始安装。"
  echo
  echo "可以按下面顺序处理后重新运行安装器："
  echo "1. 打开浏览器访问 ${registry}，确认当前网络可以访问。"
  echo "2. 如果正在使用公司网络、校园网、代理或 VPN，请切换网络，或确认代理已开启。"
  echo "3. 如果 npm 配过代理但已经失效，请在终端执行："
  echo "   npm config delete proxy"
  echo "   npm config delete https-proxy"
  echo "4. 如果你有可用的 npm 镜像源，可以先执行："
  echo "   npm config set registry <你的 npm 镜像源地址>"
}

get_npm_registry() {
  local registry
  registry="$("$NPM_BIN" config get registry 2>/dev/null || true)"
  if [[ -z "$registry" || "$registry" == "undefined" || "$registry" == "null" ]]; then
    registry="$DEFAULT_NPM_REGISTRY"
  fi
  printf '%s' "$registry"
}

check_npm_registry_access() {
  local registry="${1:-}"
  [[ -n "$registry" ]] || registry="$(get_npm_registry)"
  log "检查 npm 源连接：$registry"
  if ! "$CURL_BIN" -fsSL --connect-timeout 8 --max-time 20 -o /dev/null "$registry"; then
    show_npm_network_help "$registry"
    pause_and_exit 1
  fi
}

install_global_tools() {
  log "开始系统级安装 Coding Helper 和 Claude Code..."
  local registry npm_log
  registry="$(get_npm_registry)"
  check_npm_registry_access "$registry"
  npm_log="$(mktemp)"
  if ! "$SUDO_BIN" "$NPM_BIN" install -g --registry "$registry" "$HELPER_PKG" "$CLAUDE_PKG" 2>&1 | tee "$npm_log"; then
    if grep -Eqi 'ENOTFOUND|getaddrinfo|registry\.npmjs\.org|network connectivity|proxy' "$npm_log"; then
      show_npm_network_help "$(get_npm_registry)"
    else
      err "npm 全局安装失败。"
      warn "上方是 npm 返回的错误信息，请根据提示处理后重新运行安装器。"
    fi
    rm -f "$npm_log"
    pause_and_exit 1
  fi
  rm -f "$npm_log"
  hash -r
  ok "Coding Helper：$(coding-helper --version)"
  ok "Claude Code：$(claude --version)"
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp "$file" "$file.bak.$(date +%s)"
  fi
}

remove_old_zshrc_path_block() {
  local rc="$HOME/.zshrc"
  [[ -f "$rc" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  awk '
    $0 == "# >>> glm-coding-plan-installer >>>" { skip=1; next }
    $0 == "# <<< glm-coding-plan-installer <<<" { skip=0; next }
    !skip { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"
}

cleanup_old_managed_install() {
  local old_root="$HOME/.glm-coding-installer"
  if [[ -d "$old_root" || -f "$HOME/.zshrc" ]]; then
    log "清理旧的本地托管 Node 路径..."
    remove_old_zshrc_path_block
    if [[ -d "$old_root" ]]; then
      "$SUDO_BIN" rm -rf "$old_root"
    fi
    ok "已清理旧的 ~/.glm-coding-installer 和 ~/.zshrc 注入"
  fi
}

write_user_configs() {
  local chelper_dir="$HOME/.chelper"
  local claude_dir="$HOME/.claude"
  mkdir -p "$chelper_dir" "$claude_dir"

  backup_file "$chelper_dir/config.yaml"
  backup_file "$claude_dir/settings.json"
  backup_file "$HOME/.claude.json"

  cat > "$chelper_dir/config.yaml" <<EOF
lang: $DEFAULT_LANG
plan: $GLM_PLAN
api_key: $GLM_API_KEY
EOF

  GLM_API_KEY_ENV="$GLM_API_KEY" GLM_BASE_URL_ENV="$BASE_URL" node <<'EOF'
const fs = require('fs');
const os = require('os');
const path = require('path');
const home = os.homedir();
const settingsPath = path.join(home, '.claude', 'settings.json');
const claudeJsonPath = path.join(home, '.claude.json');
const apiKey = process.env.GLM_API_KEY_ENV;
const baseUrl = process.env.GLM_BASE_URL_ENV;
let settings = {};
if (fs.existsSync(settingsPath)) {
  settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
}
const env = settings.env || {};
delete env.ANTHROPIC_API_KEY;
settings.env = {
  ...env,
  ANTHROPIC_AUTH_TOKEN: apiKey,
  ANTHROPIC_BASE_URL: baseUrl,
  API_TIMEOUT_MS: '3000000',
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: 1,
};
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
let claudeJson = {};
if (fs.existsSync(claudeJsonPath)) {
  claudeJson = JSON.parse(fs.readFileSync(claudeJsonPath, 'utf8'));
}
claudeJson.hasCompletedOnboarding = true;
fs.writeFileSync(claudeJsonPath, JSON.stringify(claudeJson, null, 2));
EOF

  ok "已写入用户配置"
}

verify_everything() {
  log "运行健康检查..."
  coding-helper doctor || true
  echo
  ok "Node.js：$("$NODE_BIN" --version)"
  ok "npm：$("$NPM_BIN" --version)"
  ok "npx：$("$NPX_BIN" --version)"
  ok "Coding Helper：$(coding-helper --version)"
  ok "Claude Code：$(claude --version)"
  ok "套餐：$GLM_PLAN"
  ok "API Key：$(mask_key "$GLM_API_KEY")"
}

main() {
  clear || true
  echo "========================================"
  echo "  $SCRIPT_NAME"
  echo "========================================"
  echo ""
  pick_plan
  prompt_api_key
  log "已读取 API Key：$(mask_key "$GLM_API_KEY")"
  validate_api_key
  install_system_node
  install_global_tools
  write_user_configs
  cleanup_old_managed_install
  verify_everything
  echo
  ok "安装完成，现在可以直接输入 claude 使用。"
  pause_and_exit 0
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
