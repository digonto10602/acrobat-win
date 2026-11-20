# 05-install-shell.ps1 — make shell.ps1 this user's Windows shell (Acrobat-only sessions).
# Expects shell.ps1 next to it in \\host.lan\Data (install.sh copies it there).
$marks = '\\host.lan\Data\.acrobat-win-setup'
New-Item -ItemType Directory -Path $marks -Force | Out-Null
$dir = "$env:ProgramData\acrobat-win"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
Copy-Item '\\host.lan\Data\shell.ps1' "$dir\shell.ps1" -Force
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile("$dir\shell.ps1", [ref]$null, [ref]$errs)
if ($errs.Count) { Set-Content "$marks\05-install-shell.done" "failed: shell.ps1 parse errors: $($errs | ForEach-Object { $_.Message })" -Encoding ascii; exit 1 }
$k = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
$cmd = "conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dir\shell.ps1`""
Set-ItemProperty -Path $k -Name Shell -Value $cmd -Type String
Set-Content "$marks\05-install-shell.done" 'ok' -Encoding ascii
# Sign out every session of this user so the next connection starts with the new shell.
quser 2>$null | Select-String -NotMatch '^>|USERNAME' | ForEach-Object {
  $id = ($_ -split '\s+') | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1
  if ($id) { logoff $id }
}
logoff
