param(
  [string]$TargetHome = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$NodeDistBase = 'https://nodejs.org/dist/latest-jod'
$HelperPkg = '@z_ai/coding-helper'
$ClaudePkg = '@anthropic-ai/claude-code'
$ClaudeInstallerUrl = 'https://downloads.claude.ai/claude-code-releases/bootstrap.ps1'
$DefaultLang = 'zh_CN'
$OldManagedRoot = $null
$SystemNodePrefix = Join-Path ${env:ProgramFiles} 'nodejs'
$LogRoot = Join-Path $env:TEMP 'glm-claude-auto-install-logs'
$LogPath = Join-Path $LogRoot ('install-glm-claude-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$script:ClaudeCmd = ''
$script:ClaudeVersion = ''
$script:TargetHome = if ([string]::IsNullOrWhiteSpace($TargetHome)) {
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $env:USERPROFILE } else { $HOME }
} else {
  [System.IO.Path]::GetFullPath($TargetHome)
}
$script:UserNodePrefix = Join-Path $script:TargetHome 'npm-global'
$OldManagedRoot = Join-Path $script:TargetHome 'AppData\Local\GLM-Coding-Installer'

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Write-LogLine([string]$level, [string]$msg) {
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
  $logParent = Split-Path -Parent $LogPath
  if (-not [string]::IsNullOrWhiteSpace($logParent)) {
    try { New-Item -ItemType Directory -Force -Path $logParent | Out-Null } catch {}
  }
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      Add-Content -Path $LogPath -Encoding UTF8 -Value $line -ErrorAction Stop
      break
    } catch {
      if ($attempt -eq 5) { break }
      Start-Sleep -Milliseconds (80 * $attempt)
    }
  }
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

function ConvertTo-PlainHashtable($value) {
  if ($null -eq $value) { return @{} }
  if ($value -is [hashtable]) { return $value }
  $table = @{}
  foreach ($property in $value.PSObject.Properties) {
    $propertyValue = $property.Value
    if ($propertyValue -is [pscustomobject]) {
      $table[$property.Name] = ConvertTo-PlainHashtable $propertyValue
    } else {
      $table[$property.Name] = $propertyValue
    }
  }
  return $table
}

