#!/bin/bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_NAME="OpenAI Codex CLI 一键安装（macOS）"
NODE_DIST_BASE="https://nodejs.org/dist/latest-jod"
DEFAULT_NPM_REGISTRY="https://registry.npmjs.org/"
CODEX_PKG="@openai/codex"
CODEX_PROVIDER_NAME="OpenAI"
CODEX_BASE_URL="https://ai.558669.xyz"
DEFAULT_MODEL="gpt-5.5"
DEFAULT_REASONING="xhigh"
DEFAULT_CONTEXT_WINDOW="1000000"
DEFAULT_AUTO_COMPACT_TOKEN_LIMIT="900000"
DEFAULT_APPROVAL_POLICY="never"
DEFAULT_SANDBOX_MODE="danger-full-access"
DEFAULT_APPROVALS_REVIEWER="user"
LOG_DIR="${TMPDIR:-/tmp}/glm-claude-auto-install-logs"
LOG_PATH="$LOG_DIR/install-openai-codex-$(date +%Y%m%d-%H%M%S).log"
GUI_MODE=0
CODEX_API_KEY=""
CODEX_API_KEY_FILE=""
REUSE_SAVED_KEY=0

mkdir -p "$LOG_DIR"

for arg in "$@"; do
  case "$arg" in
    --gui) GUI_MODE=1 ;;
    --console) GUI_MODE=0 ;;
    --reuse-saved-key) REUSE_SAVED_KEY=1 ;;
    --api-key=*) CODEX_API_KEY="${arg#--api-key=}" ;;
    --api-key-file=*) CODEX_API_KEY_FILE="${arg#--api-key-file=}" ;;
  esac
done

emit_gui_event() {
  if [[ "$GUI_MODE" == "1" && -n "${GUI_EVENT_FILE:-}" ]]; then
    printf '%s\t%s\n' "$1" "$2" >> "$GUI_EVENT_FILE"
  fi
}

log_line() {
  local level="$1"
  local msg="$2"
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$LOG_PATH"
  emit_gui_event "$level" "$msg"
}

log() { printf '🔹 %s\n' "$*"; log_line INFO "$*"; }
ok() { printf '✅ %s\n' "$*"; log_line OK "$*"; }
err() { printf '❌ %s\n' "$*" >&2; log_line ERROR "$*"; }
warn() { printf '⚠️  %s\n' "$*"; log_line WARN "$*"; }

pause_and_exit() {
  local code="${1:-0}"
  echo
  echo "日志文件：$LOG_PATH"
  if [[ "$GUI_MODE" != "1" ]]; then
    read -r -p "按回车键关闭窗口..." _ || true
  fi
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

shell_quote() {
  printf '%q' "$1"
}

escape_for_applescript() {
  python3 - "$1" <<'PY'
import sys
s = sys.argv[1].replace("\\", "\\\\").replace('"', '\\"')
print(s)
PY
}

run_admin_shell() {
  local cmd="$1"
  if [[ "$GUI_MODE" == "1" ]]; then
    local escaped
    escaped="$(escape_for_applescript "$cmd")"
    osascript <<APPLESCRIPT
do shell script "$escaped" with administrator privileges
APPLESCRIPT
  else
    sudo /bin/bash -lc "$cmd"
  fi
}

node_usable() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
    local major
    major="$(node --version | sed 's/^v//' | cut -d. -f1)"
    [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 18 ))
  else
    return 1
  fi
}

find_latest_pkg_name() {
  curl -fsSL "$NODE_DIST_BASE/" | grep -Eo 'node-v[0-9.]+\.pkg' | head -1
}

