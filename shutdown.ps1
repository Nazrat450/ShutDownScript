# =======================================
# Shutdown Scheduler - Enhanced Version
# =======================================

function Countdown ($seconds) {
    for ($i = $seconds; $i -ge 1; $i--) {
        Write-Host ' Shutting down in ' -NoNewline
        Write-Host "$i seconds..." -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
}

function Get-ShutdownDelayFromDuration {
    $hours = Read-Host 'Enter hours until shutdown'
    $minutes = Read-Host 'Enter minutes until shutdown'
    return ([int]$hours * 3600) + ([int]$minutes * 60)
}

function Get-ShutdownDelayFromTime {
    $timeInput = Read-Host 'Enter the shutdown time (24-hour format, e.g., 23:45)'
    try {
        $shutdownTime = Get-Date $timeInput -ErrorAction Stop
        $now = Get-Date
        if ($shutdownTime -lt $now) {
            $shutdownTime = $shutdownTime.AddDays(1)
        }
        return ($shutdownTime - $now).TotalSeconds
    }
    catch {
        Write-Host 'Invalid time format. Please enter time as HH:mm (e.g., 23:45).'
        return $null
    }
}

function KillSteam {
    param (
        [int]$postSteamWaitSeconds
    )
    $steam = Get-Process | Where-Object { $_.Name -like 'steam*' }
    if ($steam) {
        Write-Host 'Closing Steam...'
        $steam | Stop-Process -Force
    } else {
        Write-Host 'Steam is not currently running. Skipping Steam shutdown.'
    }

    $waitSpan = New-TimeSpan -Seconds $postSteamWaitSeconds
    Write-Host "Waiting $($waitSpan.Hours + $waitSpan.Days * 24) hour(s) and $($waitSpan.Minutes) minute(s) before shutdown..."
    Start-Sleep -Seconds $postSteamWaitSeconds

    Countdown 10
    Write-Host 'Time''s up. Shutting down system now.'
    Stop-Computer -Force
}

function Get-ShutdownAfterGameDownloads {
    $steamPaths = @(
        'C:\Program Files (x86)\Steam\steamapps\downloading',
        'E:\SteamLibrary\steamapps\downloading'
    )
    $epicManifestsPath = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
    
    Write-Host 'Monitoring download queues for Steam and Epic Games'

    $activeDownloads = $true
    while ($activeDownloads) {
        $activeDownloads = $false

        # Check Steam
        foreach ($path in $steamPaths) {
            if ((Test-Path $path) -and (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
                $activeDownloads = $true
                Write-Host "Steam downloads still active at: $path"
            }
        }

        # Check Epic
        if (Test-Path $epicManifestsPath) {
            $epicManifests = Get-ChildItem $epicManifestsPath -Filter *.item -ErrorAction SilentlyContinue
            foreach ($manifest in $epicManifests) {
                $content = Get-Content $manifest.FullName | Out-String
                if ($content -match '"bIsDownloading"\s*:\s*true') {
                    $activeDownloads = $true
                    Write-Host "Epic Games download in progress (manifest: $($manifest.Name))"
                }
            }

            # Also check if Pending folder has files
            $pendingPath = Join-Path $epicManifestsPath 'Pending'
            if (Test-Path $pendingPath) {
                if ((Get-ChildItem $pendingPath -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
                    $activeDownloads = $true
                    Write-Host "Epic Games Pending folder has active files."
                }
            }
        }

        
        if ($activeDownloads) {
            Write-Host 'Checking again in 30 minutes...'
            Start-Sleep -Seconds 1800
        }
    }

    Write-Host 'All downloads (Steam and Epic) have completed.'
    Start-Sleep -Seconds 10
    KillSteam 300
}


# =======================================
# Menu & Confirmation
# =======================================

Write-Host '
 ____________________________
|     SHUTDOWN SCHEDULER     |       
|____________________________|


@@                                             
    @@@@@             @@@@@@@@@@                      
.@@   @@          %@@     @@%                        
.@@     @@@@@@@@@@@@@  (@@                           
    @@@                 (@@                           
.@@                       @@%                        
.@@   @@          %@@     @@%                        
.@@   @@   @@     %@@     @@%                        
.@@     @@@  @@@          @@%                        
    @@@                 (@@                           
.@@   @@@@@@@@@@@@@@@     @@%                        
.@@@@@@@             @@@@@@@% 

'





$confirm = Read-Host 'Are you sure you want to schedule a shutdown? (Y/N)'
if ($confirm -ne 'Y') {
    Write-Host 'Shutdown cancelled. Exiting script.'
    exit
}

Write-Host 'Choose an option:'
Write-Host '1. Set shutdown after a delay (hours and minutes)'
Write-Host '2. Set shutdown at a specific time (Australian time, 24-hour format)'
Write-Host '3. Shutdown 5 minutes after Steam and Epic download queues are finished'
$choice = Read-Host 'Enter 1, 2 or 3'

if ($choice -eq '1') {
    $totalSeconds = Get-ShutdownDelayFromDuration
} elseif ($choice -eq '2') {
    $totalSeconds = Get-ShutdownDelayFromTime
    if ($totalSeconds -eq $null) { exit }
} elseif ($choice -eq '3') {
    Get-ShutdownAfterGameDownloads
    exit
} else {
    Write-Host 'Invalid choice. Exiting.'
    exit
}

# ========== Option 1 or 2 continuation ==========
$shutdownAt = (Get-Date).AddSeconds($totalSeconds)
$shutdownTimeFormatted = $shutdownAt.ToString('dddd, MMMM dd yyyy HH:mm:ss')

$steamWaitSeconds = [math]::Round($totalSeconds * 0.75)
$postSteamWaitSeconds = $totalSeconds - $steamWaitSeconds

# Display full duration
$logSpan = New-TimeSpan -Seconds $totalSeconds
$logHours = $logSpan.Hours + $logSpan.Days * 24
$logMinutes = $logSpan.Minutes

Write-Host ''
Write-Host '=== Shutdown Script Initiated ==='
Write-Host "System will shut down in $logHours hour(s) and $logMinutes minute(s)."
Write-Host "Scheduled shutdown time: $shutdownTimeFormatted"

# Steam check wait time
$waitBeforeSteamSpan = New-TimeSpan -Seconds $steamWaitSeconds
$waitBeforeSteamHours = $waitBeforeSteamSpan.Hours + ($waitBeforeSteamSpan.Days * 24)
$waitBeforeSteamMinutes = $waitBeforeSteamSpan.Minutes

if ($waitBeforeSteamHours -gt 0) {
    Write-Host "Waiting $waitBeforeSteamHours hour$(
        if ($waitBeforeSteamHours -ne 1) { 's' } else { '' }
    ) and $waitBeforeSteamMinutes minute$(
        if ($waitBeforeSteamMinutes -ne 1) { 's' } else { '' }
    ) before checking for Steam..."
} else {
    Write-Host "Waiting $waitBeforeSteamMinutes minute$(
        if ($waitBeforeSteamMinutes -ne 1) { 's' } else { '' }
    ) before checking for Steam..."
}

Start-Sleep -Seconds $steamWaitSeconds
KillSteam $postSteamWaitSeconds
