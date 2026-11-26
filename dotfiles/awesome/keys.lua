-- Key and mouse bindings. Sets the global keys; returns the per-client keys
-- and buttons for rules.lua. Uses the globals terminal and modkey (main.lua).

local gears = require("gears")
local awful = require("awful")
local home = os.getenv("HOME")

------------------------------------------------------------------------------------------------------------
------------------------------------------------ KEY BINDINGS ----------------------------------------------
------------------------------------------------------------------------------------------------------------

globalkeys =
	gears.table.join(
	---------------------------------------------- TILING --------------------------------------------------

	-- focus windows
	awful.key(
		{modkey},
		"j",
		function()
			awful.client.focus.byidx(1)
		end,
		{description = "focus next by index", group = "client"}
	),
	awful.key(
		{modkey},
		"k",
		function()
			awful.client.focus.byidx(-1)
		end,
		{description = "focus previous by index", group = "client"}
	),
	-- move client
	awful.key(
		{modkey, "Shift"},
		"j",
		function()
			awful.client.swap.byidx(1)
		end,
		{description = "swap with next client by index", group = "client"}
	),
	awful.key(
		{modkey, "Shift"},
		"k",
		function()
			awful.client.swap.byidx(-1)
		end,
		{description = "swap with previous client by index", group = "client"}
	),
	-- change master size
	awful.key(
		{modkey},
		"l",
		function()
			awful.tag.incmwfact(0.05)
		end,
		{description = "increase master width factor", group = "layout"}
	),
	awful.key(
		{modkey},
		"h",
		function()
			awful.tag.incmwfact(-0.05)
		end,
		{description = "decrease master width factor", group = "layout"}
	),
	awful.key(
		{modkey, "Control"},
		"r",
		function()
			awesome.restart()
		end,
		{description = "restart awesomeWM", group = "awesome"}
	),
	awful.key(
		{modkey, "Shift"},
		"BackSpace",
		function()
			awesome.quit()
		end,
		{description = "quit awesomeWM", group = "awesome"}
	),
	-- cycle tiling layout
	awful.key(
		{modkey},
		"m",
		function()
			awful.layout.inc(1)
		end,
		{description = "select next", group = "layout"}
	),
	-- lock computer
	awful.key(
		{modkey},
		"x",
		function()
			awful.spawn(home .. "/GNOMS/scripts/blurlock.sh")
		end,
		{description = "lock computer", group = "layout"}
	),
	--------------------------------------------- FUNCTION KEYS --------------------------------------------

	-- Volume keys
	awful.key(
		{},
		"XF86AudioRaiseVolume",
		function()
			awful.spawn(home .. "/GNOMS/scripts/volume.sh up")
		end,
		{description = "volume up", group = "media"}
	),
	awful.key(
		{},
		"XF86AudioLowerVolume",
		function()
			awful.spawn(home .. "/GNOMS/scripts/volume.sh down")
		end,
		{description = "volume down", group = "media"}
	),
	-- Mute sound
	awful.key(
		{},
		"XF86AudioMute",
		function()
			awful.spawn(home .. "/GNOMS/scripts/volume.sh mute")
		end,
		{description = "toggle mute", group = "media"}
	),
	-- Mute mic
	awful.key(
		{},
		"XF86AudioMicMute",
		function()
			awful.spawn.with_shell(
				[[wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED && notify-send -i microphone-sensitivity-muted "Mic muted" || notify-send -i microphone-sensitivity-high "Mic unmuted"]]
			)
		end,
		{description = "toggle mic mute", group = "media"}
	),
	-- Brightness keys
	awful.key(
		{},
		"XF86MonBrightnessUp",
		function()
			awful.spawn(home .. "/GNOMS/scripts/brightstep.sh up")
		end,
		{description = "brightness up", group = "system"}
	),
	awful.key(
		{},
		"XF86MonBrightnessDown",
		function()
			awful.spawn(home .. "/GNOMS/scripts/brightstep.sh down")
		end,
		{description = "brightness down", group = "system"}
	),
	-- Screenshots
	awful.key(
		{},
		"Print",
		function()
			awful.spawn("flameshot screen -p " .. home .. "/media/img/screenshots/")
		end,
		{description = "screenshot: screen", group = "screenshot"}
	),
	awful.key(
		{"Shift"},
		"Print",
		function()
			awful.spawn("flameshot gui -p " .. home .. "/media/img/screenshots/")
		end,
		{description = "screenshot: gui", group = "screenshot"}
	),
	awful.key(
		{modkey},
		"Print",
		function()
			awful.spawn("flameshot full -p " .. home .. "/media/img/screenshots/")
		end,
		{description = "screenshot: full", group = "screenshot"}
	),
	--------------------------------------------- PROGRAMS ------------------------------------------------

	awful.key(
		{modkey},
		"Return",
		function()
			awful.spawn(terminal)
		end,
		{description = "open a terminal", group = "launcher"}
	),
	awful.key(
		{modkey},
		"w",
		function()
			awful.spawn("firefox")
		end,
		{description = "open web browser", group = "launcher"}
	),
	awful.key(
		{modkey},
		"s",
		function()
			awful.spawn("spotify")
		end,
		{description = "open Spotify", group = "launcher"}
	),
	awful.key(
		{modkey},
		"c",
		function()
			awful.spawn("qalculate-gtk")
		end,
		{description = "open calculator", group = "launcher"}
	),
	awful.key(
		{modkey},
		"e",
		function()
			awful.spawn("thunar")
		end,
		{description = "open file explorer", group = "launcher"}
	),
	--------------------------------------------- WORKFLOW ------------------------------------------------

	-- Run program
	awful.key(
		{modkey},
		"r",
		function()
			awful.spawn("rofi -show run")
		end,
		{description = "open launcher", group = "launcher"}
	),
	-- restore program
	awful.key(
		{modkey},
		"z",
		function()
			local s = awful.screen.focused()
			local scrap_tag = awful.tag.find_by_name(s, "scrap")
			if not scrap_tag then
				return
			end

			for _, c in ipairs(scrap_tag:clients()) do
				c:move_to_tag(s.selected_tag)
				client.focus = c
				c:raise()
				return
			end
		end,
		{description = "restore from scrap pad", group = "client"}
	)
)

