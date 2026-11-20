# C:\ProgramData\acrobat-win\shell.ps1 — per-user Windows shell for the Acrobat-only desktop.
# Started at sign-in (via conhost --headless, so no console window).
#  * \\host.lan\Data\open-request.txt present  -> Acrobat-only session: open each requested
#    file in Acrobat (maximized), keep watching for new requests, sign out when Acrobat exits.
#  * no request                                -> normal Windows desktop (explorer).
$req = '\\host.lan\Data\open-request.txt'
$exe = 'C:\Program Files\Adobe\Acrobat DC\Acrobat\Acrobat.exe'
$log = "$env:ProgramData\acrobat-win\shell.log"

function Read-Request {
  for ($i = 0; $i -lt 20; $i++) {          # the share can lag a moment right after sign-in
    if (Test-Path -LiteralPath $req) {
      try {
        $p = [IO.File]::ReadAllText($req, [Text.Encoding]::UTF8).Trim()
        Remove-Item -LiteralPath $req -Force
        return @{ found = $true; path = $p }
      } catch { Start-Sleep -Milliseconds 100 }
    } else { return @{ found = $false } }
  }
  return @{ found = $false }
}

Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool IsZoomed(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, System.IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h, out uint pid);
public delegate bool EnumProc(System.IntPtr h, System.IntPtr l);
public static System.Collections.Generic.List<System.IntPtr> FramesOf(uint[] pids) {
  var r = new System.Collections.Generic.List<System.IntPtr>();
  EnumWindows((h, l) => { uint pid; GetWindowThreadProcessId(h, out pid);
    if (System.Array.IndexOf(pids, pid) >= 0) { var sb = new System.Text.StringBuilder(64); GetClassName(h, sb, 64);
      if (sb.ToString() == "AcrobatSDIWindow") r.Add(h); }
    return true; }, System.IntPtr.Zero);
  return r;
}
'@

# Keep Acrobat's main window maximized, so it always fills the Linux window: the RDP
# desktop follows the Linux window size (/dynamic-resolution), a maximized window
# follows the desktop. Skips minimized windows (the user minimized it on purpose).
function Keep-Maximized {
  # Only Acrobat's document frame windows (class AcrobatSDIWindow), never its dialogs:
  # maximizing the WebView2 "Sign" dialog left it as a blank grey page.
  $pids = [uint32[]]@(Get-Process Acrobat -ErrorAction SilentlyContinue | ForEach-Object { [uint32]$_.Id })
  if (-not $pids) { return }
  foreach ($h in [W.U]::FramesOf($pids)) {
    if ([W.U]::IsWindowVisible($h) -and -not [W.U]::IsZoomed($h) -and -not [W.U]::IsIconic($h)) {
      [W.U]::ShowWindow($h, 3) | Out-Null   # 3 = SW_MAXIMIZE
    }
  }
}

function Open-InAcrobat($path) {
  "$(Get-Date -Format o) open [$path]" | Add-Content $log
  if ($path) { Start-Process -FilePath $exe -ArgumentList "`"$path`"" }
  else       { Start-Process -FilePath $exe }
}

# Wait briefly for the share and the request written just before this session connected.
$first = $null
for ($i = 0; $i -lt 30 -and -not $first; $i++) {
  $r = Read-Request
  if ($r.found) { $first = $r } elseif (Test-Path '\\host.lan\Data') { break } else { Start-Sleep -Milliseconds 200 }
}
if (-not $first) { "$(Get-Date -Format o) no request -> explorer" | Add-Content $log; Start-Process explorer.exe; exit }

Open-InAcrobat $first.path
$seen = $false; $goneSince = $null
while ($true) {
  Start-Sleep -Milliseconds 400
  $r = Read-Request
  if ($r.found) { Open-InAcrobat $r.path }
  Keep-Maximized
  if (Get-Process Acrobat -ErrorAction SilentlyContinue) { $seen = $true; $goneSince = $null }
  elseif ($seen) {
    if (-not $goneSince) { $goneSince = Get-Date }
    elseif (((Get-Date) - $goneSince).TotalSeconds -ge 2) { break }   # Acrobat closed for 2 s
  } elseif (-not $goneSince) { $goneSince = Get-Date }
  elseif (((Get-Date) - $goneSince).TotalSeconds -ge 60) { break }    # Acrobat never started
}
"$(Get-Date -Format o) Acrobat closed -> sign out" | Add-Content $log
logoff
