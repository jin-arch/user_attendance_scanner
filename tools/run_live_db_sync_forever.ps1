$ErrorActionPreference = 'Stop'
$repoRoot = 'C:\UAS\user_attendance_scanner'
$scriptPath = Join-Path $repoRoot 'tools\live_android_db_sync.py'
$logPath = 'C:\SQLiteDB\live_db_sync.log'

if (-not (Test-Path 'C:\SQLiteDB')) {
  New-Item -ItemType Directory -Path 'C:\SQLiteDB' -Force | Out-Null
}

Set-Location $repoRoot
python $scriptPath --interval 2 2>&1 | Tee-Object -FilePath $logPath -Append
