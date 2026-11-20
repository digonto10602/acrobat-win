# check-acrobat.ps1 [-Tag x] [-Pdf path] — record whether everything Acrobat Reader depends on works.
# Writes \\host.lan\Data\.acrobat-win-setup\check-<tag>.txt (one "name=value" per line).
# Note: the open test closes any running Acrobat first.
param([string]$Tag = 'run', [string]$Pdf = '\\host.lan\Data\.acrobat-win-setup\selftest.pdf')
$ErrorActionPreference = 'Continue'
$marks = '\\host.lan\Data\.acrobat-win-setup'
New-Item -ItemType Directory -Path $marks -Force | Out-Null
$out = "$marks\check-$Tag.txt"
$r = [ordered]@{}

$exe = "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe"
$r.acrobat_exe = $exe
$r.acrobat_version = if ($exe -and (Test-Path $exe)) { (Get-Item $exe).VersionInfo.ProductVersion } else { 'MISSING' }

# Services Acrobat relies on (crypto/signing, smart cards, printing, fonts, RDP, audio).
foreach ($s in 'CryptSvc', 'CertPropSvc', 'SCardSvr', 'Spooler', 'FontCache', 'TermService', 'UmRdpService', 'Audiosrv', 'WinDefend', 'w32time') {
  $svc = Get-Service $s -ErrorAction SilentlyContinue
  $r["svc_$s"] = if ($svc) { "$($svc.Status)/$($svc.StartType)" } else { 'absent' }
}
$r.webview2 = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue).pv
$r.printers = ((Get-Printer -ErrorAction SilentlyContinue).Name -join ';')
$r.fonts = (Get-ChildItem "$env:WINDIR\Fonts" -ErrorAction SilentlyContinue).Count
$r.vcredist = ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
  Where-Object DisplayName -like '*Visual C++*').DisplayName -join ';')

# Certificate signing path: can Windows create and use a signing certificate?
try {
  $c = New-SelfSignedCertificate -Subject 'CN=Acrobat VM Self-Test' -CertStoreLocation Cert:\CurrentUser\My `
    -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -NotAfter (Get-Date).AddDays(1)
  $data = [Text.Encoding]::UTF8.GetBytes('acrobat-vm-selftest')
  # Windows PowerShell 5.1: CNG keys are only reachable through these extension methods.
  $priv = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($c)
  $pub = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($c)
  $sig = $priv.SignData($data, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $ok = $pub.VerifyData($data, $sig, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $r.crypto_sign_verify = $ok
  Remove-Item "Cert:\CurrentUser\My\$($c.Thumbprint)" -Force
} catch { $r.crypto_sign_verify = "ERROR: $_" }

# Acrobat itself: open a PDF, check it stays up and shows the file.
$pdf = $Pdf
$stem = [IO.Path]::GetFileNameWithoutExtension($pdf)
if ($exe -and (Test-Path $pdf)) {
  Get-Process Acrobat, AcroRd32 -ErrorAction SilentlyContinue | Stop-Process -Force
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Start-Process -FilePath $exe -ArgumentList "`"$pdf`""
  $title = ''
  while ($sw.Elapsed.TotalSeconds -lt 60) {
    $p = Get-Process Acrobat, AcroRd32 -ErrorAction SilentlyContinue | Where-Object MainWindowTitle -like "*$stem*" | Select-Object -First 1
    if ($p) { $title = $p.MainWindowTitle; break }
    Start-Sleep -Milliseconds 250
  }
  $r.open_pdf_seconds = if ($title) { [math]::Round($sw.Elapsed.TotalSeconds, 2) } else { 'TIMEOUT' }
  $r.window_title = $title
  Start-Sleep 5
  $r.acrobat_alive_after_5s = [bool](Get-Process Acrobat, AcroRd32 -ErrorAction SilentlyContinue)
  $r.acrobat_procs = (Get-Process Acrobat, AcroRd32, AcroCEF, RdrCEF -ErrorAction SilentlyContinue).Count
  Get-Process Acrobat, AcroRd32 -ErrorAction SilentlyContinue | Stop-Process -Force
} else { $r.open_pdf_seconds = 'SKIPPED (no exe or no test pdf)' }

$os = Get-CimInstance Win32_OperatingSystem
$r.ram_free_MB = [int]($os.FreePhysicalMemory / 1024)
$r.C_used_GB = [math]::Round((Get-PSDrive C).Used / 1GB, 1)
$r.appx = (Get-AppxPackage -AllUsers).Count
$r.services_running = (Get-Service | Where-Object Status -eq Running).Count
$r.processes = (Get-Process).Count
$r.time = Get-Date -Format o
$r.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content -Path $out -Encoding ascii
Set-Content "$marks\check-acrobat.done" 'ok' -Encoding ascii
