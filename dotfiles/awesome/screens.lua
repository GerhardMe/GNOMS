-- Screens: boot-only setup (monitors, eGPU detection), wallpaper, bar color,
-- layouts, and per-screen tags and bar. Loaded by main.lua after beautiful.init.

local gears = require("gears")
local awful = require("awful")
local wibox = require("wibox")
local beautiful = require("beautiful")
local statusbar = require("statusbar")

------------------------------------------------------------------------------------------------------------
------------------------------------------------- LOAD FROM BOOT -------------------------------------------
------------------------------------------------------------------------------------------------------------

-- ---------- eGPU + monitor helpers (boot-only check for eGPU) ----------
local HAS_EGPU = false

-- Count active screens
local function screen_count()
	local n = 0
	for _ in screen do
		n = n + 1
	end
	return n
end

local function refresh_monitor_prefixes()
	local n = screen_count()
	for s in screen do
		if s.monitor_prefix then
			if n > 1 then
				s.monitor_prefix.markup =
					string.format(
					"<span font='%s' foreground='%s' size='11pt' rise='1000' >(%s)</span>",
					beautiful.font,
					"#8700ff",
					s.index
				)
				s.monitor_prefix.visible = true
			else
				s.monitor_prefix.markup = ""
				s.monitor_prefix.visible = false
			end
		end
	end
end

-- Keep prefixes correct as screens are added/removed/resize
screen.connect_signal(
	"added",
	function(_)
		refresh_monitor_prefixes()
	end
)
screen.connect_signal(
	"removed",
	function(_)
		refresh_monitor_prefixes()
	end
)
screen.connect_signal(
	"property::geometry",
	function(_)
		refresh_monitor_prefixes()
	end
)

-- Boot-only setup (not on reload)
local awesome_started_flag = "/tmp/awesome-has-started"
local function is_first_boot()
	local f = io.open(awesome_started_flag, "r")
	if f then
		f:close()
		return false
	end
	return true
end

if is_first_boot() then
	-- Mark that we've started
	local f = io.open(awesome_started_flag, "w")
	if f then
		f:write(tostring(os.time()))
		f:close()
	end

	-- Detect and configure monitors
	awful.spawn("autorandr --change")

	-- One-shot eGPU detection
	awful.spawn.easy_async_with_shell(
		[[sh -c 'nvidia-smi -L >/dev/null 2>&1 && echo YES || echo NO']],
		function(out)
			HAS_EGPU = out:match("YES") ~= nil
			awesome.emit_signal("env::egpu_ready", HAS_EGPU)
		end
	)
end

------------------------------------------------------------------------------------------------------------
------------------------------------------------- THEMING --------------------------------------------------
------------------------------------------------------------------------------------------------------------
local function set_wallpaper(s)
	if beautiful.wallpaper then
		local wallpaper = beautiful.wallpaper
		if type(wallpaper) == "function" then
			wallpaper = wallpaper(s)
		end
		gears.wallpaper.maximized(wallpaper, s, true)
	end
end
screen.connect_signal("property::geometry", set_wallpaper)

-- listen for external requests to change bar bg
awesome.connect_signal(
	"mode::bar_bg",
	function(color)
		if not color or type(color) ~= "string" then
			return
		end
		-- update theme value so newly created widgets use it too
		beautiful.bg_normal = color
		-- update existing bars
		for s in screen do
			if s.mywibox then
				s.mywibox.bg = color
			end
		end
	end
)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- TILING ---------------------------------------------------
------------------------------------------------------------------------------------------------------------

awful.layout.layouts = {
	awful.layout.suit.tile,
	awful.layout.suit.tile.bottom,
	awful.layout.suit.tile.left,
	awful.layout.suit.tile.top,
	awful.layout.suit.floating
}

awful.screen.connect_for_each_screen(
	function(s)
		set_wallpaper(s)
		awful.tag({"1", "2", "3", "4", "5", "6", "7", "8", "9"}, s, awful.layout.layouts[1])

		awful.tag.add(
			"scrap",
			{
				screen = s,
				layout = awful.layout.suit.floating,
				selected = false
			}
		)

		awful.tag.add(
			"preload",
			{
				screen = s,
				layout = awful.layout.suit.floating,
				selected = false
			}
		)

		for _, t in ipairs(s.tags) do
			t.gap = beautiful.useless_gap
			t.gap_single_client = false -- Like i3's smartgaps
		end

		----------------------------------------------------------------------------------------------------
		---------------------------------------------- WIDGETS ---------------------------------------------
		----------------------------------------------------------------------------------------------------

		-- TAG-list widget
		s.mytaglist =
			awful.widget.taglist(
			{
				screen = s,
				buttons = gears.table.join(
					awful.button(
						{},
						1,
						function(t)
							t:view_only()
						end
					)
				),
				filter = function(t)
					return t.name:match("^%d+$") and (#t:clients() > 0 or t.selected)
				end
			}
		)

		-- Tiling-layout widget
		s.mylayoutbox = awful.widget.layoutbox(s)
		s.mylayoutbox:buttons(
			gears.table.join(
				awful.button(
					{},
					1,
					function()
						awful.layout.inc(1)
					end
				)
			)
		)

		-- --- Small label before the taglist: "N:" if multiple monitors
		s.monitor_prefix =
			wibox.widget(
			{
				widget = wibox.widget.textbox,
				align = "left",
				valign = "center",
				text = "" -- filled by refresh_monitor_prefixes()
			}
		)

		-- --- Small label after the taglist: " eGPU" if detected at boot
		s.egpu_label =
			wibox.widget(
			{
				widget = wibox.widget.textbox,
				align = "left",
				valign = "center",
				markup = string.format(
					"<span font='%s' foreground='%s' size='11pt' rise='1000' > eGPU</span>",
					beautiful.font,
					"#00ff00"
				),
				visible = HAS_EGPU
			}
		)

		-- set initial monitor prefix state
		refresh_monitor_prefixes()

		-- react once eGPU detection finishes
		awesome.connect_signal(
			"env::egpu_ready",
			function(has)
				if s.egpu_label then
					s.egpu_label.visible = has
				end
			end
		)

		-- Statusbar
		s.mywibox = awful.wibar({position = "top", screen = s, height = 22})

		s.mywibox:setup(
			{
				layout = wibox.layout.align.horizontal,
				{
					--- Left widgets
					layout = wibox.layout.fixed.horizontal,
					s.monitor_prefix, -- monitor num
					s.mytaglist, -- your numeric tags
					s.egpu_label -- " eGPU"
				},
				nil, -- middle widgets
				{
					--- Right widgets
					layout = wibox.layout.fixed.horizontal,
					statusbar.widget,
					wibox.widget.systray(),
					s.mylayoutbox
				}
			}
		)
	end
)
