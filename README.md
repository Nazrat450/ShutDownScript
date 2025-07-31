🖥️ Shutdown Scheduler PowerShell Script
This script allows you to schedule a Windows system shutdown with optional Steam download monitoring and staged delay handling.

📦 Features
⏱ Schedule shutdown based on:

Duration (hours and minutes)

Specific time (24-hour format)

After Steam downloads complete (auto-detects active download folders)

🧠 Intelligent delay logic:

Waits 75% of total time, then shuts down Steam

Waits remaining time before shutdown

💬 Countdown before final shutdown

🔐 Optional execution policy bypass for first run

🛠️ Requirements
PowerShell 5.1+

Admin privileges (required to execute shutdown and stop Steam and Epic)

🚀 How to Use
Open PowerShell as Administrator

Run the script:

.\shutdown.ps1
Follow prompts:

Choose a scheduling option:

1 for delay

2 for specific time

3 for shutdown after Steam downloads

Confirm execution (Y)

Provide time values as requested

📂 Steam Monitoring
When using option 3, the script checks the following directories:

C:\Program Files (x86)\Steam\steamapps\downloading
E:\SteamLibrary\steamapps\downloading
You can modify these paths inside the script ($steamPaths) if your Steam library is elsewhere.

It checks every 30 minutes for active downloads. Once all are complete:
Note currently can not tell if Epic downloads are paused.

Waits 10 seconds

Closes Steam

Waits 5 minutes

Initiates shutdown

🧪 Example Usages
Shutdown in 1 hour and 30 minutes:


Choose option 1 → Enter: 1h, 30m
Shutdown at 23:45:


Choose option 2 → Enter: 23:45
Shutdown after downloads finish:


Choose option 3 → Monitors until Steam and Epic downloads stop
🛑 Permissions Note
If you see a policy error like:


cannot be loaded because running scripts is disabled
Run this (one-time setup):

Set-ExecutionPolicy Bypass -Scope Process
