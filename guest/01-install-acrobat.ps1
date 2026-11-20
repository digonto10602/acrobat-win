# 01-install-acrobat.ps1 — install Adobe Acrobat Reader and prepare Windows for acrobat-win.
# Runs inside the Windows VM (as the VM user, elevated: dockurr/windows turns UAC off).
$ErrorActionPreference = 'Stop'
$marks = '\\host.lan\Data\.acrobat-win-setup'
New-Item -ItemType Directory -Path $marks -Force | Out-Null
Start-Transcript -Path "$marks\01-install-acrobat.log" -Force | Out-Null
trap { Write-Host "FAILED: $_"; Stop-Transcript | Out-Null; Set-Content "$marks\01-install-acrobat.done" 'failed' -Encoding ascii; exit 1 }

Write-Host '1/4 Use the classic console (a Windows Terminal window outlives its script and keeps RDP sessions open)...'
$c = 'HKCU:\Console\%%Startup'
New-Item -Path $c -Force | Out-Null
Set-ItemProperty -Path $c -Name DelegationConsole  -Value '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'
Set-ItemProperty -Path $c -Name DelegationTerminal -Value '{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}'

Write-Host '2/4 Installing Adobe Acrobat Reader (64-bit) with winget...'
winget install --id Adobe.Acrobat.Reader.64-bit --exact --silent `
  --accept-package-agreements --accept-source-agreements
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {  # -1978335189 = already installed
  throw "winget failed with exit code $LASTEXITCODE"
}
$exe = "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
if (-not (Test-Path $exe)) { throw "Acrobat not found at $exe after install" }

Write-Host '3/4 Allowing RemoteApp (used only by the maintenance runner, lib/winrun)...'
foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList',
               'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services') {
  New-Item -Path $k -Force | Out-Null
}
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList' fDisabledAllowList 1 -Type DWord
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' fAllowUnlistedRemotePrograms 1 -Type DWord

Write-Host '4/4 Resync the clock at every sign-in/connect (the VM is frozen between uses)...'
Set-Service w32time -StartupType Automatic
Start-Service w32time
w32tm /config /manualpeerlist:"time.windows.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /update | Out-Null
$cls = Get-CimClass -Namespace ROOT\Microsoft\Windows\TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
$onConnect = New-CimInstance -CimClass $cls -ClientOnly
$onConnect.StateChange = 3   # TASK_SESSION_REMOTE_CONNECT
$onConnect.Enabled = $true
$onLogon = New-ScheduledTaskTrigger -AtLogOn
$action = New-ScheduledTaskAction -Execute 'w32tm.exe' -Argument '/resync /force'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
Register-ScheduledTask -TaskName 'ResyncClockOnConnect' -Trigger $onConnect, $onLogon `
  -Action $action -Principal $principal -Force | Out-Null

Write-Host "Done. Acrobat: $exe ($((Get-Item $exe).VersionInfo.ProductVersion))"
Stop-Transcript | Out-Null
Set-Content "$marks\01-install-acrobat.done" 'ok' -Encoding ascii
