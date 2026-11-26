pcall(require, "luarocks.loader")

require("awful.autofocus")
require("awful.hotkeys_popup.keys")

local gears = require("gears")
local awful = require("awful")
local beautiful = require("beautiful")
local spawn = require("awful.spawn")
-- statusbar loads before beautiful.init (same order as before the split)
local statusbar = require("statusbar")
local home = os.getenv("HOME")

------------------------------------------------------------------------------------------------------------
------------------------------------------------- ERROR HANDLING -------------------------------------------
------------------------------------------------------------------------------------------------------------

-- Handle startup errors
if awesome.startup_errors then
	spawn.easy_async_with_shell(
		string.format('dunstify -u critical "<span color=\'red\'>Startup Error</span>" %q', awesome.startup_errors),
		function(_)
		end
	)
end

-- Handle runtime errors
do
	local in_error = false
	awesome.connect_signal(
		"debug::error",
		function(err)
			if in_error then
				return
			end
			in_error = true

			spawn.easy_async_with_shell(
				string.format('dunstify -u critical "<span color=\'red\'>Runtime Error</span>" %q', tostring(err)),
				function(_)
					in_error = false
				end
			)
		end
	)
end

------------------------------------------------------------------------------------------------------------
------------------------------------------------- SETTINGS -------------------------------------------------
------------------------------------------------------------------------------------------------------------

terminal = "wezterm"
editor = os.getenv("EDITOR") or "vim"
editor_cmd = terminal .. " -e " .. editor
modkey = "Mod4"

------------------------------------------------------------------------------------------------------------
------------------------------------------------- THEMING --------------------------------------------------
------------------------------------------------------------------------------------------------------------

beautiful.init(home .. "/.config/awesome/theme.lua")

------------------------------------------------------------------------------------------------------------
------------------------------------------------- MODULES --------------------------------------------------
------------------------------------------------------------------------------------------------------------

-- Order matters: screens needs the theme, rules needs the client keys from keys.
require("screens") -- boot setup, wallpaper, layouts, tags, bar
require("keys") -- key and mouse bindings
require("rules") -- client rules
require("clients") -- client decoration and focus signals
require("startup") -- startup programs, tag restore, Firefox preload

------------------------------------------------------------------------------------------------------------
------------------------------------------------- PRIVATE --------------------------------------------------
------------------------------------------------------------------------------------------------------------

-- Machine-local config that is not in the repo (private/ is gitignored).
-- Loaded last, so it can use the hooks above (e.g. statusbar.clock_day).
local private_config = home .. "/GNOMS/private/awesome.lua"
if gears.filesystem.file_readable(private_config) then
	local ok, err = pcall(dofile, private_config)
	if not ok then
		local naughty = require("naughty")
		naughty.notify({preset = naughty.config.presets.critical, title = "private/awesome.lua failed", text = tostring(err)})
	end
end