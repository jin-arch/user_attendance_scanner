@echo off
setlocal
cd /d "%~dp0.."
python tools\live_android_db_sync.py --once
echo.
echo Synced Android DB to C:\SQLiteDB\biometric_scanner.db
pause
