@echo off
rem Moho Power Launcher - double-click to install (or update). No admin rights needed.
if not exist "%~dp0app\Setup.ps1" (
  echo.
  echo  Please unzip the whole download first ^(right-click the zip ^> Extract All^),
  echo  then double-click "Install Moho Power Launcher" in the unzipped folder.
  echo.
  pause
  exit /b 1
)
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app\Setup.ps1"