function Test-SamePath([string]$a, [string]$b) {
  return ($a.TrimEnd('\').ToLowerInvariant() -eq $b.TrimEnd('\').ToLowerInvariant())
}

function Get-TargetUserSid {
  try {
    $target = $script:TargetHome.TrimEnd('\').ToLowerInvariant()
    $profile = Get-CimInstance Win32_UserProfile -ErrorAction Stop |
      Where-Object { $_.LocalPath -and $_.LocalPath.TrimEnd('\').ToLowerInvariant() -eq $target } |
      Select-Object -First 1
    if ($profile -and $profile.SID) { return [string]$profile.SID }
  } catch {
    Write-LogLine 'WARN' ('failed to resolve target user SID: ' + $_.Exception.Message)
  }
  return ''
}

function Get-TargetUserPath {
  $sid = Get-TargetUserSid
  if (-not [string]::IsNullOrWhiteSpace($sid)) {
    try {
      $envKey = "Registry::HKEY_USERS\$sid\Environment"
      if (Test-Path $envKey) {
        $value = (Get-ItemProperty -Path $envKey -Name Path -ErrorAction SilentlyContinue).Path
        if ($value) { return [string]$value }
      }
    } catch {
      Write-LogLine 'WARN' ('failed to read target user PATH: ' + $_.Exception.Message)
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE) -and
      $script:TargetHome.TrimEnd('\').ToLowerInvariant() -eq $env:USERPROFILE.TrimEnd('\').ToLowerInvariant()) {
    return [Environment]::GetEnvironmentVariable('Path', 'User')
  }
  return ''
}

function Set-TargetUserPath([string]$value) {
  $sid = Get-TargetUserSid
  if (-not [string]::IsNullOrWhiteSpace($sid)) {
    try {
      $envKey = "Registry::HKEY_USERS\$sid\Environment"
      New-Item -Path $envKey -Force | Out-Null
      New-ItemProperty -Path $envKey -Name Path -Value $value -PropertyType ExpandString -Force | Out-Null
      return
    } catch {
      Write-LogLine 'WARN' ('failed to write target user PATH: ' + $_.Exception.Message)
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE) -and
      $script:TargetHome.TrimEnd('\').ToLowerInvariant() -eq $env:USERPROFILE.TrimEnd('\').ToLowerInvariant()) {
    [Environment]::SetEnvironmentVariable('Path', $value, 'User')
    return
  }
  Write-WarnMsg '无法持久写入目标用户 PATH，本次安装窗口会临时补齐 PATH。'
}

function Add-TargetUserPathEntry([string]$path) {
  $userPath = Get-TargetUserPath
  $parts = @()
  if (-not [string]::IsNullOrWhiteSpace($userPath)) {
    $parts = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  }
  foreach ($part in $parts) {
    if (Test-SamePath $part $path) { return }
  }
  $next = if ([string]::IsNullOrWhiteSpace($userPath)) { $path } else { $userPath.TrimEnd(';') + ';' + $path }
  Set-TargetUserPath $next
  Write-Ok "已加入用户 PATH：$path"
}

function Refresh-ProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = Get-TargetUserPath
  $env:Path = (@($script:UserNodePrefix, $SystemNodePrefix, $machine, $user) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';'
}

function Clear-TargetNpmCache {
  $cachePath = Join-Path $script:TargetHome 'AppData\Local\npm-cache'
  if (-not ($cachePath.TrimEnd('\').ToLowerInvariant().StartsWith($script:TargetHome.TrimEnd('\').ToLowerInvariant()))) {
    Write-WarnMsg ('跳过 npm cache 清理，路径不在目标用户目录内：' + $cachePath)
    return
  }

  try {
    if (Test-Path $cachePath) {
      Write-WarnMsg ('清理目标用户 npm cache：' + $cachePath)
      Remove-Item -LiteralPath $cachePath -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Force -Path $cachePath | Out-Null
  } catch {
    Write-WarnMsg ('无法清理 npm cache：' + $_.Exception.Message)
  }
}

function Write-TargetNpmPrefix {
  $npmrcPath = Join-Path $script:TargetHome '.npmrc'
  $lines = @()
  if (Test-Path $npmrcPath) {
    $lines = Get-Content -Path $npmrcPath -ErrorAction SilentlyContinue |
      Where-Object { $_ -notmatch '^\s*prefix\s*=' }
  }
  $lines += ('prefix=' + $script:UserNodePrefix)
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($npmrcPath, (($lines -join [Environment]::NewLine) + [Environment]::NewLine), $encoding)
}

function Write-Utf8NoBom([string]$path, [string]$content) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $encoding)
}

function Remove-StaleNpmClaudeCode {
  $paths = @(
    (Join-Path $script:UserNodePrefix 'claude'),
    (Join-Path $script:UserNodePrefix 'claude.cmd'),
    (Join-Path $script:UserNodePrefix 'claude.ps1'),
    (Join-Path $script:UserNodePrefix 'node_modules\@anthropic-ai\claude-code')
  )

  $anthropicRoot = Join-Path $script:UserNodePrefix 'node_modules\@anthropic-ai'
  if (Test-Path $anthropicRoot) {
    $paths += Get-ChildItem -LiteralPath $anthropicRoot -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like '.claude-code-*' } |
      ForEach-Object { $_.FullName }
  }

  foreach ($path in $paths) {
    if (Test-Path $path) {
      try {
        Write-WarnMsg ('移除旧的 npm Claude Code 文件：' + $path)
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
      } catch {
        Write-WarnMsg ('无法移除旧的 npm Claude Code 文件：' + $_.Exception.Message)
      }
    }
  }
}

function Test-ClaudeCommand([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) { return $false }
  try {
    $output = & $path --version 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($output | Out-String))) {
      $script:ClaudeCmd = $path
      $script:ClaudeVersion = (($output | Out-String).Trim() -split "`r?`n" | Select-Object -First 1)
      return $true
    }
  } catch {
    Write-LogLine 'WARN' ('claude command failed: ' + $path + ' :: ' + $_.Exception.Message)
  }
  return $false
}

function Find-ClaudeCommand {
  $candidates = New-Object System.Collections.Generic.List[string]
  $knownPaths = @(
    (Join-Path $script:UserNodePrefix 'claude.cmd'),
    (Join-Path $script:UserNodePrefix 'claude.exe'),
    (Join-Path $script:TargetHome '.local\bin\claude.exe'),
    (Join-Path $script:TargetHome '.local\bin\claude.cmd'),
    (Join-Path $script:TargetHome 'AppData\Local\Programs\Claude\claude.exe'),
    (Join-Path $script:TargetHome 'AppData\Local\Programs\Claude Code\claude.exe'),
    (Join-Path $script:TargetHome 'AppData\Local\Claude\claude.exe')
  )
  foreach ($path in $knownPaths) { $candidates.Add($path) }

  try {
    $found = Get-ChildItem -Path $script:TargetHome -Filter 'claude.exe' -File -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notlike ((Join-Path $script:UserNodePrefix 'node_modules\@anthropic-ai') + '*') } |
      Select-Object -ExpandProperty FullName
    foreach ($path in $found) { $candidates.Add($path) }
  } catch {
    Write-LogLine 'WARN' ('failed to search claude.exe: ' + $_.Exception.Message)
  }

  try {
    $command = Get-Command claude -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { $candidates.Add($command.Source) }
  } catch {}

  foreach ($path in ($candidates | Select-Object -Unique)) {
    if (Test-ClaudeCommand $path) { return $script:ClaudeCmd }
  }
  return ''
}

function Install-ClaudeCodeFromNpm {
  Write-WarnMsg '回退到 npm 安装 Claude Code，并禁用 PowerShell 问题 shim。'
  $script:ClaudeNpmInstallExitCode = 0
  Invoke-WithTargetUserEnvironment {
    & $script:NodeCmds.Npm install -g --no-audit --no-fund --prefix $script:UserNodePrefix $ClaudePkg
    $script:ClaudeNpmInstallExitCode = $LASTEXITCODE
  }
  if ($script:ClaudeNpmInstallExitCode -ne 0) {
    throw 'npm 安装 Claude Code 失败。'
  }

  $psShim = Join-Path $script:UserNodePrefix 'claude.ps1'
  if (Test-Path $psShim) {
    try {
      Remove-Item -LiteralPath $psShim -Force -ErrorAction Stop
      Write-WarnMsg ('已移除 PowerShell Claude shim，避免命中不可执行的 claude.exe：' + $psShim)
    } catch {
      Write-WarnMsg ('无法移除 PowerShell Claude shim：' + $_.Exception.Message)
    }
  }
}

function Install-ClaudeCode {
  Remove-StaleNpmClaudeCode
  Refresh-ProcessPath
  $existing = Find-ClaudeCommand
  if ($existing) {
    Add-TargetUserPathEntry (Split-Path -Parent $existing)
    Refresh-ProcessPath
    Write-Ok ('Claude Code：' + $script:ClaudeVersion)
    return
  }

  Write-Info '开始使用官方 Windows 安装器安装 Claude Code...'
  $installerOk = $false
  try {
    Invoke-WithTargetUserEnvironment {
      $installerPath = Join-Path $env:TEMP ('claude-code-install-' + [guid]::NewGuid().ToString() + '.ps1')
      Invoke-WebRequest -UseBasicParsing -Uri $ClaudeInstallerUrl -OutFile $installerPath
      $installerText = Get-Content -LiteralPath $installerPath -Raw
      if ($installerText -match '<html|<!doctype|<script' -or $installerText -notmatch 'DOWNLOAD_BASE_URL') {
        throw 'Claude Code 官方安装器下载内容不是 PowerShell 脚本。'
      }
      & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installerPath
      if ($LASTEXITCODE -ne 0) {
        throw "Claude Code 官方安装器失败，退出码：$LASTEXITCODE"
      }
      Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
    }
    $installerOk = $true
  } catch {
    Write-WarnMsg ('官方安装器执行失败，尝试使用 winget：' + $_.Exception.Message)
  }

  if (-not $installerOk) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
      & $winget.Source install --id Anthropic.ClaudeCode --exact --silent --scope user --accept-package-agreements --accept-source-agreements
      if ($LASTEXITCODE -ne 0) {
        Write-WarnMsg ("winget 安装 Claude Code 失败，退出码：$LASTEXITCODE")
      } else {
        $installerOk = $true
      }
    } else {
      Write-WarnMsg '未找到 winget。'
    }
  }
  if (-not $installerOk) {
    Install-ClaudeCodeFromNpm
  }
  Refresh-ProcessPath
  $installed = Find-ClaudeCommand
  if (-not $installed) {
    throw 'Claude Code 官方安装器已执行，但未找到可用的 claude 命令。'
  }
  Add-TargetUserPathEntry (Split-Path -Parent $installed)
  Refresh-ProcessPath
  Write-Ok ('Claude Code：' + $script:ClaudeVersion)
}

function Invoke-WithTargetUserEnvironment([scriptblock]$body) {
  $old = @{
    USERPROFILE = $env:USERPROFILE
    HOME = $env:HOME
    APPDATA = $env:APPDATA
    LOCALAPPDATA = $env:LOCALAPPDATA
    npm_config_prefix = $env:npm_config_prefix
    npm_config_cache = $env:npm_config_cache
    npm_config_userconfig = $env:npm_config_userconfig
  }
  try {
    $env:USERPROFILE = $script:TargetHome
    $env:HOME = $script:TargetHome
    $env:APPDATA = Join-Path $script:TargetHome 'AppData\Roaming'
    $env:LOCALAPPDATA = Join-Path $script:TargetHome 'AppData\Local'
    $env:npm_config_prefix = $script:UserNodePrefix
    $env:npm_config_cache = Join-Path $script:TargetHome 'AppData\Local\npm-cache'
    $env:npm_config_userconfig = Join-Path $script:TargetHome '.npmrc'
    New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA, $env:npm_config_cache | Out-Null
    & $body
  } finally {
    foreach ($key in $old.Keys) {
      if ($null -eq $old[$key]) {
        Remove-Item "Env:$key" -ErrorAction SilentlyContinue
      } else {
        Set-Item "Env:$key" $old[$key]
      }
    }
  }
}

function Ensure-Admin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Info '需要管理员权限，正在请求授权...'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '"' + $PSCommandPath + '"')
    $args += '-TargetHome'
    $args += ('"{0}"' -f $script:TargetHome)
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($args -join ' ')
    exit 0
  }
}

