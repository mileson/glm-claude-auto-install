@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-openai-codex.ps1"
exit /b %ERRORLEVEL%
