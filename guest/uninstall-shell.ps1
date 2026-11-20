# uninstall-shell.ps1 — give this Windows user the normal desktop (explorer) back.
$marks = '\\host.lan\Data\.acrobat-win-setup'
New-Item -ItemType Directory -Path $marks -Force | Out-Null
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -ErrorAction SilentlyContinue
Remove-Item "$env:ProgramData\acrobat-win" -Recurse -Force -ErrorAction SilentlyContinue
[Environment]::SetEnvironmentVariable('WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS', $null, 'User')
Set-Content "$marks\uninstall-shell.done" 'ok' -Encoding ascii
logoff
