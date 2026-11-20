-- acrobat-win: Hyprland pieces.
-- install.sh copies this file to ~/.config/hypr/acrobat-win.lua and adds
-- require("hypr.acrobat-win") to ~/.config/hypr/hyprland.lua.

-- Maintenance scripts run inside the Windows VM (lib/winrun) appear as RemoteApp
-- windows; send them to a hidden special workspace so they never cover your work.
o.window({ class = "^winrun$" }, { workspace = "special:winrun silent" })

-- Boot the Windows VM at login, wait until it accepts logins, then freeze it, so the
-- first Acrobat launch of the day is as fast as the rest. Costs one password prompt
-- per login. Delete this line (or install with --no-warm) to start the VM on demand.
o.launch_on_start("acrobat-win --warm")
