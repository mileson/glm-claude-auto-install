param(
  [switch]$Console,
  [switch]$WorkerInstall,
  [string]$ApiKey = '',
  [string]$ApiKeyFile = '',
  [switch]$ReuseSavedKey,
  [string]$DiagnosticPath = '',
  [string]$RuntimeLogPath = '',
  [string]$TargetHome = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$NodeDistBase = 'https://nodejs.org/dist/latest-jod'
$CodexPkg = '@openai/codex'
$CodexProviderName = 'OpenAI'
$CodexBaseUrl = 'https://ai.558669.xyz'
$DefaultModel = 'gpt-5.5'
$DefaultReasoning = 'xhigh'
$SystemNodePrefix = Join-Path ${env:ProgramFiles} 'nodejs'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$LogRoot = Join-Path $env:TEMP 'glm-claude-auto-install-logs'
$LogPath = if ([string]::IsNullOrWhiteSpace($RuntimeLogPath)) {
  Join-Path $LogRoot ('install-openai-codex-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
} else {
  $RuntimeLogPath
}
$DiagnosticLogPath = if ([string]::IsNullOrWhiteSpace($DiagnosticPath)) {
  Join-Path $PSScriptRoot 'OpenAI-Codex-Install-Diagnostic.md'
} else {
  $DiagnosticPath
}
$script:LogCallback = $null
$script:TargetHome = if ([string]::IsNullOrWhiteSpace($TargetHome)) {
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $env:USERPROFILE } else { $HOME }
} else {
  [System.IO.Path]::GetFullPath($TargetHome)
}
$script:UserNodePrefix = Join-Path $script:TargetHome 'npm-global'

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

function Write-Diagnostic([string]$text) {
  try {
    Add-Content -Path $DiagnosticLogPath -Encoding UTF8 -Value $text
  } catch {
    # Diagnostic logging must never prevent the installer from running.
  }
}

function Write-DiagnosticSection([string]$title) {
  Write-Diagnostic ''
  Write-Diagnostic "## $title"
}

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
  Write-Diagnostic "- $line"
}

function Publish-Log([string]$level, [string]$msg) {
  $prefix = switch ($level) {
    'OK' { '[OK]' }
    'WARN' { '[WARN]' }
    'ERROR' { '[ERROR]' }
    default { '[INFO]' }
  }
  if ($level -eq 'ERROR') {
    Write-Host "$prefix $msg" -ForegroundColor Red
  } else {
    Write-Host "$prefix $msg"
  }
  Write-LogLine $level $msg
  if ($script:LogCallback) {
    & $script:LogCallback $level $msg
  }
}

function Write-Info($msg) { Publish-Log 'INFO' $msg }
function Write-Ok($msg) { Publish-Log 'OK' $msg }
function Write-WarnMsg($msg) { Publish-Log 'WARN' $msg }
function Write-Err($msg) { Publish-Log 'ERROR' $msg }

function Write-Utf8NoBom([string]$path, [string]$content) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $content, $encoding)
}

