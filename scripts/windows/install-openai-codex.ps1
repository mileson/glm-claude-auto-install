$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$NodeDistBase = 'https://nodejs.org/dist/latest-jod'
$CodexPkg = '@openai/codex'
$CodexProviderName = 'OpenAI'
$CodexBaseUrl = 'https://ai.558669.xyz'
$DefaultModel = 'gpt-5.4'
$DefaultReasoning = 'xhigh'
$DefaultNetworkAccess = 'enabled'
$DefaultContextWindow = '1000000'
$DefaultAutoCompactTokenLimit = '900000'
$DefaultApprovalPolicy = 'never'
$DefaultSandboxMode = 'danger-full-access'
$DefaultApprovalsReviewer = 'user'
$SystemNodePrefix = Join-Path ${env:ProgramFiles} 'nodejs'
$LogRoot = Join-Path $env:TEMP 'glm-claude-auto-install-logs'
$LogPath = Join-Path $LogRoot ('install-openai-codex-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Write-LogLine([string]$level, [string]$msg) {
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
  Add-Content -Path $LogPath -Encoding UTF8 -Value $line
}

function Write-Info($msg) { Write-Host "🔹 $msg"; Write-LogLine 'INFO' $msg }
function Write-Ok($msg) { Write-Host "✅ $msg"; Write-LogLine 'OK' $msg }
function Write-WarnMsg($msg) { Write-Host "⚠️  $msg"; Write-LogLine 'WARN' $msg }
function Write-Err($msg) { Write-Host "❌ $msg" -ForegroundColor Red; Write-LogLine 'ERROR' $msg }

function Pause-AndExit([int]$code = 0) {
  Write-Host ''
  Write-Host ('日志文件：' + $LogPath)
  Read-Host '按回车键关闭窗口' | Out-Null
  exit $code
}

function Ensure-Admin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Info '需要管理员权限，正在请求授权...'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '"' + $PSCommandPath + '"')
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($args -join ' ')
    exit 0
  }
}

function Get-NodeCommands {
  $node = Get-Command node -ErrorAction SilentlyContinue
  $npm = Get-Command npm -ErrorAction SilentlyContinue
  $npx = Get-Command npx -ErrorAction SilentlyContinue
  if ($node -and $npm -and $npx) {
    $versionText = (& $node.Source --version).Trim()
    $major = [int]($versionText.TrimStart('v').Split('.')[0])
    if ($major -ge 18) {
      return @{ Node = $node.Source; Npm = $npm.Source; Npx = $npx.Source; Version = $versionText }
    }
  }
  return $null
}

function Install-SystemNode {
  $cmds = Get-NodeCommands
  if ($cmds) {
    Write-Ok "检测到可用 Node.js：$($cmds.Version)"
    $script:NodeCmds = $cmds
    return
  }

  Write-Info '未检测到可用 Node.js，开始系统级安装...'
  $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'arm64' } else { 'x64' }
  $checksums = Invoke-WebRequest -UseBasicParsing -Uri "$NodeDistBase/SHASUMS256.txt"
  $msiName = [regex]::Matches($checksums.Content, "node-v[0-9.]+-$arch\.msi") | Select-Object -First 1 | ForEach-Object { $_.Value }
  if (-not $msiName) { throw '无法找到适配当前系统的 Node.js MSI 包。' }
  $expectedSha = ($checksums.Content -split "`n" | Where-Object { $_ -match [regex]::Escape($msiName) } | Select-Object -First 1).Trim().Split()[0].ToLower()
  $tmpDir = Join-Path $env:TEMP ('codex-node-' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $tmpDir | Out-Null
  $msiPath = Join-Path $tmpDir $msiName
  Write-Info "下载官方 Node.js 安装包：$msiName"
  Invoke-WebRequest -UseBasicParsing -Uri "$NodeDistBase/$msiName" -OutFile $msiPath
  $actualSha = (Get-FileHash -Algorithm SHA256 -Path $msiPath).Hash.ToLower()
  if ($actualSha -ne $expectedSha) { throw 'Node.js 安装包校验失败。' }
  Write-Ok 'Node.js 安装包校验通过'
  Write-Info '开始系统级安装 Node.js...'
  $proc = Start-Process msiexec.exe -ArgumentList @('/i', '"' + $msiPath + '"', '/qn', '/norestart') -Wait -PassThru
  if ($proc.ExitCode -ne 0) { throw "msiexec 安装失败，退出码：$($proc.ExitCode)" }
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  $script:NodeCmds = Get-NodeCommands
  if (-not $script:NodeCmds) {
    $defaultDir = 'C:\Program Files\nodejs'
    $script:NodeCmds = @{
      Node = (Join-Path $defaultDir 'node.exe')
      Npm  = (Join-Path $defaultDir 'npm.cmd')
      Npx  = (Join-Path $defaultDir 'npx.cmd')
      Version = (& (Join-Path $defaultDir 'node.exe') --version).Trim()
    }
  }
  Write-Ok "Node.js 已安装：$($script:NodeCmds.Version)"
}