install_system_node() {
  if node_usable; then
    NODE_BIN="$(command -v node)"
    NPM_BIN="$(command -v npm)"
    NPX_BIN="$(command -v npx)"
    ok "检测到可用 Node.js：$($NODE_BIN --version)"
    return
  fi

  log "未检测到可用 Node.js，开始系统级安装..."
  local pkg_name checksum_url expected_sha tmp_dir pkg_path actual_sha
  pkg_name="$(find_latest_pkg_name)"
  [[ -n "$pkg_name" ]] || { err "无法获取 Node.js 安装包名称"; pause_and_exit 1; }
  checksum_url="$NODE_DIST_BASE/SHASUMS256.txt"
  expected_sha="$(curl -fsSL "$checksum_url" | awk -v name="$pkg_name" '$2 == name {print $1}')"
  [[ -n "$expected_sha" ]] || { err "无法获取 Node.js 校验值"; pause_and_exit 1; }

  tmp_dir="$(mktemp -d)"
  pkg_path="$tmp_dir/$pkg_name"
  log "下载官方 Node.js 安装包：$pkg_name"
  curl -fL --retry 3 --retry-delay 2 -o "$pkg_path" "$NODE_DIST_BASE/$pkg_name"
  actual_sha="$(shasum -a 256 "$pkg_path" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || { err "Node.js 安装包校验失败"; rm -rf "$tmp_dir"; pause_and_exit 1; }
  ok "Node.js 安装包校验通过"

  log "开始系统级安装 Node.js（会弹出管理员授权）..."
  run_admin_shell "/usr/sbin/installer -pkg $(shell_quote "$pkg_path") -target /"
  rm -rf "$tmp_dir"
  hash -r

  NODE_BIN="$(command -v node)"
  NPM_BIN="$(command -v npm)"
  NPX_BIN="$(command -v npx)"
  ok "Node.js 已安装：$($NODE_BIN --version)"
  ok "npm 已安装：$($NPM_BIN --version)"
}

show_npm_network_help() {
  local registry="$1"
  err "无法连接 npm 源：$registry"
  warn "这通常是当前网络、DNS 或代理导致的，Codex CLI 还没有开始安装。"
  log "可切换网络、检查代理，或配置可用 npm 镜像源后重新运行安装器。"
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
  if ! curl -fsSL --connect-timeout 8 --max-time 20 -o /dev/null "$registry"; then
    show_npm_network_help "$registry"
    pause_and_exit 1
  fi
}

json_escape() {
  python3 - "$1" <<'PY'
import json, sys
print(json.dumps(sys.argv[1], ensure_ascii=False)[1:-1])
PY
}

load_existing_api_key() {
  local auth_file="$HOME/.codex/auth.json"
  if [[ -f "$auth_file" ]]; then
    EXISTING_API_KEY="$(python3 - "$auth_file" <<'PY'
import json, sys
try:
    obj = json.load(open(sys.argv[1]))
    print(obj.get('OPENAI_API_KEY', ''))
except Exception:
    print('')
PY
)"
  else
    EXISTING_API_KEY=""
  fi
}

prompt_codex_config() {
  load_existing_api_key
  echo
  log "这个安装器会自动使用预设的 Codex 配置。"
  log "只需要输入 OpenAI API Key。"
  log "预设 Base URL：$CODEX_BASE_URL"
  log "预设模型：$DEFAULT_MODEL"
  echo
  if [[ -n "$EXISTING_API_KEY" ]]; then
    read -r -s -p "请输入 OpenAI API Key（直接回车复用当前已保存的 Key）：" CODEX_API_KEY_INPUT
    echo
    CODEX_API_KEY="${CODEX_API_KEY_INPUT:-$EXISTING_API_KEY}"
  else
    read -r -s -p "请输入 OpenAI API Key：" CODEX_API_KEY
    echo
  fi
  [[ -n "$CODEX_API_KEY" ]] || { err "API Key 不能为空。"; pause_and_exit 1; }
}

