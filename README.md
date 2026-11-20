# acrobat-win

**Adobe Acrobat Reader on Linux, as if it were a native app**, running inside a stripped-down Windows 11 virtual machine that is frozen whenever you are not using it.

- Opens from the app launcher, from "Open with → Adobe Acrobat Reader" in a file manager, or with `acrobat-win file.pdf`.
- Shows only Acrobat, in an ordinary Linux window that tiles, resizes, maximizes and floats like any other app. There is no Windows desktop, taskbar or start menu.
- Every save in Acrobat, including filled forms and certificate-signed copies, lands back in the PDF's original Linux folder.
- When Acrobat is closed, Windows signs out and the VM is **frozen**: it uses 0 % CPU, and its memory can be swapped out. Unfreezing takes under a second.

Built and tested on [Omarchy](https://omarchy.org) (Arch Linux + Hyprland), on top of Omarchy's own Windows VM (`omarchy windows vm`). The second half of this README walks through **how it was built and why each piece is there**. Read it if you want to do the same for another Windows-only program.

> Unofficial. Not affiliated with or endorsed by Adobe or Microsoft. You need your own valid Windows install/licence (Omarchy's VM tool handles the download) and must accept Adobe's licence terms for Acrobat Reader.

---

## Contents

1. [What you get](#what-you-get)
2. [Requirements](#requirements)
3. [Install](#install)
4. [Usage](#usage)
5. [Files and what each one does](#files-and-what-each-one-does)
6. [Properties and measurements](#properties-and-measurements)
7. [Troubleshooting](#troubleshooting)
8. [Uninstall](#uninstall)
9. [Security notes](#security-notes)
10. [How this was built: running a Windows app on Linux through a stripped VM](#how-this-was-built-running-a-windows-app-on-linux-through-a-stripped-vm)
11. [Adapting this to another Windows app](#adapting-this-to-another-windows-app)

---

## What you get

| Feature | How |
|---|---|
| Acrobat in its own Linux window | Full-screen RDP session whose Windows "shell" is a small script that only runs Acrobat |
| Resizes like a native window | FreeRDP `/dynamic-resolution`: the Windows desktop resizes to the window, and Acrobat is kept maximized inside it |
| Open with / default PDF app | `.desktop` entry with `MimeType=application/pdf` |
| Saving and digital signatures work | The PDF is copied to the VM's Samba share and synced back to its folder on every save |
| Several PDFs | A second `acrobat-win other.pdf` opens as a new tab in the same window |
| Fast start | VM is booted at login and frozen (`docker pause`); opening Acrobat unfreezes it |
| No idle cost | Closing Acrobat signs Windows out and freezes the VM again |
| Smaller Windows | Optional debloat: removes Microsoft Store apps, telemetry, background services, automatic updates |

## Requirements

- **Omarchy** with Hyprland's Lua config (tested: Hyprland 0.56.2). Other Arch + Hyprland setups need small changes; see [Adapting](#adapting-this-to-another-windows-app).
- **Omarchy's Windows VM, installed**: run `omarchy windows vm install` first and let it finish. It uses the [dockur/windows](https://github.com/dockur/windows) container, KVM, a disk image in `~/.windows` and a shared folder `~/Windows`. Tested with 4 GB RAM, 4 CPU cores and a 64 GB disk.
- Packages: `freerdp` (provides `xfreerdp3`, tested 3.32.2), `inotify-tools`, `libnotify`, `docker`, `polkit`, `sudo`.
  ```bash
  omarchy pkg add freerdp inotify-tools libnotify
  ```
- Roughly 16 GB of host disk for the Windows image (measured: `du -sh ~/.windows` → 16 GB after setup and debloat; the image file is sparse, with a nominal size of 64 GiB).

## Install

```bash
git clone https://github.com/digonto10602/acrobat-win.git
cd acrobat-win
./install.sh                       # Acrobat shows its licence once; you click Accept
# or
./install.sh --accept-adobe-eula   # records Adobe's EULA as accepted for you
```

| Option | Effect |
|---|---|
| `--accept-adobe-eula` | Writes the registry values used to pre-accept the EULA in managed (IT-deployed) installs. Use only if you have read and accept [Adobe's terms](https://www.adobe.com/legal/terms.html). |
| `--skip-debloat` | Leave Windows as installed (no app/service removal, updates stay on). |
| `--no-warm` | Don't start and freeze the VM at login; it starts on first use instead (15–60 s the first time). |
| `--linux-only` | Install only the Linux side (launcher, helper, desktop entry, Hyprland rules). |

What `install.sh` does, in order:

1. Checks the commands it needs and that Omarchy's VM is installed.
2. Copies `acrobat-win` to `~/.local/bin`, the maintenance runner and Windows scripts to `~/.local/share/acrobat-win/`, and the desktop entry to `~/.local/share/applications/`.
3. Installs the **freeze helper** `/usr/local/bin/omarchy-windows-freeze`, plus a sudoers rule letting your user run exactly `pause`, `unpause` and `status` without a password. It asks for your sudo password once, and the rule is checked with `visudo`.
4. Adds `~/.config/hypr/acrobat-win.lua` and a `require` line in `hyprland.lua` (a backup is made first).
5. Starts the VM and runs the Windows-side scripts one by one through RDP RemoteApp. Their windows go to a hidden workspace. Each script writes a log and a `*.done` marker to `~/Windows/.acrobat-win-setup/`:

   | Script | What it changes inside Windows |
   |---|---|
   | `01-install-acrobat.ps1` | `winget install Adobe.Acrobat.Reader.64-bit`; RemoteApp allowed for unlisted programs; clock resync task on every connect; classic console instead of Windows Terminal |
   | `02-debloat.ps1` | removes Microsoft Store apps (keeps frameworks, winget, Defender UI, Notepad, Terminal); uninstalls OneDrive; disables up to 27 background services; turns off telemetry, widgets, Copilot, web search, automatic updates; disables telemetry/maintenance scheduled tasks; hibernation off; component store cleanup + TRIM |
   | `03-acrobat-prefs.ps1` | no upsell, welcome tour, to-do cards or "make default" prompt; WebView2 software rendering; EULA only with `--accept-adobe-eula` |
   | `check-acrobat.ps1` | records Acrobat's dependencies (crypto, smart card, print spooler, fonts, WebView2, VC++), runs a sign/verify with a throw-away certificate, opens a test PDF |
   | `04-no-autologon.ps1` | stops Windows signing itself in on the console at boot |
   | `05-install-shell.ps1` | makes `shell.ps1` this user's Windows shell (Acrobat-only sessions) |

6. Freezes the VM.

To make it your default PDF app:

```bash
xdg-mime default acrobat-reader-win.desktop application/pdf
```

## Usage

```bash
acrobat-win file.pdf     # open a PDF (a second call adds a tab to the open window)
acrobat-win              # open Acrobat with no file
acrobat-win --status     # VM state: running | paused | exited | absent
acrobat-win --warm       # boot the VM, wait 45 s, freeze it (run at login by Hyprland)
```

- **Signing:** use Acrobat's *All tools → Use a certificate → Digitally sign* (or click a signature field), then save. The signed file appears next to the original. Check it on Linux with `pdfsig signed.pdf` (from `poppler`).
- **Saving over a file that changed meanwhile:** the old Linux copy is moved to `~/.local/state/acrobat-win/backups/` first. Every sync-back is logged in `~/.local/state/acrobat-win/sync.log`.
- **Closing:** close Acrobat (× inside Acrobat, or close the Linux window). Windows signs out and the VM freezes.
- **The full Windows desktop:** `omarchy windows vm launch` still works. Because auto sign-in is off, it shows the Windows sign-in screen; use the password from `~/.config/windows/credentials`.
- **Windows updates** are off after debloat. To update, open the full desktop, run Windows Update by hand, and reboot the VM.

## Files and what each one does

| Repo path | Installed to | Role |
|---|---|---|
| `bin/acrobat-win` | `~/.local/bin/acrobat-win` | Launcher: unfreeze or start the VM, stage the PDF, open the RDP window, sync saves back, freeze the VM on exit |
| `lib/winrun` | `~/.local/share/acrobat-win/winrun` | Runs one PowerShell script inside Windows through a RemoteApp session (used for setup and maintenance) |
| `system/omarchy-windows-freeze` | `/usr/local/bin/` (root, 0755) | Only `docker pause` / `unpause` / `inspect` of the `omarchy-windows` container |
| (generated) | `/etc/sudoers.d/acrobat-win-freeze` (0440) | Lets your user run the three helper commands without a password |
| `desktop/acrobat-reader-win.desktop` | `~/.local/share/applications/` | Launcher entry, "Open with" for PDFs |
| `hypr/acrobat-win.lua` | `~/.config/hypr/acrobat-win.lua` | Hides maintenance windows; starts and freezes the VM at login |
| `guest/shell.ps1` | `C:\ProgramData\acrobat-win\shell.ps1` | The Windows "shell": opens requested PDFs in Acrobat, keeps Acrobat maximized, signs out when Acrobat closes |
| `guest/0*.ps1`, `check-acrobat.ps1` | run once from `\\host.lan\Data` | Setup steps (table above) |
| `guest/uninstall-shell.ps1` | run by `uninstall.sh` | Restores the normal Windows desktop for the user |
| `guest/selftest.pdf` | `~/Windows/.acrobat-win-setup/` | One-page PDF used by the self-check |

Runtime state (Linux):

| Path | Contents |
|---|---|
| `~/Windows/open-request.txt` | The path of the PDF to open, written by the launcher and consumed by `shell.ps1` |
| `~/Windows/acrobat/<id>/` | Staged copies of PDFs; `<id>` is the first 12 hex digits of the SHA-1 of the original folder path |
| `~/.local/state/acrobat-win/stage/<id>.dir` | Which Linux folder each staging folder belongs to |
| `~/.local/state/acrobat-win/sync.log` | One line per file copied back |
| `~/.local/state/acrobat-win/backups/` | Linux files replaced by a sync-back |
| `~/.local/state/acrobat-win/client.log` | FreeRDP output of the last session |
| `C:\ProgramData\acrobat-win\shell.log` | What `shell.ps1` opened and when it signed out |

## Properties and measurements

Measured on one machine (Intel i7-12700KF, 31 GiB RAM, NVMe SSD, Windows 11 Pro VM with 4 GB RAM and 4 cores). Each timing is from one or two runs, so expect a spread of roughly ±1 s.

| Property | Value | How it was measured |
|---|---|---|
| Acrobat window appears (VM frozen) | 0.26 s | time from `acrobat-win file.pdf` to the window in `hyprctl clients` |
| PDF picked up by Windows (VM frozen) | 2.8–5.5 s | time until `open-request.txt` disappeared (consumed by `shell.ps1`) |
| Cold start of the VM after host boot | ≈ 12 s until Omarchy reports "started", plus ≈ 30–60 s until Windows accepts sign-ins | `time pkexec /usr/bin/omarchy-windows-vm __priv up_wait` |
| CPU use while frozen | 0 % | `docker pause` stops all VM processes (cgroup freezer) |
| RAM while frozen | stays allocated (up to the VM's 4 GB), but can be swapped out under memory pressure | see [Freeze when idle](#5-freeze-when-idle-and-what-happens-to-the-memory) |
| Windows Store apps (AppX packages) | 108 → 64 | `check-acrobat.ps1` before/after `02-debloat.ps1` |
| Running Windows services | 103 → 95 (up to 27 set to Disabled, where present) | same |
| Windows C: drive used before debloat | 22.6 GB | same (`C_used_GB`) |
| Host disk used by the VM image | 16 GB | `du -sh ~/.windows` |
| Acrobat Reader version tested | 26.003.22110 (64-bit) | `check-acrobat.ps1` |
| WebView2 runtime | 157.0.4341.60 | same |
| Certificate signature | valid, SHA-256, whole document covered | `pdfsig` on a PDF signed in Acrobat |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| "Windows VM is not installed" | Run `omarchy windows vm install` first. |
| Nothing happens for ~1 min after login, or on first use | The VM is booting (cold start). `acrobat-win --status` shows the state. |
| A grey or blank window | Close it and retry. If it persists, check `~/.local/state/acrobat-win/client.log`. |
| Grey "Sign" dialog | WebView2 GPU drawing: re-run `03-acrobat-prefs.ps1` (`./install.sh` re-runs everything). |
| "The document could not be saved. An unexpected network error occurred." | You opened the file from `\\tsclient\…`. Open PDFs through `acrobat-win` so they are staged on the Samba share. |
| "Could not sign" on one particular PDF | Some hand-made or damaged PDFs can't take a signature field. Re-save the PDF (for example print to PDF, or `qpdf in.pdf out.pdf`) and try again. |
| Saved file not in the original folder | See `~/.local/state/acrobat-win/sync.log`. Only `.pdf` files saved directly in the staging folder are synced. |
| Windows desktop appears instead of Acrobat | Windows signed itself in on the console (auto sign-in back on). Re-run `./install.sh`. |
| VM stays frozen and `omarchy windows vm` misbehaves | `sudo /usr/local/bin/omarchy-windows-freeze unpause` |
| Windows clock wrong after a long freeze | It is resynced on every connection (scheduled task `ResyncClockOnConnect`). Signature timestamps depend on it. |
| After an Omarchy update the VM no longer starts from `acrobat-win` | The launcher uses Omarchy's internal `omarchy-windows-vm __priv up_wait`. Check whether it was renamed and adjust `ensure_running` in `bin/acrobat-win`. |

## Uninstall

```bash
./uninstall.sh              # also restores the normal Windows desktop for the VM user
./uninstall.sh --linux-only # Linux side only
```

This leaves the VM, Acrobat inside it, and the debloat changes in place. To remove Windows entirely, run `omarchy windows vm remove`. Your sync log and backups in `~/.local/state/acrobat-win/` are kept.

## Security notes

- The VM's RDP port is bound to `127.0.0.1` by Omarchy, so nothing outside your machine can connect.
- The Windows password stays in Omarchy's `~/.config/windows/credentials`. Both scripts send it to FreeRDP over standard input (`/args-from:stdin`), so it never appears in `ps` output.
- `04-no-autologon.ps1` removes the plain-text `DefaultPassword` that auto sign-in stores in the Windows registry.
- The sudoers rule allows only three exact commands of a root-owned script that touches one container. Joining the `docker` group would give full root.
- `/cert:ignore` skips checking the VM's self-signed RDP certificate. That is acceptable for a loopback-only connection, but don't copy it to remote connections.
- Windows automatic updates are **off** after debloat, and the VM is only reachable from the host. Run Windows Update by hand now and then, and update Acrobat from its Help menu.

---

## How this was built: running a Windows app on Linux through a stripped VM

This is the story of the build in the order it happened, including the dead ends. Each step explains *why* a piece exists. If you want to do the same for another program, this section matters more than the scripts.

### 0. The goal and the options

The goal was to fill and **digitally sign** PDF forms with Adobe Acrobat Reader on Linux, and have it feel like a native app: a launcher entry, "Open with", its own window, and a start in seconds.

| Option | Verdict |
|---|---|
| Native Linux PDF apps (Okular, Evince) | Good for viewing and simple signing, but some forms (XFA, Adobe-specific JavaScript) and some workflows need Acrobat itself |
| Wine | Recent Acrobat versions depend on a Chromium-based component (WebView2) and protected-mode sandboxing that Wine handles poorly |
| Windows VM + RDP | Runs the real program unmodified. The cost is RAM, disk and start-up time. This project is about removing those costs. |

### 1. Get a Windows VM cheaply: reuse what the distro ships

Omarchy already ships `omarchy windows vm`. It runs the [dockur/windows](https://github.com/dockur/windows) container, which downloads Windows 11 from Microsoft, installs it unattended inside QEMU/KVM (the Linux kernel's hardware virtualization), and exposes:

- RDP (Remote Desktop Protocol) on `127.0.0.1:3389`, the way to see and control Windows;
- a web viewer on `127.0.0.1:8006` (useful for watching the install);
- a shared folder: Linux `~/Windows` is `\\host.lan\Data` inside Windows, served over Samba (the Windows file-sharing protocol);
- a privileged start-up path that sets up the disk mounts correctly after a host reboot.

Lesson: **don't build your own VM plumbing when the platform already has a hardened one.** This project never edits Omarchy's files. It only calls the tool's start-up entry point (`pkexec omarchy-windows-vm __priv up_wait`), which is internal and could change in an Omarchy update.

### 2. Strip Windows down to what the app needs

A stock Windows 11 runs about 100 services and a hundred Store apps that a single-purpose VM never uses. They cost RAM, CPU after every unfreeze, disk, and surprise reboots for updates. `02-debloat.ps1` removes:

- **Store apps published by Microsoft only.** The first version removed every non-framework AppX package and also deleted *Adobe's own* AppX component (`AdobeAcrobatReaderCoreApp`), which Acrobat needs. Restricting removal to Microsoft's publisher ID fixed it. Lesson: **filter by publisher, not by name.**
- **Services** for telemetry, search indexing, prefetch (SysMain), maps, Xbox, biometrics, error reporting and diagnostics. Kept on purpose: cryptographic services, the smart-card service and certificate propagation (signing with a certificate or smart card needs them), the print spooler, fonts, RDP, audio, Defender, and `edgeupdate` (it updates WebView2, which Acrobat uses to draw parts of its interface).
- **Automatic Windows Update**, so the VM never reboots or downloads in the background. You update by hand.
- **Telemetry, widgets, Copilot, web search**, the hibernation file, then a component-store cleanup and TRIM so the sparse disk image on Linux shrinks.

To make sure the cleanup broke nothing, `check-acrobat.ps1` ran **before and after** it. It records Acrobat's dependencies, does a real sign-and-verify with a throw-away certificate, and opens a PDF. Lesson: **write the dependency check before you start deleting things.**

### 3. Show one app instead of a desktop: RemoteApp, and why it was dropped

RDP has a mode called **RemoteApp** (also called RAIL) in which only one program's windows are sent, each becoming a separate Linux window. This is how [WinApps](https://github.com/winapps-org/winapps) works, and it was the first plan.

With FreeRDP 3.32.2 under Hyprland (Wayland, through XWayland), Acrobat's RemoteApp windows were **blank, black or showed stale dialogs**. This happened with every graphics codec tried (AVC444, AVC420, RemoteFX, progressive, `-gfx`, `hidef:off`). It matches a known FreeRDP regression ([FreeRDP issue #12485](https://github.com/FreeRDP/FreeRDP/issues/12485)). RemoteApp is still fine for short, invisible maintenance scripts, which is what `lib/winrun` uses it for.

The alternative that works is a normal **full-desktop RDP session in which the desktop is only Acrobat**:

- Windows lets each user have their own **shell**, the program started at sign-in (normally `explorer.exe`, which draws the taskbar and desktop). It is set in `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`. Here it is a PowerShell script (`shell.ps1`) started through `conhost.exe --headless`, so no console window ever shows.
- RDP's own "alternate shell" setting (`/shell:` in FreeRDP) would be the obvious tool, but **Windows 11 Pro ignores it**. The per-user Winlogon shell is honoured.
- FreeRDP's `/dynamic-resolution` makes the Windows desktop follow the Linux window size, so tiling, resizing, maximize and float all behave like a native window. `shell.ps1` keeps Acrobat's main window maximized inside that desktop.

### 4. Hand files to the app, and get saves back

The obvious way to share files is RDP **drive redirection**: FreeRDP's `/drive:home,$HOME` makes your home folder appear as `\\tsclient\home` in Windows. Opening worked, but **saving or signing failed** with *"The document could not be saved. An unexpected network error occurred."* Acrobat saves by writing a temporary file and renaming it, and that file-system pattern breaks over RDP's file channel.

The fix uses the Samba share Omarchy already provides:

1. The launcher copies `file.pdf` to `~/Windows/acrobat/<id>/file.pdf`. `<id>` is derived from the original folder, so files with the same name in different folders don't collide.
2. It writes the Windows path (`\\host.lan\Data\acrobat\<id>\file.pdf`) to `~/Windows/open-request.txt`. `shell.ps1` polls for that file every 0.4 s, opens it in Acrobat and deletes it. A second request while Acrobat is open becomes a new tab.
3. On Linux, `inotifywait` watches the staging folder. Every finished write (`close_write`) or rename into it (`moved_to`) of a `.pdf` is copied back to the original folder: first to a temporary name, then renamed, so a reader never sees half a file. An existing different file is backed up first. `Save As → "form signed.pdf"` therefore lands next to `form.pdf`.
4. When the session ends cleanly, the staging folder is emptied.

Lesson: **for anything that writes files, use the VM's real network share, not RDP drive redirection.**

### 5. Freeze when idle, and what happens to the memory

Booting Windows takes 30–60 s, which is too slow for "open a PDF". Keeping it running costs CPU and battery. The middle ground is to **freeze** it: `docker pause` puts every process of the container, QEMU included, into the kernel's cgroup freezer. A frozen VM:

- uses no CPU;
- keeps its RAM allocated, but that RAM is ordinary process memory, so under memory pressure Linux swaps it out (on Omarchy: first to zram, compressed RAM swap, then to the swap file) and brings it back on demand;
- resumes in under a second, with Windows unaware that time passed except for its clock.

Pieces involved:

- `docker` normally needs root, and the `docker` group is equivalent to root. So a tiny root-owned helper (`omarchy-windows-freeze`) does only `pause`, `unpause` and `status` of that one container, and a sudoers rule allows exactly those three calls without a password.
- At login, `acrobat-win --warm` boots the VM, waits, and freezes it, so the first launch of the day is also fast.
- After a freeze the Windows clock is behind. A scheduled task runs `w32tm /resync /force` on every RDP connect. This matters because certificate signatures carry the signing time.
- When Acrobat closes, `shell.ps1` signs the Windows user out. FreeRDP then exits with `LOGOFF_BY_USER`, and the launcher syncs, cleans up and freezes the VM. Closing the Linux window instead also freezes it; the Windows session is left to be reused next time.

### 6. The traps found along the way

| Trap | Symptom | Fix |
|---|---|---|
| Console auto sign-in | The RDP session took over the user's existing console session (normal desktop), so the Acrobat-only shell never started and requests were never read | `04-no-autologon.ps1` turns auto sign-in off and removes the stored password |
| Windows Terminal | Console windows opened by maintenance scripts kept RemoteApp sessions alive after the script ended | Make the classic `conhost` the default console (`HKCU\Console\%%Startup` delegation keys) |
| Acrobat first-run screens | EULA, welcome tour, "make Acrobat your default", upsell cards popping up in the single-app session | Adobe's documented `FeatureLockDown` policy values and per-user `FTEDialog`/`AVAlert` values (`03-acrobat-prefs.ps1`); the EULA only with explicit opt-in |
| Maximizing the wrong window | A grey, empty "Sign" panel (most likely cause; it did not recur after this fix) | Only maximize windows of Acrobat's main frame class `AcrobatSDIWindow`, never dialogs; WebView2 drawn without GPU (`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-gpu`) |
| FreeRDP ignores SIGTERM | Stale RDP windows after a `timeout` | Use `SIGKILL` (`timeout -s KILL`) for unattended runs |
| Kerberos | FreeRDP 3 tries Kerberos before NTLM and stalls on the host's `/etc/krb5.conf` | A realm-less `krb5.conf` via `KRB5_CONFIG` (the same trick Omarchy uses) |
| Debloat too greedy | Acrobat broken after cleanup | Remove only Microsoft-published AppX; check dependencies before and after |
| Hand-made test PDF | "Could not sign" on one file, while a PDF from LibreOffice signed fine | Test with real-world PDFs, not just a minimal hand-written one |

### 7. Result

From the user's side, Acrobat behaves like a Linux app that takes a few seconds to open a document. From the system's side, it is a frozen 4 GB VM that costs nothing until used.

## Adapting this to another Windows app

The design is not Acrobat-specific. To run another program the same way:

1. **VM:** Omarchy's `omarchy windows vm`, or [dockur/windows](https://github.com/dockur/windows) directly on other distributions. You then need your own way to start the container and to find RDP credentials.
2. **Install the app** with `winget` from a script run through `lib/winrun` (or once by hand in the full desktop).
3. **Debloat** with `02-debloat.ps1`, after checking its *keep* lists against the app's needs. Write the app's own `check-*.ps1` first and run it before and after.
4. **Shell:** in `guest/shell.ps1`, change `$exe` and the window class used to find the main window. You can find the class with a tool like Spy++ or `GetClassName` from PowerShell. Keep the sign-out-when-closed logic.
5. **Launcher:** in `bin/acrobat-win`, change `WM_CLASS`, the window title, and the file filter in `sync_back` (it only syncs `*.pdf`).
6. **Desktop entry:** change `Name`, `MimeType`, `Icon` and `StartupWMClass`.
7. If FreeRDP's RemoteApp renders correctly for your app and version, RemoteApp gives true per-window integration. Check the FreeRDP issue above before choosing.

## Credits and licence

- [Omarchy](https://omarchy.org) for the Windows VM tooling, and [dockur/windows](https://github.com/dockur/windows) for the container underneath it.
- [FreeRDP](https://www.freerdp.com/) for the RDP client.
- Idea of using RDP RemoteApp for Linux integration: [WinApps](https://github.com/winapps-org/winapps).
- Built with help from Claude Code (Anthropic).

MIT licence, see [LICENSE](LICENSE). Adobe, Acrobat and Acrobat Reader are trademarks of Adobe; Windows is a trademark of Microsoft.
