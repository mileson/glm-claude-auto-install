@echo off
setlocal
chcp 65001 >nul

set "SCRIPT=%~dp0install-glm-claude.ps1"
set "LOG_DIR=%TEMP%\glm-claude-auto-install-logs"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

echo ========================================
echo   GLM Claude Code 一键安装（Windows）
echo ========================================
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo 未找到 Windows PowerShell，无法继续安装。
  echo 请把这张截图发给支持同学。
  echo.
  pause
  exit /b 1
)

if not exist "%SCRIPT%" (
  echo 找不到安装脚本：
  echo %SCRIPT%
  echo.
  echo 请确认 zip 已完整解压，并且 .bat 和 .ps1 在同一个文件夹。
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
  echo.
  echo 安装没有完成，退出码：%EXIT_CODE%
  echo 日志目录：%LOG_DIR%
  echo 请把日志文件发给支持同学。
  echo.
  pause
)

exit /b %EXIT_CODE%