function Prompt-CodexConfig {
  $existingKey = ''
  $authPath = Join-Path $HOME '.codex\auth.json'
  if (Test-Path $authPath) {
    try {
      $auth = Get-Content $authPath -Raw | ConvertFrom-Json
      if ($auth.PSObject.Properties.Name -contains 'OPENAI_API_KEY') {
        $existingKey = [string]$auth.OPENAI_API_KEY
      }
    } catch {
    }
  }

  Write-Info '这个安装器会自动使用预设的 Codex 配置。'
  Write-Info '只需要输入 OpenAI API Key。'
  Write-Info ('预设 Base URL：' + $CodexBaseUrl)
  Write-Info ('预设模型：' + $DefaultModel)

  if ([string]::IsNullOrWhiteSpace($existingKey)) {
    $secure = Read-Host '请输入 OpenAI API Key' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $script:CodexApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr).Trim() }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  } else {
    $plain = Read-Host '请输入 OpenAI API Key（直接回车复用当前已保存的 Key）'
    if ([string]::IsNullOrWhiteSpace($plain)) { $script:CodexApiKey = $existingKey } else { $script:CodexApiKey = $plain.Trim() }
  }

  if ([string]::IsNullOrWhiteSpace($script:CodexApiKey)) { throw 'API Key 不能为空。' }
}

function Install-CodexCli {
  Write-Info '开始系统级安装 Codex CLI...'
  & $script:NodeCmds.Npm install -g --prefix $SystemNodePrefix $CodexPkg
  if ($LASTEXITCODE -ne 0) { throw 'npm 全局安装 Codex CLI 失败。' }
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  Write-Ok ('Codex CLI：' + (& codex --version))
}

function Backup-File([string]$path) {
  if (Test-Path $path) {
    Copy-Item $path ($path + '.bak.' + [DateTimeOffset]::Now.ToUnixTimeSeconds()) -Force
  }
}

function Write-CodexConfig {
  $codexDir = Join-Path $HOME '.codex'
  New-Item -ItemType Directory -Force -Path $codexDir | Out-Null

  $configPath = Join-Path $codexDir 'config.toml'
  $authPath = Join-Path $codexDir 'auth.json'
  Backup-File $configPath
  Backup-File $authPath

  @"
model_provider = "$CodexProviderName"
model = "$DefaultModel"
review_model = "$DefaultModel"
model_reasoning_effort = "$DefaultReasoning"
disable_response_storage = true
network_access = "$DefaultNetworkAccess"
windows_wsl_setup_acknowledged = true
model_context_window = $DefaultContextWindow
model_auto_compact_token_limit = $DefaultAutoCompactTokenLimit
approval_policy = "$DefaultApprovalPolicy"
sandbox_mode = "$DefaultSandboxMode"
approvals_reviewer = "$DefaultApprovalsReviewer"
cli_auth_credentials_store = "file"
forced_login_method = "api"

[model_providers.$CodexProviderName]
name = "$CodexProviderName"
base_url = "$CodexBaseUrl"
wire_api = "responses"
requires_openai_auth = true
"@ | Set-Content -Path $configPath -Encoding UTF8

  @{
    OPENAI_API_KEY = $script:CodexApiKey
  } | ConvertTo-Json -Depth 5 | Set-Content -Path $authPath -Encoding UTF8

  Write-Ok '已写入 ~/.codex/config.toml 和 ~/.codex/auth.json'
}

function Mask-Key([string]$key) {
  if ($key.Length -le 8) { return '********' }
  return $key.Substring(0,4) + ('*' * ($key.Length - 8)) + $key.Substring($key.Length - 4)
}

function Verify-Everything {
  $configPath = Join-Path $HOME '.codex\config.toml'
  $authPath = Join-Path $HOME '.codex\auth.json'
  if (-not (Test-Path $configPath)) { throw '未找到 ~/.codex/config.toml' }
  if (-not (Test-Path $authPath)) { throw '未找到 ~/.codex/auth.json' }
  Write-Ok ('Node.js：' + (& $script:NodeCmds.Node --version))
  Write-Ok ('npm：' + (& $script:NodeCmds.Npm --version))
  Write-Ok ('npx：' + (& $script:NodeCmds.Npx --version))
  Write-Ok ('Codex CLI：' + (& codex --version))
  Write-Ok ('Model：' + $DefaultModel)
  Write-Ok ('Base URL：' + $CodexBaseUrl)
  Write-Ok ('API Key：' + (Mask-Key $script:CodexApiKey))
  Write-WarnMsg '提示：Windows 对 Codex CLI 属于实验性支持，首次执行 codex 时如服务端策略不同，可能仍会要求重新登录。'
}

try {
  Clear-Host
  Write-Host '========================================'
  Write-Host '  OpenAI Codex CLI 一键安装（Windows）'
  Write-Host '========================================'
  Write-Info ('日志文件：' + $LogPath)
  Write-WarnMsg '官方当前主推 macOS / Linux，Windows 建议优先在 WSL2 中使用。'
  Write-Info '官方安装文档：https://developers.openai.com/codex/cli'
  Ensure-Admin
  Prompt-CodexConfig
  Install-SystemNode
  Install-CodexCli
  Write-CodexConfig
  Verify-Everything
  Write-Host ''
  Write-Ok '安装完成，现在可以直接输入 codex 使用。'
  Pause-AndExit 0
} catch {
  Write-Err $_.Exception.Message
  Write-LogLine 'ERROR' ($_.ScriptStackTrace | Out-String)
  Pause-AndExit 1
}
