#!/bin/bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_NAME="OpenAI Codex CLI 一键安装（macOS）"
NODE_DIST_BASE="https://nodejs.org/dist/latest-jod"
CODEX_PKG="@openai/codex"
CODEX_PROVIDER_NAME="OpenAI"
CODEX_BASE_URL="https://ai.558669.xyz"
DEFAULT_MODEL="gpt-5.4"
DEFAULT_REASONING="xhigh"
DEFAULT_NETWORK_ACCESS="enabled"
DEFAULT_CONTEXT_WINDOW="1000000"
DEFAULT_AUTO_COMPACT_TOKEN_LIMIT="900000"
DEFAULT_APPROVAL_POLICY="never"
DEFAULT_SANDBOX_MODE="danger-full-access"
DEFAULT_APPROVALS_REVIEWER="user"

log() { printf '🔹 %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
err() { printf '❌ %s\n' "$*" >&2; }
warn() { printf '⚠️  %s\n' "$*"; }

pause_and_exit() {
  local code="${1:-0}"
  echo
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

need_command curl
need_command awk
need_command shasum
need_command sed
need_command grep
need_command mktemp
need_command sudo

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
  sudo installer -pkg "$pkg_path" -target /
  rm -rf "$tmp_dir"
  hash -r

  NODE_BIN="$(command -v node)"
  NPM_BIN="$(command -v npm)"
  NPX_BIN="$(command -v npx)"
  ok "Node.js 已安装：$($NODE_BIN --version)"
  ok "npm 已安装：$($NPM_BIN --version)"
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
  sudo "$NPM_BIN" install -g "$CODEX_PKG"
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
network_access = "${DEFAULT_NETWORK_ACCESS}"
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

  cat > "$codex_dir/auth.json" <<EOF
{
  "OPENAI_API_KEY": "${CODEX_API_KEY}"
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
  ok "API Key：$(mask_key "$CODEX_API_KEY")"
  warn "提示：首次执行 codex 时，如服务端策略不同，可能仍会要求重新登录。"
}

main() {
  clear || true
  echo "========================================"
  echo "  $SCRIPT_NAME"
  echo "========================================"
  echo
  log "官方安装文档：https://developers.openai.com/codex/cli"
  prompt_codex_config
  install_system_node
  install_codex_cli
  write_codex_config
  verify_everything
  echo
  ok "安装完成，现在可以直接输入 codex 使用。"
  pause_and_exit 0
}

main "$@"