function Quote-ProcessArg([string]$value) {
  if ($null -eq $value) { return '""' }
  $escaped = New-Object System.Text.StringBuilder
  $slashes = 0
  foreach ($ch in $value.ToCharArray()) {
    if ($ch -eq '\') {
      $slashes += 1
      continue
    }
    if ($ch -eq '"') {
      [void]$escaped.Append(('\' * (($slashes * 2) + 1)))
      [void]$escaped.Append('"')
      $slashes = 0
      continue
    }
    if ($slashes -gt 0) {
      [void]$escaped.Append(('\' * $slashes))
      $slashes = 0
    }
    [void]$escaped.Append($ch)
  }
  if ($slashes -gt 0) {
    [void]$escaped.Append(('\' * ($slashes * 2)))
  }
  return '"' + $escaped.ToString() + '"'
}

function Pause-AndExit([int]$code = 0) {
  Write-Host ''
  Write-Host ('Log file: ' + $LogPath)
  Write-Host ('Diagnostic log: ' + $DiagnosticLogPath)
  if ($Console) {
    Read-Host 'Press Enter to close' | Out-Null
  }
  exit $code
}

function Ensure-Admin {
  Write-DiagnosticSection 'PowerShell process'
  Write-Diagnostic ('- Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
  Write-Diagnostic ('- Script path: ' + $PSCommandPath)
  Write-Diagnostic ('- PowerShell version: ' + $PSVersionTable.PSVersion.ToString())
  Write-Diagnostic ('- OS: ' + [Environment]::OSVersion.VersionString)
  Write-Diagnostic ('- Working directory: ' + (Get-Location).Path)
  Write-Diagnostic ('- Diagnostic log: ' + $DiagnosticLogPath)

  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Info 'Administrator permission is required. Requesting elevation...'
    $args = @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath))
    if ($Console) { $args += '-Console' }
    if ($WorkerInstall) { $args += '-WorkerInstall' }
    if ($ReuseSavedKey) { $args += '-ReuseSavedKey' }
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
      $args += '-ApiKey'
      $args += (Quote-ProcessArg $ApiKey)
    }
    if (-not [string]::IsNullOrWhiteSpace($ApiKeyFile)) {
      $args += '-ApiKeyFile'
      $args += ('"{0}"' -f $ApiKeyFile)
    }
    $args += '-DiagnosticPath'
    $args += ('"{0}"' -f $DiagnosticLogPath)
    if (-not [string]::IsNullOrWhiteSpace($RuntimeLogPath)) {
      $args += '-RuntimeLogPath'
      $args += ('"{0}"' -f $RuntimeLogPath)
    }
    $args += '-TargetHome'
    $args += ('"{0}"' -f $script:TargetHome)
    Write-Diagnostic '- Stage: requesting administrator permission.'
    Write-Diagnostic ('- Elevated PowerShell path: ' + $PowerShellExe)
    Start-Process $PowerShellExe -Verb RunAs -ArgumentList ($args -join ' ')
    exit 0
  }
  Write-Diagnostic '- Stage: already running as administrator.'
}

function Get-PlainText([Security.SecureString]$secure) {
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Test-SamePath([string]$a, [string]$b) {
  return ($a.TrimEnd('\').ToLowerInvariant() -eq $b.TrimEnd('\').ToLowerInvariant())
}

function Add-MachinePathEntry([string]$path) {
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $parts = @()
  if (-not [string]::IsNullOrWhiteSpace($machinePath)) {
    $parts = $machinePath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  }
  $exists = $false
  foreach ($part in $parts) {
    if (Test-SamePath $part $path) {
      $exists = $true
      break
    }
  }
  if (-not $exists) {
    $next = if ([string]::IsNullOrWhiteSpace($machinePath)) { $path } else { $machinePath.TrimEnd(';') + ';' + $path }
    [Environment]::SetEnvironmentVariable('Path', $next, 'Machine')
    Write-Ok "Added to system PATH: $path"
  }
}

function Get-TargetUserSid {
  try {
    $target = $script:TargetHome.TrimEnd('\').ToLowerInvariant()
    $profile = Get-CimInstance Win32_UserProfile -ErrorAction Stop |
      Where-Object { $_.LocalPath -and $_.LocalPath.TrimEnd('\').ToLowerInvariant() -eq $target } |
      Select-Object -First 1
    if ($profile -and $profile.SID) { return [string]$profile.SID }
  } catch {
    Write-Diagnostic ('- Warning: failed to resolve target user SID: ' + $_.Exception.Message)
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
      Write-Diagnostic ('- Warning: failed to read target user PATH: ' + $_.Exception.Message)
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
      Write-Diagnostic ('- Warning: failed to write target user PATH: ' + $_.Exception.Message)
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE) -and
      $script:TargetHome.TrimEnd('\').ToLowerInvariant() -eq $env:USERPROFILE.TrimEnd('\').ToLowerInvariant()) {
    [Environment]::SetEnvironmentVariable('Path', $value, 'User')
    return
  }
  Write-WarnMsg 'Could not persist the target user PATH. The launcher will still add Codex to PATH for this session.'
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
  Write-Ok "Added to user PATH: $path"
}

function Refresh-ProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = Get-TargetUserPath
  $env:Path = (@($script:UserNodePrefix, $SystemNodePrefix, $machine, $user) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ';'
}

function Resolve-NodeSiblingCommand([string]$nodePath, [string]$commandName) {
  if (-not [string]::IsNullOrWhiteSpace($nodePath)) {
    $dir = Split-Path -Parent $nodePath
    foreach ($ext in @('.cmd', '.exe', '.bat')) {
      $candidate = Join-Path $dir ($commandName + $ext)
      if (Test-Path $candidate) { return $candidate }
    }
  }
  foreach ($cmd in (Get-Command $commandName -All -ErrorAction SilentlyContinue)) {
    if ($cmd.Source -and $cmd.Source.ToLowerInvariant().EndsWith('.cmd')) { return $cmd.Source }
  }
  foreach ($cmd in (Get-Command $commandName -All -ErrorAction SilentlyContinue)) {
    if ($cmd.Source -and -not $cmd.Source.ToLowerInvariant().EndsWith('.ps1')) { return $cmd.Source }
  }
  return $null
}

function Resolve-NpmCliPath([string]$npmPath) {
  if ([string]::IsNullOrWhiteSpace($npmPath)) { return $null }
  $npmDir = Split-Path -Parent $npmPath
  foreach ($candidate in @(
    (Join-Path $npmDir 'node_modules\npm\bin\npm-cli.js'),
    (Join-Path $npmDir '..\node_modules\npm\bin\npm-cli.js')
  )) {
    $resolved = [System.IO.Path]::GetFullPath($candidate)
    if (Test-Path $resolved) { return $resolved }
  }
  return $null
}

function Get-NodeCommands {
  Refresh-ProcessPath
  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($node) {
    $versionText = (& $node.Source --version).Trim()
    $major = [int]($versionText.TrimStart('v').Split('.')[0])
    if ($major -ge 18) {
      $npm = Resolve-NodeSiblingCommand $node.Source 'npm'
      $npx = Resolve-NodeSiblingCommand $node.Source 'npx'
      if ($npm -and $npx) {
        return @{ Node = $node.Source; Npm = $npm; Npx = $npx; NpmCli = (Resolve-NpmCliPath $npm); Version = $versionText }
      }
    }
  }
  return $null
}

function Install-SystemNode {
  $cmds = Get-NodeCommands
  if ($cmds) {
    Write-Ok "Detected Node.js: $($cmds.Version)"
    $script:NodeCmds = $cmds
    return
  }

  Write-Info 'Node.js was not found. Installing system Node.js...'
  $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'arm64' } else { 'x64' }
  $checksums = Invoke-WebRequest -UseBasicParsing -Uri "$NodeDistBase/SHASUMS256.txt"
  $msiName = [regex]::Matches($checksums.Content, "node-v[0-9.]+-$arch\.msi") | Select-Object -First 1 | ForEach-Object { $_.Value }
  if (-not $msiName) { throw 'Could not find a Node.js MSI package for this system.' }
  $expectedSha = ($checksums.Content -split "`n" | Where-Object { $_ -match [regex]::Escape($msiName) } | Select-Object -First 1).Trim().Split()[0].ToLower()
  $tmpDir = Join-Path $env:TEMP ('codex-node-' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Path $tmpDir | Out-Null
  $msiPath = Join-Path $tmpDir $msiName
  Write-Info "Downloading official Node.js installer: $msiName"
  Invoke-WebRequest -UseBasicParsing -Uri "$NodeDistBase/$msiName" -OutFile $msiPath
  $actualSha = (Get-FileHash -Algorithm SHA256 -Path $msiPath).Hash.ToLower()
  if ($actualSha -ne $expectedSha) { throw 'Node.js installer checksum verification failed.' }
  Write-Ok 'Node.js installer checksum verified.'
  Write-Info 'Installing Node.js for all users...'
  $proc = Start-Process msiexec.exe -ArgumentList @('/i', '"' + $msiPath + '"', '/qn', '/norestart') -Wait -PassThru
  if ($proc.ExitCode -ne 0) { throw "msiexec failed with exit code: $($proc.ExitCode)" }
  Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
  Refresh-ProcessPath
  $script:NodeCmds = Get-NodeCommands
  if (-not $script:NodeCmds) {
    $defaultDir = 'C:\Program Files\nodejs'
    $script:NodeCmds = @{
      Node = (Join-Path $defaultDir 'node.exe')
      Npm  = (Join-Path $defaultDir 'npm.cmd')
      Npx  = (Join-Path $defaultDir 'npx.cmd')
      NpmCli = (Join-Path $defaultDir 'node_modules\npm\bin\npm-cli.js')
      Version = (& (Join-Path $defaultDir 'node.exe') --version).Trim()
    }
  }
  Write-Ok "Node.js installed: $($script:NodeCmds.Version)"
}

function Get-InstalledCodexCommand {
  Refresh-ProcessPath
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $userCmd = Join-Path $script:UserNodePrefix 'codex.cmd'
  if (Test-Path $userCmd) { return $userCmd }
  $userExe = Join-Path $script:UserNodePrefix 'codex.exe'
  if (Test-Path $userExe) { return $userExe }
  $prefixCmd = Join-Path $SystemNodePrefix 'codex.cmd'
  if (Test-Path $prefixCmd) { return $prefixCmd }
  $prefixExe = Join-Path $SystemNodePrefix 'codex.exe'
  if (Test-Path $prefixExe) { return $prefixExe }
  throw 'The codex command was not found.'
}

function Install-CodexCli {
  Write-Info 'Installing Codex CLI for the target Windows user...'
  Write-Info ('Target user home: ' + $script:TargetHome)
  Write-Info ('Using npm: ' + $script:NodeCmds.Npm)
  if ($script:NodeCmds.NpmCli -and (Test-Path $script:NodeCmds.NpmCli)) {
    Write-Info ('Using npm CLI: ' + $script:NodeCmds.NpmCli)
  } else {
    throw 'npm CLI entrypoint was not found next to node.exe. Please reinstall Node.js and try again.'
  }
  New-Item -ItemType Directory -Force -Path $script:UserNodePrefix | Out-Null
  Write-TargetNpmPrefix
  Add-TargetUserPathEntry $script:UserNodePrefix
  Refresh-ProcessPath

  Stop-CodexProcesses
  Remove-StaleCodexTempDirs
  Clear-TargetNpmCache
  $exitCode = Invoke-NpmInstall
  if ($exitCode -ne 0 -and (Test-NpmRetryableInstallFailure)) {
    Write-WarnMsg 'npm reported a retryable install failure. Cleaning old Codex install files and retrying once...'
    Stop-CodexProcesses
    Clear-TargetNpmCache
    Remove-OldCodexInstallFiles
    Remove-StaleCodexTempDirs
    $exitCode = Invoke-NpmInstall
  }

  if ($exitCode -ne 0) { throw ('npm failed to install Codex CLI globally. Exit code: ' + $exitCode) }
  Refresh-ProcessPath
  $codexCmd = Get-InstalledCodexCommand
  Write-Ok ('Codex CLI: ' + (& $codexCmd --version))
}

function Stop-CodexProcesses {
  foreach ($proc in (Get-Process -Name codex -ErrorAction SilentlyContinue)) {
    try {
      Write-WarnMsg ('Stopping running Codex process: ' + $proc.Id)
      Stop-Process -Id $proc.Id -Force -ErrorAction Stop
      Start-Sleep -Milliseconds 500
    } catch {
      Write-WarnMsg ('Could not stop Codex process ' + $proc.Id + ': ' + $_.Exception.Message)
    }
  }
}

function Remove-StaleCodexTempDirs {
  foreach ($prefix in @($script:UserNodePrefix, $SystemNodePrefix)) {
    $openaiDir = Join-Path $prefix 'node_modules\@openai'
    if (-not (Test-Path $openaiDir)) { continue }
    foreach ($dir in (Get-ChildItem -Path $openaiDir -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '.codex-*' })) {
      try {
        Write-WarnMsg ('Removing stale npm temp directory: ' + $dir.FullName)
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
      } catch {
        Write-WarnMsg ('Could not remove stale npm temp directory: ' + $_.Exception.Message)
      }
    }
  }
}

function Remove-OldCodexInstallFiles {
  $paths = @(
    (Join-Path $script:UserNodePrefix 'node_modules\@openai\codex'),
    (Join-Path $script:UserNodePrefix 'codex.cmd'),
    (Join-Path $script:UserNodePrefix 'codex.ps1'),
    (Join-Path $script:UserNodePrefix 'codex')
  )
  foreach ($path in @(
    (Join-Path $SystemNodePrefix 'node_modules\@openai\codex'),
    (Join-Path $SystemNodePrefix 'codex.cmd'),
    (Join-Path $SystemNodePrefix 'codex.ps1'),
    (Join-Path $SystemNodePrefix 'codex')
  ) + $paths) {
    if (Test-Path $path) {
      try {
        Write-WarnMsg ('Removing old Codex install path: ' + $path)
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
      } catch {
        Write-WarnMsg ('Could not remove old Codex install path: ' + $_.Exception.Message)
      }
    }
  }
}

function Test-NpmRetryableInstallFailure {
  if (-not $script:LastNpmStderr) { return $false }
  return ($script:LastNpmStderr -match 'EBUSY|resource busy|locked|EPERM|ENOTEMPTY|cleanup Failed|ENOSPC|no space left')
}

function Write-TargetNpmPrefix {
  $npmrcPath = Join-Path $script:TargetHome '.npmrc'
  $lines = @()
  if (Test-Path $npmrcPath) {
    $lines = Get-Content -Path $npmrcPath -ErrorAction SilentlyContinue |
      Where-Object { $_ -notmatch '^\s*prefix\s*=' }
  }
  $lines += ('prefix=' + $script:UserNodePrefix)
  Write-Utf8NoBom $npmrcPath (($lines -join [Environment]::NewLine) + [Environment]::NewLine)
}

function Clear-TargetNpmCache {
  $cachePath = Join-Path $script:TargetHome 'AppData\Local\npm-cache'
  if (-not ($cachePath.TrimEnd('\').ToLowerInvariant().StartsWith($script:TargetHome.TrimEnd('\').ToLowerInvariant()))) {
    Write-WarnMsg ('Skipping npm cache cleanup because the path is outside target home: ' + $cachePath)
    return
  }

  try {
    if (Test-Path $cachePath) {
      Write-WarnMsg ('Removing target npm cache directory: ' + $cachePath)
      Remove-Item -LiteralPath $cachePath -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Force -Path $cachePath | Out-Null
  } catch {
    Write-WarnMsg ('Could not clean npm cache: ' + $_.Exception.Message)
  }
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

function Invoke-NpmInstall([string[]]$packages = @($CodexPkg)) {
  $stdoutPath = Join-Path $env:TEMP ('codex-npm-stdout-' + [guid]::NewGuid().ToString() + '.log')
  $stderrPath = Join-Path $env:TEMP ('codex-npm-stderr-' + [guid]::NewGuid().ToString() + '.log')
  $npmArgs = @($script:NodeCmds.NpmCli, 'install', '-g', '--no-audit', '--no-fund', '--prefix', $script:UserNodePrefix) + $packages |
    ForEach-Object { Quote-ProcessArg ([string]$_) }
  $npmArgLine = $npmArgs -join ' '
  Write-Info ('npm install command: ' + $script:NodeCmds.Node + ' ' + $npmArgLine)
  $proc = Invoke-WithTargetUserEnvironment {
    Start-Process -FilePath $script:NodeCmds.Node -ArgumentList $npmArgLine -WorkingDirectory $script:TargetHome -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden
  }
  $timeoutSeconds = 240
  $startedAt = Get-Date
  while (-not $proc.HasExited) {
    Start-Sleep -Seconds 5
    $proc.Refresh()
    $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
    if ($elapsed -gt 0 -and ($elapsed % 30) -eq 0) {
      Write-Info ('npm install still running after ' + $elapsed + ' seconds...')
    }
    if ($elapsed -ge $timeoutSeconds) {
      Write-Err ('npm install timed out after ' + $timeoutSeconds + ' seconds.')
      try { Stop-Process -Id $proc.Id -Force -ErrorAction Stop } catch {}
      $proc.Refresh()
      break
    }
  }
  if ($proc.HasExited) {
    try { $proc.WaitForExit() } catch {}
    $exitCode = $proc.ExitCode
  } else {
    $exitCode = 124
  }

  $script:LastNpmStdout = ''
  $script:LastNpmStderr = ''
  try {
    if (Test-Path $stdoutPath) {
      $script:LastNpmStdout = Get-Content -Path $stdoutPath -Raw -ErrorAction SilentlyContinue
    }
    if (Test-Path $stderrPath) {
      $script:LastNpmStderr = Get-Content -Path $stderrPath -Raw -ErrorAction SilentlyContinue
    }

    if ($null -eq $exitCode) {
      if ($script:LastNpmStderr -match 'npm\s+(ERR!|error)\b|ENOSPC|no space left|TAR_ENTRY_ERROR') {
        $exitCode = 1
      } elseif ($script:LastNpmStdout -match '(added|changed|up to date).*packages?') {
        $exitCode = 0
      } else {
        $exitCode = 1
      }
    }

    if (-not [string]::IsNullOrWhiteSpace($script:LastNpmStdout)) {
      foreach ($line in ($script:LastNpmStdout -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
          Write-Info ([string]$line)
        }
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($script:LastNpmStderr)) {
      foreach ($line in ($script:LastNpmStderr -split "`r?`n")) {
        if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
          if ($exitCode -eq 0) {
            Write-WarnMsg ([string]$line)
          } else {
            Write-Err ([string]$line)
          }
        }
      }
    }
  } finally {
    Remove-Item $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
  }

  return $exitCode
}

function Backup-File([string]$path) {
  if (Test-Path $path) {
    Copy-Item $path ($path + '.bak.' + [DateTimeOffset]::Now.ToUnixTimeSeconds()) -Force
  }
}

function Load-ExistingApiKey {
  $authPath = Join-Path $script:TargetHome '.codex\auth.json'
  if (Test-Path $authPath) {
    try {
      $auth = Get-Content $authPath -Raw | ConvertFrom-Json
      if ($auth.PSObject.Properties.Name -contains 'OPENAI_API_KEY') {
        return [string]$auth.OPENAI_API_KEY
      }
    } catch {
      return ''
    }
  }
  return ''
}

function Resolve-CodexApiKey([string]$providedKey, [bool]$reuseSaved) {
  $existingKey = Load-ExistingApiKey
  if (-not [string]::IsNullOrWhiteSpace($providedKey)) {
    return $providedKey.Trim()
  }
  if ($reuseSaved -and -not [string]::IsNullOrWhiteSpace($existingKey)) {
    return $existingKey
  }
  throw 'API Key cannot be empty.'
}

function Prompt-CodexConfig {
  $existingKey = Load-ExistingApiKey

  Write-Info 'This installer will use the preset Codex configuration.'
  Write-Info 'Only your OpenAI API Key is required.'
  Write-Info ('Preset Base URL: ' + $CodexBaseUrl)
  Write-Info ('Preset model: ' + $DefaultModel)

  if ([string]::IsNullOrWhiteSpace($existingKey)) {
    $secure = Read-Host 'Enter OpenAI API Key' -AsSecureString
    $script:CodexApiKey = (Get-PlainText $secure).Trim()
  } else {
    $plain = Read-Host 'Enter OpenAI API Key (press Enter to reuse the saved key)'
    if ([string]::IsNullOrWhiteSpace($plain)) { $script:CodexApiKey = $existingKey } else { $script:CodexApiKey = $plain.Trim() }
  }

  if ([string]::IsNullOrWhiteSpace($script:CodexApiKey)) { throw 'API Key cannot be empty.' }
}

function Write-CodexConfig {
  $codexDir = Join-Path $script:TargetHome '.codex'
  New-Item -ItemType Directory -Force -Path $codexDir | Out-Null

  $configPath = Join-Path $codexDir 'config.toml'
  $authPath = Join-Path $codexDir 'auth.json'
  Backup-File $configPath
  Backup-File $authPath

  $configContent = @"
model_provider = "$CodexProviderName"
model = "$DefaultModel"
review_model = "$DefaultModel"
model_reasoning_effort = "$DefaultReasoning"
disable_response_storage = true
network_access = "enabled"
windows_wsl_setup_acknowledged = true

[model_providers.$CodexProviderName]
name = "$CodexProviderName"
base_url = "$CodexBaseUrl"
wire_api = "responses"
requires_openai_auth = true

[features]
goals = true
"@
  Write-Utf8NoBom $configPath $configContent

  $authContent = @{
    OPENAI_API_KEY = $script:CodexApiKey
  } | ConvertTo-Json -Depth 5
  Write-Utf8NoBom $authPath $authContent

  Write-Ok ('Wrote Codex config: ' + $codexDir)
}

function Mask-Key([string]$key) {
  if ($key.Length -le 8) { return '********' }
  return $key.Substring(0,4) + ('*' * ($key.Length - 8)) + $key.Substring($key.Length - 4)
}

function Verify-Everything {
  $configPath = Join-Path $script:TargetHome '.codex\config.toml'
  $authPath = Join-Path $script:TargetHome '.codex\auth.json'
  if (-not (Test-Path $configPath)) { throw '~/.codex/config.toml was not found' }
  if (-not (Test-Path $authPath)) { throw '~/.codex/auth.json was not found' }
  $codexCmd = Get-InstalledCodexCommand
  Write-Ok ('Node.js: ' + (& $script:NodeCmds.Node --version))
  Write-Ok ('npm: ' + (& $script:NodeCmds.Npm --version))
  Write-Ok ('npx: ' + (& $script:NodeCmds.Npx --version))
  Write-Ok ('Codex CLI: ' + (& $codexCmd --version))
  Write-Ok ('Model: ' + $DefaultModel)
  Write-Ok ('Base URL: ' + $CodexBaseUrl)
  Write-Ok ('API Key: ' + (Mask-Key $script:CodexApiKey))
  Write-WarnMsg 'Run codex in PowerShell or Windows Terminal. Windows 11 is recommended; Windows 10 requires version 1809 or newer.'
}

function Invoke-CodexInstall([string]$providedKey, [bool]$reuseSaved) {
  Write-Info ('Log file: ' + $LogPath)
  Write-Info 'Official install docs: https://developers.openai.com/codex/cli'
  Write-Info 'PowerShell or Windows Terminal is recommended on Windows.'
  $script:CodexApiKey = Resolve-CodexApiKey $providedKey $reuseSaved
  Write-Info ('Loaded API Key: ' + (Mask-Key $script:CodexApiKey))
  Install-SystemNode
  Install-CodexCli
  Write-CodexConfig
  Verify-Everything
  Write-Ok 'Installation complete. You can now run codex in PowerShell or Windows Terminal.'
}

function Open-LogFolder {
  try {
    $target = if (Test-Path $LogPath) { $LogPath } elseif (Test-Path $DiagnosticLogPath) { $DiagnosticLogPath } else { $PSScriptRoot }
    if (Test-Path $target -PathType Leaf) {
      Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $target)
    } else {
      Start-Process explorer.exe -ArgumentList ('"{0}"' -f $target)
    }
  } catch {
    Write-Diagnostic ('- Warning: failed to open log folder: ' + $_.Exception.Message)
  }
}

function Open-CodexTerminal {
  $desktop = Join-Path $script:TargetHome 'Desktop'
  if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path $desktop)) {
    $desktop = $script:TargetHome
  }

  Write-DiagnosticSection 'Open Codex terminal'
  Write-Diagnostic ('- Desktop path: ' + $desktop)
  Write-Diagnostic ('- PowerShell path: ' + $PowerShellExe)

  $launchDir = Join-Path $env:TEMP 'openai-codex-launch'
  New-Item -ItemType Directory -Force -Path $launchDir | Out-Null
  $launchScript = Join-Path $launchDir 'start-codex.ps1'
  $escapedDesktop = $desktop.Replace("'", "''")
  $escapedNodePrefix = $SystemNodePrefix.Replace("'", "''")
  $escapedUserNodePrefix = $script:UserNodePrefix.Replace("'", "''")
  $launchContent = @"
`$env:Path = @('$escapedUserNodePrefix', '$escapedNodePrefix', [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';'
Set-Location -LiteralPath '$escapedDesktop'
codex
"@
  Write-Utf8NoBom $launchScript $launchContent

  Write-Diagnostic ('- Launch script: ' + $launchScript)
  Start-Process -FilePath $PowerShellExe -WorkingDirectory $desktop -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $launchScript))
}

function Read-ApiKeyFromFile([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { return '' }
  if (-not (Test-Path $path)) { throw 'The temporary API Key file does not exist.' }
  return (Get-Content -Path $path -Raw -Encoding UTF8).Trim()
}


function GuiText([string]$value) {
  return [System.Text.RegularExpressions.Regex]::Unescape($value)
}

function Show-Gui {
  Write-DiagnosticSection 'GUI startup'
  Write-Diagnostic '- Stage: loading Windows Forms assemblies.'
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  [System.Windows.Forms.Application]::EnableVisualStyles()
  Write-Diagnostic '- Stage: Windows Forms assemblies loaded.'

  $existingKey = Load-ExistingApiKey

  $form = New-Object System.Windows.Forms.Form
  $form.Text = (GuiText 'OpenAI Codex \u5b89\u88c5\u5668')
  $form.StartPosition = 'CenterScreen'
  $form.Size = New-Object System.Drawing.Size(720, 560)
  $form.MinimumSize = New-Object System.Drawing.Size(640, 500)

  $title = New-Object System.Windows.Forms.Label
  $title.Text = (GuiText 'OpenAI Codex CLI \u4e00\u952e\u5b89\u88c5')
  $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold)
  $title.AutoSize = $true
  $title.Location = New-Object System.Drawing.Point(18, 16)
  $form.Controls.Add($title)

  $desc = New-Object System.Windows.Forms.Label
  $desc.Text = (GuiText '\u8f93\u5165 OpenAI API Key \u540e\u5f00\u59cb\u5b89\u88c5\u3002\u5b89\u88c5\u5668\u4f1a\u68c0\u6d4b Node.js\u3001\u5b89\u88c5 Codex CLI\u3001\u5199\u5165\u914d\u7f6e\u5e76\u6821\u9a8c\u7ed3\u679c\u3002')
  $desc.AutoSize = $false
  $desc.Location = New-Object System.Drawing.Point(20, 50)
  $desc.Size = New-Object System.Drawing.Size(660, 34)
  $form.Controls.Add($desc)

  $keyLabel = New-Object System.Windows.Forms.Label
  $keyLabel.Text = 'OpenAI API Key'
  $keyLabel.AutoSize = $true
  $keyLabel.Location = New-Object System.Drawing.Point(20, 84)
  $form.Controls.Add($keyLabel)

  $keyBox = New-Object System.Windows.Forms.TextBox
  $keyBox.UseSystemPasswordChar = $true
  $keyBox.Anchor = 'Top,Left,Right'
  $keyBox.Location = New-Object System.Drawing.Point(20, 106)
  $keyBox.Size = New-Object System.Drawing.Size(520, 24)
  $form.Controls.Add($keyBox)

  $reuseBox = New-Object System.Windows.Forms.CheckBox
  $reuseBox.Text = (GuiText '\u590d\u7528\u5df2\u4fdd\u5b58\u7684 Key')
  $reuseBox.AutoSize = $true
  $reuseBox.Location = New-Object System.Drawing.Point(552, 108)
  $reuseBox.Enabled = -not [string]::IsNullOrWhiteSpace($existingKey)
  $reuseBox.Checked = -not [string]::IsNullOrWhiteSpace($existingKey)
  $form.Controls.Add($reuseBox)

  $status = New-Object System.Windows.Forms.Label
  $status.Text = if ($reuseBox.Enabled) { (GuiText '\u68c0\u6d4b\u5230\u5df2\u6709\u914d\u7f6e\uff0c\u53ef\u76f4\u63a5\u590d\u7528\u6216\u8f93\u5165\u65b0 Key \u8986\u76d6\u3002') } else { (GuiText '\u7b49\u5f85\u8f93\u5165 API Key\u3002') }
  $status.AutoSize = $true
  $status.Location = New-Object System.Drawing.Point(20, 142)
  $form.Controls.Add($status)

  $progress = New-Object System.Windows.Forms.ProgressBar
  $progress.Style = 'Marquee'
  $progress.MarqueeAnimationSpeed = 0
  $progress.Anchor = 'Top,Left,Right'
  $progress.Location = New-Object System.Drawing.Point(20, 170)
  $progress.Size = New-Object System.Drawing.Size(660, 16)
  $form.Controls.Add($progress)

  $logBox = New-Object System.Windows.Forms.TextBox
  $logBox.Multiline = $true
  $logBox.ReadOnly = $true
  $logBox.ScrollBars = 'Both'
  $logBox.WordWrap = $false
  $logBox.Anchor = 'Top,Bottom,Left,Right'
  $logBox.Location = New-Object System.Drawing.Point(20, 200)
  $logBox.Size = New-Object System.Drawing.Size(660, 250)
  $form.Controls.Add($logBox)

  $startButton = New-Object System.Windows.Forms.Button
  $startButton.Text = (GuiText '\u5f00\u59cb\u5b89\u88c5')
  $startButton.Location = New-Object System.Drawing.Point(20, 468)
  $startButton.Size = New-Object System.Drawing.Size(110, 32)
  $form.Controls.Add($startButton)

  $closeButton = New-Object System.Windows.Forms.Button
  $closeButton.Text = (GuiText '\u5173\u95ed')
  $closeButton.Location = New-Object System.Drawing.Point(142, 468)
  $closeButton.Size = New-Object System.Drawing.Size(90, 32)
  $closeButton.Add_Click({ $form.Close() })
  $form.Controls.Add($closeButton)

  $openLogButton = New-Object System.Windows.Forms.Button
  $openLogButton.Text = (GuiText '\u6253\u5f00\u65e5\u5fd7\u4f4d\u7f6e')
  $openLogButton.Location = New-Object System.Drawing.Point(244, 468)
  $openLogButton.Size = New-Object System.Drawing.Size(120, 32)
  $openLogButton.Add_Click({ Open-LogFolder })
  $form.Controls.Add($openLogButton)

  $useButton = New-Object System.Windows.Forms.Button
  $useButton.Text = (GuiText '\u524d\u5f80\u4f7f\u7528')
  $useButton.Location = New-Object System.Drawing.Point(376, 468)
  $useButton.Size = New-Object System.Drawing.Size(110, 32)
  $useButton.Enabled = $false
  $useButton.Add_Click({
    try {
      Open-CodexTerminal
      $status.Text = (GuiText '\u5df2\u5728\u684c\u9762\u76ee\u5f55\u6253\u5f00 PowerShell \u5e76\u8fd0\u884c codex\u3002')
    } catch {
      Write-Diagnostic ('- Warning: failed to open Codex terminal: ' + $_.Exception.Message)
      [System.Windows.Forms.MessageBox]::Show($form, (((GuiText '\u65e0\u6cd5\u6253\u5f00 Codex\uff1a')) + $_.Exception.Message), (GuiText 'OpenAI Codex \u5b89\u88c5\u5668'), 'OK', 'Error') | Out-Null
    }
  })
  $form.Controls.Add($useButton)

  $logPathLabel = New-Object System.Windows.Forms.Label
  $logPathLabel.Text = (GuiText '\u65e5\u5fd7\u4f4d\u7f6e\uff1a\u70b9\u51fb\u6309\u94ae\u6253\u5f00\u65e5\u5fd7\u6587\u4ef6\u5939')
  $logPathLabel.AutoSize = $false
  $logPathLabel.Anchor = 'Bottom,Left'
  $logPathLabel.Location = New-Object System.Drawing.Point(498, 476)
  $logPathLabel.Size = New-Object System.Drawing.Size(182, 24)
  $form.Controls.Add($logPathLabel)

  $installTimer = New-Object System.Windows.Forms.Timer
  $installTimer.Interval = 700
  $script:InstallProcess = $null
  $script:ApiKeyTempPath = ''
  $script:LastLogLength = 0

  $installTimer.Add_Tick({
    if (Test-Path $LogPath) {
      try {
        $content = Get-Content -Path $LogPath -Raw -Encoding UTF8
        if ($content.Length -ne $script:LastLogLength) {
          $logBox.Text = $content
          $script:LastLogLength = $content.Length
          $logBox.SelectionStart = $logBox.TextLength
          $logBox.ScrollToCaret()
        }
      } catch {
        Write-Diagnostic ('- Warning: failed to refresh GUI log: ' + $_.Exception.Message)
      }
    }

    if ($script:InstallProcess -and $script:InstallProcess.HasExited) {
      $installTimer.Stop()
      $progress.MarqueeAnimationSpeed = 0
      $startButton.Enabled = $true
      $keyBox.Enabled = $true
      $reuseBox.Enabled = -not [string]::IsNullOrWhiteSpace($existingKey)
      if (-not [string]::IsNullOrWhiteSpace($script:ApiKeyTempPath)) {
        Remove-Item $script:ApiKeyTempPath -Force -ErrorAction SilentlyContinue
        $script:ApiKeyTempPath = ''
      }

      $exitCode = $script:InstallProcess.ExitCode
      Write-Diagnostic ('- Worker exit code: ' + $exitCode)
      if ($exitCode -eq 0) {
        $status.Text = (GuiText '\u5b89\u88c5\u5b8c\u6210\uff0c\u53ef\u4ee5\u5728 PowerShell \u6216 Windows Terminal \u4e2d\u8f93\u5165 codex \u4f7f\u7528\u3002')
        $useButton.Enabled = $true
        [System.Windows.Forms.MessageBox]::Show($form, (GuiText '\u5b89\u88c5\u5b8c\u6210\u3002\\n\\n\u73b0\u5728\u53ef\u4ee5\u5728 PowerShell \u6216 Windows Terminal \u4e2d\u8f93\u5165 codex \u4f7f\u7528\u3002'), (GuiText 'OpenAI Codex \u5b89\u88c5\u5668'), 'OK', 'Information') | Out-Null
      } else {
        $status.Text = (GuiText '\u5b89\u88c5\u5931\u8d25\u3002\u8bf7\u70b9\u51fb\u201c\u6253\u5f00\u65e5\u5fd7\u4f4d\u7f6e\u201d\u67e5\u770b\u65e5\u5fd7\u3002')
        $useButton.Enabled = $false
        [System.Windows.Forms.MessageBox]::Show($form, (((GuiText '\u5b89\u88c5\u5931\u8d25\uff0c\u9000\u51fa\u7801\uff1a')) + $exitCode + ((GuiText '\\n\\n\u70b9\u51fb\u201c\u6253\u5f00\u65e5\u5fd7\u4f4d\u7f6e\u201d\u53ef\u4ee5\u67e5\u770b\u8bca\u65ad\u65e5\u5fd7\u548c\u5b89\u88c5\u65e5\u5fd7\u3002'))), (GuiText 'OpenAI Codex \u5b89\u88c5\u5668'), 'OK', 'Error') | Out-Null
      }
      $script:InstallProcess.Dispose()
      $script:InstallProcess = $null
    }
  })

  $startButton.Add_Click({
    $key = $keyBox.Text.Trim()
    $reuse = [bool]$reuseBox.Checked
    if ([string]::IsNullOrWhiteSpace($key) -and -not $reuse) {
      [System.Windows.Forms.MessageBox]::Show($form, (GuiText '\u8bf7\u8f93\u5165 OpenAI API Key\u3002'), (GuiText 'OpenAI Codex \u5b89\u88c5\u5668'), 'OK', 'Warning') | Out-Null
      return
    }
    $logBox.Clear()
    Write-DiagnosticSection 'Install button'
    Write-Diagnostic '- Stage: user clicked start install.'
    if (Test-Path $LogPath) { Remove-Item $LogPath -Force -ErrorAction SilentlyContinue }
    $script:LastLogLength = 0
    $status.Text = (GuiText '\u6b63\u5728\u5b89\u88c5\uff0c\u8bf7\u4e0d\u8981\u5173\u95ed\u7a97\u53e3...')
    $startButton.Enabled = $false
    $keyBox.Enabled = $false
    $reuseBox.Enabled = $false
    $useButton.Enabled = $false
    $progress.MarqueeAnimationSpeed = 30
    if (-not [string]::IsNullOrWhiteSpace($key)) {
      $script:ApiKeyTempPath = Join-Path $env:TEMP ('codex-api-key-' + [guid]::NewGuid().ToString() + '.txt')
      Write-Utf8NoBom $script:ApiKeyTempPath $key
    } else {
      $script:ApiKeyTempPath = ''
    }

	    $args = @(
      '-NoProfile',
      '-STA',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      ('"{0}"' -f $PSCommandPath),
      '-WorkerInstall',
      '-DiagnosticPath',
      ('"{0}"' -f $DiagnosticLogPath),
	      '-RuntimeLogPath',
	      ('"{0}"' -f $LogPath),
	      '-TargetHome',
	      ('"{0}"' -f $script:TargetHome)
	    )
    if ($reuse) { $args += '-ReuseSavedKey' }
    if (-not [string]::IsNullOrWhiteSpace($script:ApiKeyTempPath)) {
      $args += '-ApiKeyFile'
      $args += ('"{0}"' -f $script:ApiKeyTempPath)
    }
    Write-Diagnostic ('- Worker command: ' + $PowerShellExe + ' ' + (($args | Where-Object { $_ -ne ('"{0}"' -f $script:ApiKeyTempPath) }) -join ' '))

    try {
      $script:InstallProcess = Start-Process $PowerShellExe -ArgumentList ($args -join ' ') -PassThru -WindowStyle Hidden
      Write-Diagnostic ('- Worker process id: ' + $script:InstallProcess.Id)
      $installTimer.Start()
    } catch {
      $progress.MarqueeAnimationSpeed = 0
      $startButton.Enabled = $true
      $keyBox.Enabled = $true
      $reuseBox.Enabled = -not [string]::IsNullOrWhiteSpace($existingKey)
      if (-not [string]::IsNullOrWhiteSpace($script:ApiKeyTempPath)) {
        Remove-Item $script:ApiKeyTempPath -Force -ErrorAction SilentlyContinue
        $script:ApiKeyTempPath = ''
      }
      Write-Diagnostic ('- Error: failed to start worker process: ' + $_.Exception.Message)
      [System.Windows.Forms.MessageBox]::Show($form, (((GuiText '\u65e0\u6cd5\u542f\u52a8\u5b89\u88c5\u8fdb\u7a0b\uff1a')) + $_.Exception.Message + ((GuiText '\\n\\n\u70b9\u51fb\u201c\u6253\u5f00\u65e5\u5fd7\u4f4d\u7f6e\u201d\u67e5\u770b\u8bca\u65ad\u65e5\u5fd7\u3002'))), (GuiText 'OpenAI Codex \u5b89\u88c5\u5668'), 'OK', 'Error') | Out-Null
    }
  })

  $form.Add_FormClosing({
    if ($script:InstallProcess -and -not $script:InstallProcess.HasExited) {
      $answer = [System.Windows.Forms.MessageBox]::Show($form, (GuiText '\u5b89\u88c5\u4ecd\u5728\u8fdb\u884c\u4e2d\uff0c\u786e\u5b9a\u8981\u5173\u95ed\u5417\uff1f'), (GuiText 'OpenAI Codex \u5b89\u88c5\u5668'), 'YesNo', 'Warning')
      if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        $_.Cancel = $true
      }
    }
  })

  Write-Diagnostic '- Stage: showing GUI window.'
  [void]$form.ShowDialog()
  Write-Diagnostic '- Stage: GUI window closed.'
}

try {
  Ensure-Admin
  if ($WorkerInstall) {
    $workerKey = Read-ApiKeyFromFile $ApiKeyFile
    Invoke-CodexInstall $workerKey ([bool]$ReuseSavedKey)
    exit 0
  } elseif ($Console) {
    Clear-Host
    Write-Host '========================================'
    Write-Host '  OpenAI Codex CLI Installer(Windows)'
    Write-Host '========================================'
    Prompt-CodexConfig
    Invoke-CodexInstall $script:CodexApiKey $false
    Pause-AndExit 0
  } else {
    Show-Gui
  }
} catch {
  Write-Err $_.Exception.Message
  Write-DiagnosticSection 'Fatal error'
  Write-Diagnostic ('- Error: ' + $_.Exception.Message)
  Write-Diagnostic '```text'
  Write-Diagnostic ($_.ScriptStackTrace | Out-String)
  Write-Diagnostic '```'
  Write-LogLine 'ERROR' ($_.ScriptStackTrace | Out-String)
  Pause-AndExit 1
}
