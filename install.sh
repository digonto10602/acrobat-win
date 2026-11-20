#!/bin/bash
# install.sh — set up acrobat-win: Adobe Acrobat Reader from Omarchy's Windows VM,
# in its own Linux window, frozen when idle.
#
#   ./install.sh [--accept-adobe-eula] [--skip-debloat] [--no-warm] [--linux-only]
#
#   --accept-adobe-eula  record Adobe's license agreement as accepted inside Windows.
#                        Only use it if you have read and accept Adobe's terms
#                        (https://www.adobe.com/legal/terms.html). Without it, Acrobat
#                        shows the agreement on first start and you click Accept.
#   --skip-debloat       do not strip Windows (keep all Store apps, services, updates).
#   --no-warm            do not boot+freeze the VM at login (start it on first use).
#   --linux-only         install the Linux side only; skip everything inside Windows.
#
# Prerequisite: `omarchy windows vm install` has finished (Windows is installed).
# Re-running is safe: every step overwrites its previous result.
set -euo pipefail

ACCEPT_EULA=0 DEBLOAT=1 WARM=1 GUEST=1
for a in "$@"; do
  case "$a" in
  --accept-adobe-eula) ACCEPT_EULA=1 ;;
  --skip-debloat) DEBLOAT=0 ;;
  --no-warm) WARM=0 ;;
  --linux-only) GUEST=0 ;;
  -h | --help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $a (see --help)" >&2; exit 2 ;;
  esac
done

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BIN="$HOME/.local/bin"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/acrobat-win"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
HYPR="$HOME/.config/hypr"
SHARE="$HOME/Windows"                        # \\host.lan\Data inside Windows
MARKS="$SHARE/.acrobat-win-setup"            # guest scripts write logs + *.done here
FREEZE=/usr/local/bin/omarchy-windows-freeze
SUDOERS=/etc/sudoers.d/acrobat-win-freeze

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 1. checks
say "Checking requirements"
[[ $EUID -ne 0 ]] || die "run as your normal user, not root (sudo is used where needed)"
missing=()
for c in xfreerdp3 inotifywait docker pkexec sudo visudo sha1sum notify-send; do
  command -v "$c" >/dev/null || missing+=("$c")