clientkeys =
	gears.table.join(
	-- fullscreen
	awful.key(
		{modkey},
		"f",
		function(c)
			c.fullscreen = not c.fullscreen
			c:raise()
		end,
		{description = "toggle fullscreen", group = "client"}
	),
	-- close program
	awful.key(
		{modkey},
		"q",
		function()
			local c = client.focus
			if not c then
				return
			end

			local class = c.class or ""
			local name = c.name or ""

			-- Programs eligible for scrap
			local scrap_classes = {
				-- Editors
				["code"] = true,
				["libreoffice"] = true,
				["gedit"] = true,
				["mousepad"] = true,
				["notepadqq"] = true,
				["kate"] = true,
				-- Browsers
				["firefox"] = true,
				["brave-browser"] = true,
				["chromium"] = true,
				["google-chrome"] = true,
				-- CAD / Design
				["org.kde.kicad"] = true,
				["Fusion360"] = true
			}

			-- Terminal classes (scrap only if generic name)
			local terminal_classes = {
				["WezTerm"] = true,
				["Alacritty"] = true,
				["kitty"] = true,
				["Xfce4-terminal"] = true,
				["org.gnome.Terminal"] = true,
				["konsole"] = true,
				["Terminal"] = true
			}

			local function is_generic_terminal()
				return terminal_classes[class] and
					(name == "" or name:lower():match("terminal") or name:lower():match("^bash$") or name:lower():match("^zsh$") or
						name:lower():match("^fish$") or
						name:lower():match("^sh$"))
			end

			local should_scrap = scrap_classes[class] or is_generic_terminal()

			if should_scrap then
				local scrap_tag = awful.tag.find_by_name(c.screen, "scrap")
				if scrap_tag then
					for _, cl in ipairs(scrap_tag:clients()) do
						cl:kill()
					end
					c:move_to_tag(scrap_tag)
					return
				end
			end

			-- Fallback: close normally
			c:kill()
		end,
		{description = "send to scrap or close", group = "client"}
	),
	-- forcefully close program
	awful.key(
		{modkey, "Shift"},
		"q",
		function(c)
			c:kill()
		end,
		{description = "close", group = "client"}
	),
	-- togglefloating
	awful.key({modkey}, "space", awful.client.floating.toggle, {description = "toggle floating", group = "client"})
)

--------------------------------------------- MOVE TO TAG ------------------------------------------------

for i = 1, 9 do
	globalkeys =
		gears.table.join(
		globalkeys,
		-- View tag only.
		awful.key(
			{modkey},
			"#" .. i + 9,
			function()
				local screen = awful.screen.focused()
				local tag = screen.tags[i]
				if tag then
					tag:view_only()
				end
			end,
			{description = "view tag #" .. i, group = "tag"}
		),
		-- Move client to tag.
		awful.key(
			{modkey, "Shift"},
			"#" .. i + 9,
			function()
				if client.focus then
					local tag = client.focus.screen.tags[i]
					if tag then
						client.focus:move_to_tag(tag)
						tag:view_only()
					end
				end
			end,
			{description = "move focused client to tag #" .. i, group = "tag"}
		)
	)
end

--------------------------------------------- MOVE TO MONITOR ------------------------------------------------

for i = 1, 9 do
	globalkeys =
		gears.table.join(
		globalkeys,
		awful.key(
			{modkey, "Control"},
			"#" .. (i + 9),
			function()
				local c = client.focus
				local target_screen = screen[i]
				if c and target_screen then
					c:move_to_screen(target_screen)
				end
			end,
			{description = "move client to screen #" .. i, group = "screen"}
		)
	)
end

globalkeys =
	gears.table.join(
	globalkeys,
	awful.key(
		{modkey, "Shift"},
		"f",
		function()
			if _G.toggle_fan then
				_G.toggle_fan()
			end
		end,
		{description = "toggle fan silent mode", group = "system"}
	)
)

root.keys(globalkeys)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- MOUSE BINDINGS -------------------------------------------
------------------------------------------------------------------------------------------------------------

clientbuttons =
	gears.table.join(
	awful.button(
		{},
		1,
		function(c)
			c:emit_signal("request::activate", "mouse_click", {raise = true})
		end
	),
	awful.button(
		{modkey},
		1,
		function(c)
			c:emit_signal("request::activate", "mouse_click", {raise = true})
			awful.mouse.client.move(c)
		end
	),
	awful.button(
		{modkey},
		3,
		function(c)
			c:emit_signal("request::activate", "mouse_click", {raise = true})
			awful.mouse.client.resize(c)
		end
	)
)

return {keys = clientkeys, buttons = clientbuttons}