resolve_codex_api_key() {
  load_existing_api_key
  if [[ -n "$CODEX_API_KEY_FILE" ]]; then
    if [[ -f "$CODEX_API_KEY_FILE" ]]; then
      CODEX_API_KEY="$(cat "$CODEX_API_KEY_FILE")"
      rm -f "$CODEX_API_KEY_FILE"
    else
      err "找不到 API Key 临时文件。"
      pause_and_exit 1
    fi
  fi
  if [[ -n "$CODEX_API_KEY" ]]; then
    return
  fi
  if [[ "$REUSE_SAVED_KEY" == "1" && -n "$EXISTING_API_KEY" ]]; then
    CODEX_API_KEY="$EXISTING_API_KEY"
    return
  fi
  err "API Key 不能为空。"
  pause_and_exit 1
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

install_codex_cli() {
  log "开始系统级安装 Codex CLI..."
  local registry npm_log
  registry="$(get_npm_registry)"
  check_npm_registry_access "$registry"
  npm_log="$(mktemp)"
  if ! run_admin_shell "$(shell_quote "$NPM_BIN") install -g --registry $(shell_quote "$registry") $(shell_quote "$CODEX_PKG")" 2>&1 | tee "$npm_log"; then
    if grep -Eqi 'ENOTFOUND|getaddrinfo|registry\.npmjs\.org|network connectivity|proxy' "$npm_log"; then
      show_npm_network_help "$(get_npm_registry)"
    else
      err "npm 全局安装 Codex CLI 失败。"
      warn "上方是 npm 返回的错误信息，请根据提示处理后重新运行安装器。"
    fi
    rm -f "$npm_log"
    pause_and_exit 1
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] && log "$line"
  done < "$npm_log"
  rm -f "$npm_log"
  hash -r
  ok "Codex CLI：$(codex --version)"
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cp "$file" "$file.bak.$(date +%s)"
  fi
}

write_codex_config() {
  local codex_dir="$HOME/.codex"
  mkdir -p "$codex_dir"

  backup_file "$codex_dir/config.toml"
  backup_file "$codex_dir/auth.json"

  cat > "$codex_dir/config.toml" <<EOF
model_provider = "${CODEX_PROVIDER_NAME}"
model = "${DEFAULT_MODEL}"
review_model = "${DEFAULT_MODEL}"
model_reasoning_effort = "${DEFAULT_REASONING}"
disable_response_storage = true
model_context_window = ${DEFAULT_CONTEXT_WINDOW}
model_auto_compact_token_limit = ${DEFAULT_AUTO_COMPACT_TOKEN_LIMIT}
approval_policy = "${DEFAULT_APPROVAL_POLICY}"
sandbox_mode = "${DEFAULT_SANDBOX_MODE}"
approvals_reviewer = "${DEFAULT_APPROVALS_REVIEWER}"
cli_auth_credentials_store = "file"
forced_login_method = "api"

[model_providers.${CODEX_PROVIDER_NAME}]
name = "${CODEX_PROVIDER_NAME}"
base_url = "${CODEX_BASE_URL}"
wire_api = "responses"
requires_openai_auth = true
EOF

  local escaped_key
  escaped_key="$(json_escape "$CODEX_API_KEY")"
  cat > "$codex_dir/auth.json" <<EOF
{
  "OPENAI_API_KEY": "${escaped_key}"
}
EOF

  ok "已写入 ~/.codex/config.toml 和 ~/.codex/auth.json"
}

verify_everything() {
  log "检查安装结果..."
  [[ -f "$HOME/.codex/config.toml" ]] || { err "未找到 ~/.codex/config.toml"; pause_and_exit 1; }
  [[ -f "$HOME/.codex/auth.json" ]] || { err "未找到 ~/.codex/auth.json"; pause_and_exit 1; }
  ok "Node.js：$($NODE_BIN --version)"
  ok "npm：$($NPM_BIN --version)"
  ok "npx：$($NPX_BIN --version)"
  ok "Codex CLI：$(codex --version)"
  ok "Model：$DEFAULT_MODEL"
  ok "Base URL：$CODEX_BASE_URL"
  ok "Sandbox：$DEFAULT_SANDBOX_MODE / $DEFAULT_APPROVAL_POLICY"
  ok "API Key：$(mask_key "$CODEX_API_KEY")"
  warn "提示：首次执行 codex 时，如服务端策略不同，可能仍会要求重新登录。"
}