done
if ((${#missing[@]})); then
  echo "missing commands: ${missing[*]}"
  echo "on Omarchy/Arch:  omarchy pkg add freerdp inotify-tools libnotify"
  die "install the missing packages and re-run"
fi
[[ -x /usr/bin/omarchy-windows-vm ]] || die "omarchy-windows-vm not found: this needs Omarchy's Windows VM"
[[ -f $HOME/.config/windows/credentials ]] || die "Windows VM not installed yet: run 'omarchy windows vm install' first"
[[ -d $SHARE ]] || die "shared folder $SHARE missing: was the VM installed with Omarchy's tool?"
echo "ok"

# ---------------------------------------------------------------- 2. Linux files
say "Installing the launcher, maintenance runner and desktop entry"
install -Dm755 "$REPO/bin/acrobat-win" "$BIN/acrobat-win"
install -Dm755 "$REPO/lib/winrun" "$DATA/winrun"
mkdir -p "$DATA/guest"
install -m644 "$REPO"/guest/*.ps1 "$REPO/guest/selftest.pdf" "$DATA/guest/"
install -Dm644 "$REPO/desktop/acrobat-reader-win.desktop" "$APPS/acrobat-reader-win.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" 2>/dev/null || true
case ":$PATH:" in *":$BIN:"*) ;; *) echo "note: $BIN is not on your PATH" ;; esac

say "Installing the freeze helper (needs sudo once)"
# A tiny root-owned script that can only pause/unpause/inspect the one VM container,
# plus a sudoers rule letting you run exactly that without a password. Much narrower
# than joining the docker group (which is equivalent to root).
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
printf '%s ALL=(root) NOPASSWD: %s pause, %s unpause, %s status\n' \
  "$USER" "$FREEZE" "$FREEZE" "$FREEZE" >"$tmp"
visudo -cqf "$tmp" || die "generated sudoers rule failed visudo check"
sudo install -o root -g root -m755 "$REPO/system/omarchy-windows-freeze" "$FREEZE"
sudo install -o root -g root -m440 "$tmp" "$SUDOERS"
sudo visudo -cq || { sudo rm -f "$SUDOERS"; die "sudoers check failed; rule removed"; }
sudo -n "$FREEZE" status >/dev/null || die "passwordless freeze helper does not work"
echo "ok: $FREEZE + $SUDOERS"

say "Hyprland rules"
if [[ -f $HYPR/hyprland.lua ]]; then
  install -m644 "$REPO/hypr/acrobat-win.lua" "$HYPR/acrobat-win.lua"
  ((WARM)) || sed -i '/acrobat-win --warm/d' "$HYPR/acrobat-win.lua"
  if ! grep -q 'require("hypr.acrobat-win")' "$HYPR/hyprland.lua"; then
    cp "$HYPR/hyprland.lua" "$HYPR/hyprland.lua.bak.$(date +%s)"
    printf '\n-- acrobat-win (Adobe Acrobat Reader in the Windows VM)\nrequire("hypr.acrobat-win")\n' >>"$HYPR/hyprland.lua"
  fi
  if command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null
    errs=$(hyprctl configerrors 2>/dev/null || true)
    [[ -z $errs || $errs == *"no errors"* ]] || echo "warning: Hyprland reports config errors:"$'\n'"$errs"
  fi
  echo "ok: $HYPR/acrobat-win.lua"
else
  echo "no Lua Hyprland config found; add the two rules from hypr/acrobat-win.lua by hand"
fi

if ((!GUEST)); then
  say "Done (Linux side only). Run ./install.sh again without --linux-only to set up Windows."
  exit 0
fi

# ---------------------------------------------------------------- 3. Windows side
state() { sudo -n "$FREEZE" status 2>/dev/null | tr -d '\n'; }
pgrep -u "$USER" -x xfreerdp3 >/dev/null &&
  die "an RDP window (Acrobat or the Windows VM) is open; close it and re-run"

say "Starting the Windows VM"
case "$(state)" in
running) ;;
paused) sudo -n "$FREEZE" unpause ;;
*) pkexec /usr/bin/omarchy-windows-vm __priv up_wait || die "VM failed to start (omarchy windows vm status)" ;;
esac
for _ in $(seq 120); do
  timeout 1 bash -c '</dev/tcp/127.0.0.1/3389' 2>/dev/null && break
  sleep 1
done
echo "VM: $(state), RDP port open"

mkdir -p "$MARKS"
cp -f "$REPO/guest/shell.ps1" "$SHARE/shell.ps1"
cp -f "$REPO/guest/selftest.pdf" "$MARKS/selftest.pdf"

# run_step <script> <max_seconds> [args...]
# Runs a guest script through RemoteApp (lib/winrun) and waits for the
# <script>.done marker it writes. The RemoteApp window lands on a hidden
# Hyprland workspace (special:winrun). Retries the connection while Windows
# is still booting and not yet accepting sign-ins.
run_step() {
  local script=$1 max=$2 base mark pid t0 try
  shift 2
  base=${script%.ps1}
  mark="$MARKS/$base.done"
  rm -f "$mark"
  for try in 1 2 3 4 5 6; do
    t0=$SECONDS
    setsid "$DATA/winrun" "$DATA/guest/$script" "$max" "$@" >"$MARKS/$base.rdp.log" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null && [[ ! -f $mark ]]; do sleep 2; done
    [[ -f $mark ]] && sleep 3 # let the script log off / close cleanly
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    [[ -f $mark ]] && break
    ((SECONDS - t0 < 30)) || break # it ran for a while: a real failure, not "not booted yet"
    echo "  (Windows not accepting sign-ins yet, retry $try/6 in 15 s)"
    sleep 15
  done
  [[ -f $mark ]] || die "$script did not finish; see $MARKS/$base.log and $base.rdp.log"
  grep -q '^ok' "$mark" || die "$script failed: $(cat "$mark"); see $MARKS/$base.log"
  echo "ok: $script"
}

say "1/5 Installing Adobe Acrobat Reader (downloads ~600 MB; several minutes)"
run_step 01-install-acrobat.ps1 1800

if ((DEBLOAT)); then
  say "2/5 Stripping Windows down (Store apps, services, telemetry, updates; 10-30 min)"
  run_step 02-debloat.ps1 3600
else
  say "2/5 Skipping debloat (--skip-debloat)"
fi

say "3/5 Acrobat preferences (no upsell/tour; WebView2 software rendering)"
if ((ACCEPT_EULA)); then run_step 03-acrobat-prefs.ps1 300 -AcceptEula; else run_step 03-acrobat-prefs.ps1 300; fi

say "Self-check (dependencies, certificate signing, opening a PDF)"
run_step check-acrobat.ps1 300 -Tag install
tr -d '\r' <"$MARKS/check-install.txt" | sed 's/^/  /'

say "4/5 Turning off Windows auto sign-in"
run_step 04-no-autologon.ps1 120

say "5/5 Installing the Acrobat-only Windows shell"
run_step 05-install-shell.ps1 120
rm -f "$SHARE/shell.ps1" "$SHARE"/0[1-5]-*.ps1 "$SHARE/check-acrobat.ps1"

sleep 5
sudo -n "$FREEZE" pause && echo "VM frozen until first use"

say "Done"
cat <<EOF
Open a PDF:       acrobat-win file.pdf     (or "Adobe Acrobat Reader" in the app launcher,
                                            or "Open with" in your file manager)
Make it default:  xdg-mime default acrobat-reader-win.desktop application/pdf
Logs:             $MARKS/  and  ~/.local/state/acrobat-win/
EOF
((ACCEPT_EULA)) || echo "First start: Acrobat shows Adobe's license agreement once; click Accept."
