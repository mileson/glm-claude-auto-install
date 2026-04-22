@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup-old-glm-managed-install.ps1"
exit /b %ERRORLEVEL%