run_install() {
  log "官方安装文档：https://developers.openai.com/codex/cli"
  log "日志文件：$LOG_PATH"
  if [[ "$GUI_MODE" == "1" ]]; then
    resolve_codex_api_key
  else
    prompt_codex_config
  fi
  log "已读取 API Key：$(mask_key "$CODEX_API_KEY")"
  install_system_node
  install_codex_cli
  write_codex_config
  verify_everything
  ok "安装完成，现在可以直接输入 codex 使用。"
}

run_gui() {
  local self
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  osascript - "$self" "$LOG_PATH" <<'APPLESCRIPT'
on run argv
  set scriptPath to item 1 of argv
  set logPath to item 2 of argv
  set reuseSaved to false

  set promptText to "请输入 OpenAI API Key。安装器会检测 Node.js、安装 Codex CLI、写入配置并校验结果。"
  set dialogResult to display dialog promptText default answer "" buttons {"取消", "复用已保存 Key", "开始安装"} default button "开始安装" cancel button "取消" with title "OpenAI Codex 安装器" with hidden answer
  set buttonName to button returned of dialogResult
  set apiKey to text returned of dialogResult
  if buttonName is "复用已保存 Key" then
    set reuseSaved to true
  end if
  if apiKey is "" and reuseSaved is false then
    display alert "请输入 OpenAI API Key。" as warning
    return
  end if

  set eventFile to do shell script "mktemp /tmp/codex-installer-events.XXXXXX"
  set quotedScript to quoted form of scriptPath
  set quotedEvent to quoted form of eventFile
  set keyFile to do shell script "mktemp /tmp/codex-installer-key.XXXXXX"
  do shell script "chmod 600 " & quoted form of keyFile
  do shell script "cat > " & quoted form of keyFile & " <<'EOF_KEY'" & linefeed & apiKey & linefeed & "EOF_KEY"
  set quotedKeyFile to quoted form of keyFile
  set reuseArg to ""
  if reuseSaved then set reuseArg to " --reuse-saved-key"
  set cmd to "GUI_EVENT_FILE=" & quotedEvent & " " & quotedScript & " --gui --api-key-file=" & quotedKeyFile & reuseArg & " >/dev/null 2>&1 & echo $!"
  set pidText to do shell script cmd

  set lastSize to 0
  set outputText to "正在安装，请不要关闭窗口..." & linefeed
  repeat
    delay 1
    try
      set newText to do shell script "if [ -f " & quotedEvent & " ]; then tail -c +" & (lastSize + 1) & " " & quotedEvent & "; fi"
      if newText is not "" then
        set outputText to outputText & newText
        set lastSize to (do shell script "wc -c < " & quotedEvent) as integer
      end if
    end try

    try
      do shell script "kill -0 " & pidText
      set stillRunning to true
    on error
      set stillRunning to false
    end try

    if stillRunning is false then exit repeat
  end repeat

  try
    set finalText to do shell script "cat " & quotedEvent
    if finalText is not "" then set outputText to finalText
  end try

  set failed to false
  try
    do shell script "grep -q '^ERROR	' " & quotedEvent
    set failed to true
  end try

  if failed then
    display dialog "安装失败。日志文件：" & logPath & linefeed & linefeed & outputText buttons {"关闭"} default button "关闭" with title "OpenAI Codex 安装器"
  else
    display dialog "安装完成。现在可以在终端输入 codex 使用。" & linefeed & linefeed & outputText buttons {"关闭"} default button "关闭" with title "OpenAI Codex 安装器"
  end if
end run
APPLESCRIPT
}

main() {
  need_command curl
  need_command awk
  need_command shasum
  need_command sed
  need_command grep
  need_command mktemp
  need_command sudo
  need_command python3

  if [[ "$GUI_MODE" == "1" ]]; then
    run_install
    return
  fi

  if [[ "${1:-}" == "--app-gui" ]]; then
    run_gui
    return
  fi

  clear || true
  echo "========================================"
  echo "  $SCRIPT_NAME"
  echo "========================================"
  echo
  run_install
  echo
  pause_and_exit 0
}

main "$@"
