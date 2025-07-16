# ====================================
# Launcher for Shutdown Scheduler
# Always runs Shutdown.ps1 from this folder
# ====================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$shutdownScript = Join-Path $scriptDir 'Shutdown.ps1'


Start-Process powershell.exe -ArgumentList "-NoExit -File `"$shutdownScript`""
