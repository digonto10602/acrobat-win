# 02-debloat.ps1 — strip the Omarchy Windows VM down to what Adobe Acrobat Reader needs.
# KEEPS: Acrobat's dependencies (WebView2, VC++ runtimes, .NET), crypto + smart-card
# services (certificate signing), print spooler (printing), fonts, RDP + audio,
# winget/App Installer, Microsoft Defender.
# Only Microsoft-published Store apps are removed (Adobe's own AppX parts are never touched).
# Writes a transcript and a marker to \\host.lan\Data\.acrobat-win-setup\.
$ErrorActionPreference = 'Continue'
$marks = '\\host.lan\Data\.acrobat-win-setup'
New-Item -ItemType Directory -Path $marks -Force | Out-Null
Start-Transcript -Path "$marks\02-debloat.log" -Force | Out-Null

function Set-Reg($path, $name, $value, $type = 'DWord') {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  Set-ItemProperty -Path $path -Name $name -Value $value -Type $type
}

Write-Host '== 1. Store apps (AppX): remove everything except frameworks, system parts and the keep list'
$keep = @(
  'Microsoft.DesktopAppInstaller',   # winget
  'Microsoft.VCLibs*', 'Microsoft.UI.Xaml*', 'Microsoft.NET.Native*', 'Microsoft.WindowsAppRuntime*',
  'Microsoft.SecHealthUI',           # Defender UI
  'Microsoft.WindowsNotepad', 'Microsoft.WindowsTerminal',
  'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.StartMenuExperienceHost',
  'MicrosoftWindows.Client.CBS', 'MicrosoftWindows.Client.Core', 'Microsoft.Windows.CloudExperienceHost',
  'Microsoft.AAD.BrokerPlugin', 'Microsoft.AccountsControl', 'Microsoft.Windows.ContentDeliveryManager',
  'windows.immersivecontrolpanel', 'Microsoft.Windows.Search', 'Microsoft.HEIFImageExtension',
  'Microsoft.WebpImageExtension', 'Microsoft.VP9VideoExtensions', 'Microsoft.WebMediaExtensions',
  'Microsoft.LanguageExperiencePack*', 'Microsoft.Windows.PeopleExperienceHost', 'Microsoft.Win32WebViewHost',
  'Microsoft.WindowsAppRuntime.*', 'MicrosoftCorporationII.WinAppRuntime*', 'Microsoft.ApplicationCompatibilityEnhancements'
)
function Test-Keep($name) { foreach ($k in $keep) { if ($name -like $k) { return $true } }; return $false }

Get-AppxProvisionedPackage -Online | Where-Object { $_.PublisherId -eq '8wekyb3d8bbwe' -and -not (Test-Keep $_.DisplayName) } | ForEach-Object {
  Write-Host "  deprovision $($_.DisplayName)"
  Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
}
Get-AppxPackage -AllUsers | Where-Object {
  $_.Publisher -like '*O=Microsoft Corporation*' -and -not $_.IsFramework -and $_.SignatureKind -ne 'System' -and -not $_.NonRemovable -and -not (Test-Keep $_.Name)
} | ForEach-Object {
  Write-Host "  remove $($_.Name)"
  Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
}

Write-Host '== 2. OneDrive'
Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($p in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe",
               "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe") {
  if (Test-Path $p) { Start-Process $p -ArgumentList '/uninstall' -Wait }
}
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OneDrive -ErrorAction SilentlyContinue

Write-Host '== 3. Background services not needed for Acrobat'
$disable = 'DiagTrack', 'dmwappushservice', 'SysMain', 'WSearch', 'MapsBroker', 'lfsvc', 'RetailDemo',
  'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc', 'WerSvc', 'Fax', 'wisvc', 'WbioSrvc',
  'PcaSvc', 'TrkWks', 'RemoteRegistry', 'WMPNetworkSvc', 'icssvc', 'PhoneSvc', 'SEMgrSvc', 'WalletService',
  'diagsvc', 'DPS', 'WdiServiceHost', 'WdiSystemHost'   # edgeupdate kept: it patches WebView2, which Acrobat uses
foreach ($s in $disable) {
  $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
  if ($svc) {
    Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
    Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Host "  disabled $s"
  }
}

Write-Host '== 4. Telemetry, ads, widgets, Copilot, web search, Edge background'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' AllowTelemetry 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' DisableWindowsConsumerFeatures 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' DisableSoftLanding 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' AllowNewsAndInterests 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1
Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' TurnOffWindowsCopilot 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' AllowCortana 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' DisableWebSearch 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' DisableSearchBoxSuggestions 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' StartupBoostEnabled 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' BackgroundModeEnabled 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' AllowGameDVR 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' GlobalUserDisabled 1
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' VisualFXSetting 2
Set-Reg 'HKCU:\Control Panel\Desktop' MenuShowDelay '0' 'String'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' fResetBroken 0

Write-Host '== 5. Windows Update: no automatic download/restart (run it by hand when you choose)'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' NoAutoUpdate 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' NoAutoRebootWithLoggedOnUsers 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode 0

Write-Host '== 6. Scheduled telemetry/maintenance tasks'
$taskPaths = '\Microsoft\Windows\Application Experience\', '\Microsoft\Windows\Customer Experience Improvement Program\',
  '\Microsoft\Windows\Feedback\Siuf\', '\Microsoft\Windows\Maps\', '\Microsoft\Windows\Windows Error Reporting\',
  '\Microsoft\Windows\DiskDiagnostic\', '\Microsoft\Windows\CloudExperienceHost\', '\Microsoft\Windows\Defrag\',
  '\Microsoft\Windows\Autochk\', '\Microsoft\Windows\Maintenance\', '\Microsoft\XblGameSave\'
foreach ($tp in $taskPaths) {
  Get-ScheduledTask -TaskPath $tp -ErrorAction SilentlyContinue | ForEach-Object {
    Disable-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  disabled task $($_.TaskPath)$($_.TaskName)"
  }
}

Write-Host '== 7. Power: no hibernation file, high performance'
powercfg -h off
powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

Write-Host '== 8. Startup apps'
foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run') {
  $props = Get-ItemProperty $k -ErrorAction SilentlyContinue
  if ($props) { $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' -and $_.Name -notmatch 'SecurityHealth' } | ForEach-Object {
    Write-Host "  remove autostart $($_.Name)"; Remove-ItemProperty $k -Name $_.Name -ErrorAction SilentlyContinue } }
}

Write-Host '== 9. Disk cleanup (component store) and TRIM so the host image shrinks'
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
Remove-Item "$env:TEMP\*", "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue

Stop-Transcript | Out-Null
Set-Content -Path "$marks\02-debloat.done" -Value 'ok' -Encoding ascii
