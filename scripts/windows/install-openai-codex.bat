@echo off
setlocal

set "SCRIPT=%~dp0install-openai-codex.ps1"
set "DIAG_LOG=%~dp0OpenAI-Codex-Install-Diagnostic.md"
set "LOG_DIR=%TEMP%\glm-claude-auto-install-logs"
set "MODE_ARGS="
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if /I "%~1"=="--console" set "MODE_ARGS=-Console"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

> "%DIAG_LOG%" echo # OpenAI Codex Windows Installer Diagnostic
call :log ""
call :log "## Batch launcher"
call :log "- Time: %DATE% %TIME%"
call :log "- Stage: batch started"
call :log "- Console mode: %MODE_ARGS%"
call :log "- Batch path: %~f0"
call :log "- Script path: %SCRIPT%"
call :log "- PowerShell candidate: %PS_EXE%"
call :log ""

call :log "- Stage: checking PowerShell absolute path"
if exist "%PS_EXE%" goto ps_path_ready
call :log "- Warning: absolute PowerShell path was not found."
set "PS_EXE=powershell.exe"
call :log "- Fallback PowerShell command: powershell.exe"

:ps_path_ready
call :log "- Stage: checking installer script"
if exist "%SCRIPT%" goto script_ready
call :log "- Error: install-openai-codex.ps1 was not found next to this batch file."
echo Installer script was not found:
echo %SCRIPT%
echo.
echo Please unzip the package first, then run this file again.
echo Diagnostic log:
echo %DIAG_LOG%
echo.
call :open_log
pause
exit /b 1

:script_ready
call :log "- Stage: probing PowerShell startup"
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Write-Output 'powershell-probe-ok'" >> "%DIAG_LOG%" 2>&1
set "PROBE_CODE=%ERRORLEVEL%"
call :log "- PowerShell probe exit code: %PROBE_CODE%"
if "%PROBE_CODE%"=="0" goto probe_ready
call :log "- Error: PowerShell failed during probe."
echo Windows PowerShell was not found or could not start. Cannot continue.
echo Diagnostic log:
echo %DIAG_LOG%
echo.
call :open_log
pause
exit /b %PROBE_CODE%

:probe_ready
call :log "- Stage: launching powershell.exe"
if /I "%~1"=="--console" goto launch_console

:launch_gui
"%PS_EXE%" -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT%" -DiagnosticPath "%DIAG_LOG%" >> "%DIAG_LOG%" 2>&1
goto after_launch

:launch_console
"%PS_EXE%" -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT%" -DiagnosticPath "%DIAG_LOG%" %MODE_ARGS%

:after_launch
set "EXIT_CODE=%ERRORLEVEL%"
call :log "- PowerShell exit code: %EXIT_CODE%"
if "%EXIT_CODE%"=="0" goto finish
echo.
echo Installation did not finish. Exit code: %EXIT_CODE%
echo Log directory: %LOG_DIR%
echo Diagnostic log:
echo %DIAG_LOG%
echo.
call :open_log
pause

:finish
call :log "- Stage: batch finished"
exit /b %EXIT_CODE%

:log
if "%~1"=="" goto log_blank
>> "%DIAG_LOG%" echo %~1
exit /b 0

:log_blank
>> "%DIAG_LOG%" echo.
exit /b 0

:open_log
start "" notepad.exe "%DIAG_LOG%" >nul 2>nul
exit /b 0
