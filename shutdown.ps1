# =======================================
#        Shutdown Scheduler
# =======================================

function Countdown ($seconds) {
    for ($i = $seconds; $i -ge 1; $i--) {
        Write-Host ' Shutting down in ' -NoNewline
        Write-Host "$i seconds..." -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
}

function Show-Countdown {
    param (
        [int]$Seconds,
        [string]$Activity = "Waiting...",
        [string]$Status = "Countdown in progress"
    )
    for ($i = $Seconds; $i -ge 0; $i--) {
        $percent = (($Seconds - $i) / $Seconds) * 100
        $timeLeft = [TimeSpan]::FromSeconds($i).ToString("hh\:mm\:ss")
        Write-Progress -Activity $Activity -Status "$Status ($timeLeft remaining)" -PercentComplete $percent
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $Activity -Completed
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
    Show-Countdown -Seconds $postSteamWaitSeconds -Activity "Post-Steam wait" -Status "Shutdown in progress"

    Show-Countdown -Seconds 10 -Activity "Final Shutdown" -Status "Shutting down shortly"
    Write-Host "Time's up. Shutting down system now."
    Stop-Computer -Force
}

function Get-SteamDownloadPaths {
    $steamRegPath = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'
    $libraryPaths = @()

    try {
        $steamInstallPath = (Get-ItemProperty -Path $steamRegPath -ErrorAction Stop).InstallPath
        $vdfPath = Join-Path $steamInstallPath 'steamapps\libraryfolders.vdf'

        if (Test-Path $vdfPath) {
           # Write-Host "Parsing Steam libraryfolders.vdf at $vdfPath"
            $vdfContent = Get-Content $vdfPath | Out-String

            $matches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
            foreach ($match in $matches) {
                $libraryPath = $match.Groups[1].Value
                $downloadPath = Join-Path $libraryPath 'steamapps\downloading'
                $libraryPaths += $downloadPath
            }

            Write-Host "Detected Steam download paths:"
            $libraryPaths | ForEach-Object { Write-Host " - $_" }
        }
        else {
            Write-Host "libraryfolders.vdf not found, using main Steam path only."
            $libraryPaths += Join-Path $steamInstallPath 'steamapps\downloading'
        }
    } catch {
        Write-Host "Steam registry key not found. Using default fallback."
        $libraryPaths += 'C:\Program Files (x86)\Steam\steamapps\downloading'
    }

    return $libraryPaths
}

function Get-EpicManifestPath {
    $defaultManifestPath = 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests'
    if (Test-Path $defaultManifestPath) {
        Write-Host "Detected Epic Games manifest path: $defaultManifestPath"
        return $defaultManifestPath
    } else {
        Write-Host "Epic manifest path not found. Please verify Epic Games is installed."
        return $null
    }
}

function Get-ShutdownAfterGameDownloads {
    $steamPaths = Get-SteamDownloadPaths
    $epicManifestsPath = Get-EpicManifestPath

    Write-Host 'Monitoring download queues for Steam and Epic Games'

    $previousSteamFileSizes = @{}

    while ($true) {
        $steamActive = $false
        $epicActive = $false
        $steamSizeChanged = $false
        $currentSteamFileSizes = @{}

        # ----- Check Steam -----
        foreach ($path in $steamPaths) {
            if (Test-Path $path) {
                $files = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue
                if ($files.Count -gt 0) {
                    $steamActive = $true
                    Write-Host "Steam downloads still active at: $path"

                    foreach ($file in $files) {
                        $currentSteamFileSizes[$file.FullName] = $file.Length

                        if ($previousSteamFileSizes.ContainsKey($file.FullName)) {
                            if ($file.Length -ne $previousSteamFileSizes[$file.FullName]) {
                                $steamSizeChanged = $true
                            }
                        } else {
                            $steamSizeChanged = $true
                        }
                    }
                }
            }
        }

        if (-not $steamActive) {
            Write-Host 'No active Steam downloads detected.'
        } elseif (-not $steamSizeChanged -and ($previousSteamFileSizes.Count -gt 0)) {
            Write-Host 'Steam files unchanged since last check. Assuming Steam downloads are paused.'
            $steamActive = $false
        }

        # ----- Check Epic -----
        if ($null -ne $epicManifestsPath -and (Test-Path $epicManifestsPath)) {
            $epicManifests = Get-ChildItem $epicManifestsPath -Filter *.item -ErrorAction SilentlyContinue
            foreach ($manifest in $epicManifests) {
                $content = Get-Content $manifest.FullName | Out-String
                if ($content -match '"bIsDownloading"\s*:\s*true') {
                    $epicActive = $true
                    Write-Host "Epic Games download in progress (manifest: $($manifest.Name))"
                }
            }

            $pendingPath = Join-Path $epicManifestsPath 'Pending'
            if (Test-Path $pendingPath) {
                if ((Get-ChildItem $pendingPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
                    $epicActive = $true
                    Write-Host "Epic Games download in progress"
                }
            }
        }

        # ----- Final shutdown condition -----
        if (-not $steamActive -and -not $epicActive) {
            Write-Host 'Both Steam and Epic downloads have completed or are paused. Proceeding with shutdown.'
            break
        }

        # ----- Wait for next loop -----
        $lastCheckTime = (Get-Date).ToString("hh:mmtt")
        $totalSteamDownloadSizeBytes = ($currentSteamFileSizes.Values | Measure-Object -Sum).Sum
        $totalSteamDownloadSizeMB = [math]::Round($totalSteamDownloadSizeBytes / 1MB, 2)
        Write-Host "Checking again in 30 minutes... Last check at $lastCheckTime"
        Write-Host "Current Steam download size: $totalSteamDownloadSizeMB MB"

        $previousSteamFileSizes = $currentSteamFileSizes

        Show-Countdown -Seconds 1800 -Activity "Monitoring Downloads" -Status "Next check in"
        #Start-Sleep -Seconds 30
    }

    Write-Host 'All downloads (Steam and Epic) have completed or are paused. Preparing for shutdown.'
    Show-Countdown -Seconds 10 -Activity "Preparing Shutdown" -Status "Closing Steam soon"
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
    if ($null -eq $totalSeconds) { exit }
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

Show-Countdown -Seconds $steamWaitSeconds -Activity "Waiting before closing Steam" -Status "Pre-shutdown hold"
KillSteam $postSteamWaitSeconds