function Pick-Plan {
  $script:GlmPlan = 'glm_coding_plan_china'
  $script:ApiValidateUrl = 'https://open.bigmodel.cn/api/coding/paas/v4/models'
  $script:BaseUrl = 'https://open.bigmodel.cn/api/anthropic'
}

function Get-PlainText([Security.SecureString]$secure) {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Load-ExistingApiKey {
  $configPath = Join-Path $script:TargetHome '.chelper\config.yaml'
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
  Refresh-ProcessPath
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
  Write-Info '开始安装 Coding Helper 到目标用户目录...'
  Write-Info ('目标用户目录：' + $script:TargetHome)
  New-Item -ItemType Directory -Force -Path $script:UserNodePrefix | Out-Null
  Write-TargetNpmPrefix
  Add-TargetUserPathEntry $script:UserNodePrefix
  Refresh-ProcessPath
  Clear-TargetNpmCache
  $script:NpmInstallExitCode = 0
  Invoke-WithTargetUserEnvironment {
    & $script:NodeCmds.Npm install -g --no-audit --no-fund --prefix $script:UserNodePrefix $HelperPkg
    $script:NpmInstallExitCode = $LASTEXITCODE
  }
  if ($script:NpmInstallExitCode -ne 0) { throw 'npm 全局安装失败。' }
  Refresh-ProcessPath
  Write-Ok ('Coding Helper：' + (& coding-helper --version))
  Install-ClaudeCode
}

function Remove-OldManagedPathEntries {
  if (-not $OldManagedRoot) { return }
  $userPath = Get-TargetUserPath
  if ([string]::IsNullOrWhiteSpace($userPath)) { return }
  $parts = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $filtered = $parts | Where-Object { $_.ToLower() -notlike ($OldManagedRoot.ToLower() + '*') }
  $newPath = ($filtered -join ';')
  Set-TargetUserPath $newPath
}

function Cleanup-OldManagedInstall {
  if (-not $OldManagedRoot) { return }
  Write-Info '清理旧的本地托管 Node 路径...'
  Remove-OldManagedPathEntries
  if (Test-Path $OldManagedRoot) {
    Remove-Item $OldManagedRoot -Recurse -Force
  }
  Refresh-ProcessPath
  Write-Ok '已清理旧的本地托管目录与用户 PATH 注入'
}

function Backup-File([string]$path) {
  if (Test-Path $path) {
    Copy-Item $path ($path + '.bak.' + [DateTimeOffset]::Now.ToUnixTimeSeconds()) -Force
  }
}

function Write-UserConfigs {
  $chelperDir = Join-Path $script:TargetHome '.chelper'
  $claudeDir = Join-Path $script:TargetHome '.claude'
  New-Item -ItemType Directory -Force -Path $chelperDir | Out-Null
  New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null

  $chelperPath = Join-Path $chelperDir 'config.yaml'
  $settingsPath = Join-Path $claudeDir 'settings.json'
  $claudeJsonPath = Join-Path $script:TargetHome '.claude.json'

  Backup-File $chelperPath
  Backup-File $settingsPath
  Backup-File $claudeJsonPath

  @"
lang: $DefaultLang
plan: $script:GlmPlan
api_key: $script:GlmApiKey
"@ | ForEach-Object { Write-Utf8NoBom $chelperPath ($_ + [Environment]::NewLine) }

  $settings = @{}
  if (Test-Path $settingsPath) {
    $settings = ConvertTo-PlainHashtable (Get-Content $settingsPath -Raw | ConvertFrom-Json)
  }
  if (-not $settings.ContainsKey('env')) { $settings['env'] = @{} }
  $settings['env'].Remove('ANTHROPIC_API_KEY') | Out-Null
  $settings['env']['ANTHROPIC_AUTH_TOKEN'] = $script:GlmApiKey
  $settings['env']['ANTHROPIC_BASE_URL'] = $script:BaseUrl
  $settings['env']['API_TIMEOUT_MS'] = '3000000'
  $settings['env']['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = 1
  Write-Utf8NoBom $settingsPath (($settings | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

  $claudeJson = @{}
  if (Test-Path $claudeJsonPath) {
    $claudeJson = ConvertTo-PlainHashtable (Get-Content $claudeJsonPath -Raw | ConvertFrom-Json)
  }
  $claudeJson['hasCompletedOnboarding'] = $true
  Write-Utf8NoBom $claudeJsonPath (($claudeJson | ConvertTo-Json -Depth 10) + [Environment]::NewLine)

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
  if (-not $script:ClaudeCmd) {
    $null = Find-ClaudeCommand
  }
  Write-Ok ('Claude Code：' + (& $script:ClaudeCmd --version))
  Write-Ok ('套餐：' + $script:GlmPlan)
  Write-Ok ('API Key：' + (Mask-Key $script:GlmApiKey))
}

try {
  Clear-Host
  Write-Host '========================================'
  Write-Host '  GLM Claude Code 一键安装（Windows）'
  Write-Host '========================================'
  Write-Info ('日志文件：' + $LogPath)
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
  Write-LogLine 'ERROR' ($_.ScriptStackTrace | Out-String)
  Pause-AndExit 1
}
