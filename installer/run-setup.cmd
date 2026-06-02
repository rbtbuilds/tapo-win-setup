@echo off
REM Invoked by the Install-Tapo.exe installer. Sets the "packaged" flag so the
REM setup script doesn't pause for Enter, then runs it (it finds the .apkm sitting
REM next to it in the same folder).
set TAPO_PACKAGED=1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-Tapo-Emulator.ps1"
