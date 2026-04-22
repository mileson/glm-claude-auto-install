$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$OldManagedRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'GLM-Coding-Installer' } else { $null }

function Write-Info($msg) { Write-Host "🔹 $msg" }
function Write-Ok($msg) { Write-Host "✅ $msg" }
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

function Remove-OldManagedPathEntries {
  if (-not $OldManagedRoot) { return }
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ([string]::IsNullOrWhiteSpace($userPath)) { return }
  $parts = $userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  $filtered = $parts | Where-Object { $_.ToLower() -notlike ($OldManagedRoot.ToLower() + '*') }
  [Environment]::SetEnvironmentVariable('Path', ($filtered -join ';'), 'User')
}

function Get-SystemCommandPath([string]$name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) { return $null }
  if ($OldManagedRoot -and $cmd.Source.ToLower().Contains($OldManagedRoot.ToLower())) { return $null }
  return $cmd.Source
}

function Test-SystemInstallReady {
  $script:SystemNode = Get-SystemCommandPath 'node'
  $script:SystemNpm = Get-SystemCommandPath 'npm'
  $script:SystemNpx = Get-SystemCommandPath 'npx'
  $script:SystemClaude = Get-SystemCommandPath 'claude'
  return ($null -ne $script:SystemNode -and $null -ne $script:SystemNpm -and $null -ne $script:SystemNpx -and $null -ne $script:SystemClaude)
}

try {
  Clear-Host
  Write-Host '========================================'
  Write-Host '  清理旧的本地托管 GLM Node 安装（Windows）'
  Write-Host '========================================'

  if (-not $OldManagedRoot) {
    throw '未检测到 LOCALAPPDATA，无法定位旧托管目录。'
  }

  Ensure-Admin

  if (-not (Test-SystemInstallReady)) {
    throw '还没有检测到系统级 Node + Claude。请先运行 scripts\\windows\\install-glm-claude.bat 完成系统级安装。'
  }

  Write-Info '检测到系统级环境：'
  Write-Ok ('node -> ' + $script:SystemNode)
  Write-Ok ('npm -> ' + $script:SystemNpm)
  Write-Ok ('npx -> ' + $script:SystemNpx)
  Write-Ok ('claude -> ' + $script:SystemClaude)

  Remove-OldManagedPathEntries

  if (Test-Path $OldManagedRoot) {
    Remove-Item $OldManagedRoot -Recurse -Force
    Write-Ok ('已移除旧目录：' + $OldManagedRoot)
  } else {
    Write-Ok '旧托管目录不存在，无需删除'
  }

  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
  Write-Ok '已清理用户 PATH 中旧托管路径'
  Pause-AndExit 0
} catch {
  Write-Err $_.Exception.Message
  Pause-AndExit 1
}
