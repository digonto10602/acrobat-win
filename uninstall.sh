#!/bin/bash
# uninstall.sh — remove acrobat-win from Linux and give the Windows user its normal
# desktop back. Leaves the Windows VM itself, Acrobat inside it, and the debloat
# changes alone (remove the whole VM with: omarchy windows vm remove).
#
#   ./uninstall.sh [--linux-only]
set -euo pipefail
GUEST=1
[[ ${1:-} == --linux-only ]] && GUEST=0
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/acrobat-win"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
HYPR="$HOME/.config/hypr"
FREEZE=/usr/local/bin/omarchy-windows-freeze
MARKS="$HOME/Windows/.acrobat-win-setup"

if ((GUEST)) && [[ -x $DATA/winrun ]]; then
  echo "==> Restoring the normal Windows shell"
  pgrep -u "$USER" -x xfreerdp3 >/dev/null && { echo "close the Acrobat/Windows window first" >&2; exit 1; }
  case "$(sudo -n "$FREEZE" status 2>/dev/null)" in
  paused) sudo -n "$FREEZE" unpause ;;
  running) ;;
  *) pkexec /usr/bin/omarchy-windows-vm __priv up_wait ;;
  esac
  mkdir -p "$MARKS"; rm -f "$MARKS/uninstall-shell.done"
  "$DATA/winrun" "$DATA/guest/uninstall-shell.ps1" 120 || true
  [[ -f $MARKS/uninstall-shell.done ]] && echo "ok" || echo "warning: guest step did not confirm; Windows may still start Acrobat-only sessions"
fi

echo "==> Removing Linux files"
sudo -n "$FREEZE" unpause 2>/dev/null || true # never leave the VM frozen without the helper
rm -f "$HOME/.local/bin/acrobat-win" "$APPS/acrobat-reader-win.desktop" "$HYPR/acrobat-win.lua"
rm -rf "$DATA" "$MARKS" "$HOME/Windows/acrobat" "$HOME/Windows/open-request.txt"
[[ -f $HYPR/hyprland.lua ]] && sed -i '/^-- acrobat-win (Adobe Acrobat Reader in the Windows VM)$/d; /^require("hypr.acrobat-win")$/d' "$HYPR/hyprland.lua"
sudo rm -f /etc/sudoers.d/acrobat-win-freeze "$FREEZE"
echo "Kept: ~/.local/state/acrobat-win (sync log + backups of overwritten PDFs). Delete it by hand if unwanted."
