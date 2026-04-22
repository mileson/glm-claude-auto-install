#!/bin/bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_NAME="OpenAI Codex CLI 一键安装（macOS）"
NODE_DIST_BASE="https://nodejs.org/dist/latest-jod"
CODEX_PKG="@openai/codex"
DEFAULT_MODEL="gpt-5.4"
DEFAULT_REASONING="xhigh"

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

prompt_codex_config() {
  echo
  read -r -p "请输入 Codex 代理 Base URL（例如 https://your-host/v1 ）：" CODEX_BASE_URL
  [[ -n "$CODEX_BASE_URL" ]] || { err "Base URL 不能为空。"; pause_and_exit 1; }

  read -r -s -p "请输入 OpenAI API Key：" CODEX_API_KEY
  echo
  [[ -n "$CODEX_API_KEY" ]] || { err "API Key 不能为空。"; pause_and_exit 1; }

  read -r -p "请输入默认模型（默认 ${DEFAULT_MODEL}）：" CODEX_MODEL_INPUT
  CODEX_MODEL="${CODEX_MODEL_INPUT:-$DEFAULT_MODEL}"

  read -r -p "请输入 reasoning effort（默认 ${DEFAULT_REASONING}）：" CODEX_REASONING_INPUT
  CODEX_REASONING="${CODEX_REASONING_INPUT:-$DEFAULT_REASONING}"
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
model_provider = "openai_proxy"
model = "${CODEX_MODEL}"
review_model = "${CODEX_MODEL}"
model_reasoning_effort = "${CODEX_REASONING}"
cli_auth_credentials_store = "file"
forced_login_method = "api"

[model_providers.openai_proxy]
name = "OpenAI Compatible Proxy"
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
  ok "Model：$CODEX_MODEL"
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
