# 03-acrobat-prefs.ps1 [-AcceptEula] — quiet Acrobat's first-run prompts and fix WebView2 drawing.
# -AcceptEula records Adobe's license agreement as accepted (the switch IT departments use for
# mass installs). Only pass it if you have read and accept Adobe's terms; without it, Acrobat
# shows the agreement the first time it starts and you click Accept yourself.
param([switch]$AcceptEula)
$ErrorActionPreference = 'Continue'
$marks = '\\host.lan\Data\.acrobat-win-setup'
New-Item -ItemType Directory -Path $marks -Force | Out-Null
Start-Transcript -Path "$marks\03-acrobat-prefs.log" -Force | Out-Null
function Set-Reg($path, $name, $value) {
  if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
  Set-ItemProperty -Path $path -Name $name -Value $value -Type DWord
}
Get-Process Eula, Acrobat -ErrorAction SilentlyContinue | Stop-Process -Force

if ($AcceptEula) {
  Write-Host 'Recording the Adobe EULA as accepted (requested with -AcceptEula)'
  foreach ($root in 'HKCU:\Software\Adobe', 'HKLM:\SOFTWARE\Adobe', 'HKLM:\SOFTWARE\WOW6432Node\Adobe') {
    foreach ($prod in 'Adobe Acrobat', 'Acrobat Reader') { Set-Reg "$root\$prod\DC\AdobeViewer" EULA 1 }
  }
}
Write-Host 'No upsell, no welcome tour, no "make Acrobat your default PDF app" prompt'
foreach ($prod in 'Adobe Acrobat', 'Acrobat Reader') {
  Set-Reg "HKLM:\SOFTWARE\Policies\Adobe\$prod\DC\FeatureLockDown" bAcroSuppressUpsell 1
  Set-Reg "HKLM:\SOFTWARE\Policies\Adobe\$prod\DC\FeatureLockDown" bToggleFTE 1
  Set-Reg "HKLM:\SOFTWARE\Policies\Adobe\$prod\DC\FeatureLockDown" bToggleToDoList 1
  Set-Reg "HKCU:\Software\Adobe\$prod\DC\FTEDialog" iFTEVersion 10
  Set-Reg "HKCU:\Software\Adobe\$prod\DC\FTEDialog" iLastCardShown 0
  Set-Reg "HKCU:\Software\Adobe\$prod\DC\AVAlert\cCheckbox" iAppDoNotTakePDFOwnershipAtLaunchWin10 1
  Set-Reg "HKCU:\Software\Adobe\$prod\DC\AVAlert\cCheckbox" iAppDoNotTakePDFOwnershipAtLaunch 1
}
Write-Host 'WebView2 (draws the Sign dialog and other panels): software rendering inside the VM'
[Environment]::SetEnvironmentVariable('WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS', '--disable-gpu', 'User')

Stop-Transcript | Out-Null
Set-Content "$marks\03-acrobat-prefs.done" 'ok' -Encoding ascii
