# 04-no-autologon.ps1 — stop Windows signing the user in on its own screen at boot.
# Why: an RDP connection for the same user takes over that existing session (normal
# desktop) instead of signing in fresh, so the Acrobat-only shell would never start.
# Side effect: the dockur web viewer (port 8006) shows the sign-in screen.
$marks = '\\host.lan\Data\.acrobat-win-setup'
New-Item -ItemType Directory -Path $marks -Force | Out-Null
$k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty -Path $k -Name AutoAdminLogon -Value '0' -Type String
Remove-ItemProperty -Path $k -Name DefaultPassword -ErrorAction SilentlyContinue   # plain-text password used by auto sign-in
Remove-ItemProperty -Path $k -Name AutoLogonCount -ErrorAction SilentlyContinue
"ok AutoAdminLogon=$((Get-ItemProperty $k).AutoAdminLogon) DefaultPassword_present=$([bool](Get-ItemProperty $k).DefaultPassword)" |
  Set-Content "$marks\04-no-autologon.done" -Encoding ascii
# Sign out every other session of this user (e.g. the console session from boot).
quser 2>$null | Select-String -NotMatch '^>|USERNAME' | ForEach-Object {
  $id = ($_ -split '\s+') | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1
  if ($id) { logoff $id }
}
logoff
