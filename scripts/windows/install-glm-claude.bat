@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-glm-claude.ps1"
exit /b %ERRORLEVEL%
