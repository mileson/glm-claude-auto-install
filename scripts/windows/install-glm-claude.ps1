$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$NodeDistBase = 'https://nodejs.org/dist/latest-jod'
$HelperPkg = '@z_ai/coding-helper'
$ClaudePkg = '@anthropic-ai/claude-code'
$DefaultLang = 'zh_CN'
$OldManagedRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'GLM-Coding-Installer' } else { $null }
$SystemNodePrefix = Join-Path ${env:ProgramFiles} 'nodejs'

function Write-Info($msg) { Write-Host "🔹 $msg" }
function Write-Ok($msg) { Write-Host "✅ $msg" }
function Write-WarnMsg($msg) { Write-Host "⚠️  $msg" }
function Write-Err($msg) { Write-Host "❌ $msg" -ForegroundColor Red }

function Pause-AndExit([int]$code = 0) {
  Write-Host ''
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

function Pick-Plan {
  Write-Host ''
  Write-Host '请选择套餐：'
  Write-Host '  1) 中国站（默认）'
  Write-Host '  2) Global'
  $choice = Read-Host '请输入 1 或 2，直接回车默认 1'
  if ($choice -eq '2') {
    $script:GlmPlan = 'glm_coding_plan_global'
    $script:ApiValidateUrl = 'https://api.z.ai/api/coding/paas/v4/models'
    $script:BaseUrl = 'https://api.z.ai/api/anthropic'
  } else {
    $script:GlmPlan = 'glm_coding_plan_china'
    $script:ApiValidateUrl = 'https://open.bigmodel.cn/api/coding/paas/v4/models'
    $script:BaseUrl = 'https://open.bigmodel.cn/api/anthropic'
  }
}

function Get-PlainText([Security.SecureString]$secure) {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Load-ExistingApiKey {
  $configPath = Join-Path $HOME '.chelper\config.yaml'
  if (Test-Path $configPath) {
    $line = Select-String -Path $configPath -Pattern '^api_key:\s*(.+)$' | Select-Object -Last 1
    if ($line) { return $line.Matches[0].Groups[1].Value.Trim('"') }
  }
  return ''
}

function Prompt-ApiKey {
  $existing = Load-ExistingApiKey
  if ($existing) {
    $plain = Read-Host '请输入 API Key（直接回车复用已保存的 Key）'
    if ([string]::IsNullOrWhiteSpace($plain)) { $script:GlmApiKey = $existing } else { $script:GlmApiKey = $plain.Trim() }
  } else {
    $secure = Read-Host '请输入 API Key' -AsSecureString
    $script:GlmApiKey = (Get-PlainText $secure).Trim()
  }
  if ([string]::IsNullOrWhiteSpace($script:GlmApiKey)) {
    throw 'API Key 不能为空。'
  }
}

function Mask-Key([string]$key) {
  if ($key.Length -le 8) { return '********' }
  return $key.Substring(0,4) + ('*' * ($key.Length - 8)) + $key.Substring($key.Length - 4)
}

function Validate-ApiKey {
  Write-Info '校验 API Key...'
  try {
    $resp = Invoke-RestMethod -Method Get -Uri $script:ApiValidateUrl -Headers @{ Authorization = "Bearer $($script:GlmApiKey)" }
    if ($resp.object -ne 'list' -and $null -eq $resp.data) {
      throw '接口返回格式异常。'
    }
    Write-Ok 'API Key 校验通过'
  } catch {
    throw "API Key 校验失败：$($_.Exception.Message)"
  }
}

function Get-NodeCommands {
  $node = Get-Command node -ErrorAction SilentlyContinue
  $npm = Get-Command npm -ErrorAction SilentlyContinue
  $npx = Get-Command npx -ErrorAction SilentlyContinue
  if ($node -and $npm -and $npx) {
    if ($OldManagedRoot) {
      $joined = @($node.Source, $npm.Source, $npx.Source) -join ';'
      if ($joined.ToLower().Contains($OldManagedRoot.ToLower())) {
        return $null
      }
    }
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
  $tmpDir = Join-Path $env:TEMP ('glm-node-' + [guid]::NewGuid().ToString())
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

function Install-GlobalTools {
  Write-Info '开始系统级安装 Coding Helper 和 Claude Code...'
  & $script:NodeCmds.Npm install -g --prefix $SystemNodePrefix $HelperPkg $ClaudePkg
  if ($LASTEXITCODE -ne 0) { throw 'npm 全局安装失败。' }
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  Write-Ok ('Coding Helper：' + (& coding-helper --version))
  Write-Ok ('Claude Code：' + (& claude --version))
}

function Remove-OldManagedPathEntries {
  if (-not $OldManagedRoot) { return }
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ([string]::IsNullOrWhiteSpace($userPath)) { return }
  $parts = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $filtered = $parts | Where-Object { $_.ToLower() -notlike ($OldManagedRoot.ToLower() + '*') }
  $newPath = ($filtered -join ';')
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}

function Cleanup-OldManagedInstall {
  if (-not $OldManagedRoot) { return }
  Write-Info '清理旧的本地托管 Node 路径...'
  Remove-OldManagedPathEntries
  if (Test-Path $OldManagedRoot) {
    Remove-Item $OldManagedRoot -Recurse -Force
  }
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  Write-Ok '已清理旧的本地托管目录与用户 PATH 注入'
}

function Backup-File([string]$path) {
  if (Test-Path $path) {
    Copy-Item $path ($path + '.bak.' + [DateTimeOffset]::Now.ToUnixTimeSeconds()) -Force
  }
}

function Write-UserConfigs {
  $chelperDir = Join-Path $HOME '.chelper'
  $claudeDir = Join-Path $HOME '.claude'
  New-Item -ItemType Directory -Force -Path $chelperDir | Out-Null
  New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null

  $chelperPath = Join-Path $chelperDir 'config.yaml'
  $settingsPath = Join-Path $claudeDir 'settings.json'
  $claudeJsonPath = Join-Path $HOME '.claude.json'

  Backup-File $chelperPath
  Backup-File $settingsPath
  Backup-File $claudeJsonPath

  @"
lang: $DefaultLang
plan: $script:GlmPlan
api_key: $script:GlmApiKey
"@ | Set-Content -Path $chelperPath -Encoding UTF8

  $settings = @{}
  if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable
  }
  if (-not $settings.ContainsKey('env')) { $settings['env'] = @{} }
  $settings['env'].Remove('ANTHROPIC_API_KEY') | Out-Null
  $settings['env']['ANTHROPIC_AUTH_TOKEN'] = $script:GlmApiKey
  $settings['env']['ANTHROPIC_BASE_URL'] = $script:BaseUrl
  $settings['env']['API_TIMEOUT_MS'] = '3000000'
  $settings['env']['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = 1
  $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8

  $claudeJson = @{}
  if (Test-Path $claudeJsonPath) {
    $claudeJson = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json -AsHashtable
  }
  $claudeJson['hasCompletedOnboarding'] = $true
  $claudeJson | ConvertTo-Json -Depth 10 | Set-Content -Path $claudeJsonPath -Encoding UTF8

  Write-Ok '已写入用户配置'
}

function Verify-Everything {
  Write-Info '运行健康检查...'
  try { & coding-helper doctor } catch { Write-WarnMsg 'doctor 执行失败，但不影响已完成的安装。' }
  Write-Host ''
  Write-Ok ('Node.js：' + (& $script:NodeCmds.Node --version))
  Write-Ok ('npm：' + (& $script:NodeCmds.Npm --version))
  Write-Ok ('npx：' + (& $script:NodeCmds.Npx --version))
  Write-Ok ('Coding Helper：' + (& coding-helper --version))
  Write-Ok ('Claude Code：' + (& claude --version))
  Write-Ok ('套餐：' + $script:GlmPlan)
  Write-Ok ('API Key：' + (Mask-Key $script:GlmApiKey))
}

try {
  Clear-Host
  Write-Host '========================================'
  Write-Host '  GLM Claude Code 一键安装（Windows）'
  Write-Host '========================================'
  Ensure-Admin
  Pick-Plan
  Prompt-ApiKey
  Write-Info ('已读取 API Key：' + (Mask-Key $script:GlmApiKey))
  Validate-ApiKey
  Install-SystemNode
  Install-GlobalTools
  Write-UserConfigs
  Cleanup-OldManagedInstall
  Verify-Everything
  Write-Host ''
  Write-Ok '安装完成，现在可以直接输入 claude 使用。'
  Pause-AndExit 0
} catch {
  Write-Err $_.Exception.Message
  Pause-AndExit 1
}
