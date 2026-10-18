@echo off
chcp 65001 >nul
@echo off
setlocal
set "GTC_DIR=%TEMP%\GTC_Setup"
set "GTC_BASE=https://raw.githubusercontent.com/gokcheon/gtc-zomboid-setup/main/"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; New-Item -ItemType Directory -Force -Path $env:GTC_DIR | Out-Null; $w=New-Object Net.WebClient; foreach($f in 'setup.ps1','config.json'){ $w.DownloadFile($env:GTC_BASE+$f, (Join-Path $env:GTC_DIR $f)) }"
if errorlevel 1 (
  echo.
  echo [ERROR] Download failed. Check your internet connection and run again.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%GTC_DIR%\setup.ps1"
endlocal
