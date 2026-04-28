local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")

local statusbar = {}

------------------------------------------------------------------------------------------------------------
------------------------------------------------- HELPERS --------------------------------------------------
------------------------------------------------------------------------------------------------------------

local function wez(cmd, opts)
	opts = opts or {}
	local class = opts.class and ("--class " .. opts.class) or ""
	-- NOTE: WezTerm has no reliable CLI flags for geometry; use Awesome client rules on class if you need sizing.
	return string.format("wezterm start --always-new-process %s -- bash -lc %q", class, cmd)
end

------------------------------------------------------------------------------------------------------------
------------------------------------------------- THEMING --------------------------------------------------
------------------------------------------------------------------------------------------------------------

local color_good = "#00ff00"
local color_degraded = "#ff7300"
local color_bad = "#ff0000"

-- Helper to make a widget with icon and text
local function icon_text(icon, widget)
	local iconbox =
		wibox.widget(
		{
			markup = string.format("<span font='%s'>%s</span>", beautiful.font, icon),
			widget = wibox.widget.textbox
		}
	)
	return wibox.widget(
		{
			iconbox,
			widget,
			layout = wibox.layout.fixed.horizontal,
			spacing = 4
		}
	)
end

------------------------------------------------------------------------------------------------------------
------------------------------------------------- NETWORK ---------------------------------------------------
------------------------------------------------------------------------------------------------------------

local network = wibox.widget.textbox()

local function update_net_combined()
	local result = {
		eth_text = "",
		wifi_text = "",
		mobile_text = "",
		eth_done = false,
		wifi_done = false,
		mobile_done = false
	}

	local function try_display()
		if result.eth_done and result.wifi_done and result.mobile_done then
			local parts = {}
			if result.eth_text ~= "" then
				table.insert(parts, result.eth_text)
			end
			if result.wifi_text ~= "" then
				table.insert(parts, result.wifi_text)
			end
			if result.mobile_text ~= "" then
				table.insert(parts, result.mobile_text)
			end

			if #parts == 0 then
				network.markup = string.format("<span foreground='%s' font='%s'>󰖪 </span>", color_bad, beautiful.font)
			else
				local final = table.concat(parts, " ")
				network.markup = string.format("<span font='%s'>%s</span>", beautiful.font, final)
			end
		end
	end

	-- Ethernet
	local candidate_dev = nil

	-- Step 1: Get candidate Ethernet interface name
	awful.spawn.easy_async_with_shell(
		[[ip -o link | awk -F': ' '/^[0-9]+: en/ {print $2}' | head -n1]],
		function(dev)
			dev = dev:gsub("%s+", "")
			candidate_dev = dev

			if dev == "" then
				result.eth_text = ""
				result.eth_done = true
				try_display()
				return
			end

			-- Step 2: Check if interface is UP
			awful.spawn.easy_async_with_shell(
				"ip link show " .. dev,
				function(output)
					local has_state_up = output:match("state UP")
					local has_lower_up = output:match("LOWER_UP")

					if has_state_up and has_lower_up then
						result.eth_text = string.format("<span foreground='%s'>🔌 Ethernet</span>", color_good)
					else
						result.eth_text = ""
					end

					result.eth_done = true
					try_display()
				end
			)
		end
	)

	-- WiFi
	awful.spawn.easy_async_with_shell(
		[[nmcli -t -f IN-USE,SSID,SIGNAL dev wifi | awk -F: '$1=="*"{print $3, $2}']],
		function(stdout)
			local signal, ssid = stdout:gsub("%s+$", ""):match("(%d+)%s+(.*)")
			if signal and ssid and ssid ~= "" then
				local signal_num = tonumber(signal)
				local color = beautiful.fg_normal
				if signal_num < 20 then
					color = color_bad
				elseif signal_num < 50 then
					color = color_degraded
				else
					color = color_good
				end
				result.wifi_text = string.format("<span foreground='%s'>󰖩 %s%% %s</span>", color, signal, ssid)
			end
			result.wifi_done = true
			try_display()
		end
	)

	-- LTE — Step 1: Get modem path
	awful.spawn.easy_async_with_shell(
		[[mmcli -L | grep -o '/Modem/[0-9]\+' | grep -o '[0-9]\+' | head -n1]],
		function(modem_path)
			modem_path = modem_path:gsub("%s+", "")

			if modem_path == "" then
				result.mobile_done = true
				try_display()
				return
			end

			-- LTE — Step 2: Query modem
			awful.spawn.easy_async_with_shell(
				"mmcli -m " .. modem_path,
				function(stdout)
					stdout = stdout:gsub("\27%[[%d;]*m", "")

					local connected = stdout:match("Status.-\n.-state:%s+(%w+)")
					local signal = stdout:match("signal quality:%s+(%d+)")
					local tech = stdout:match("access tech:%s+([^\n]+)")

					if connected == "connected" and signal and tech then
						tech = tech:lower():gsub("^%s+", ""):gsub("%s+$", "")
						if tech == "lte" then
							tech = "4G"
						elseif tech:match("hspa") or tech == "umts" then
							tech = "3G"
						elseif tech == "edge" or tech == "gprs" then
							tech = "2G"
						elseif tech:match("5g") then
							tech = "5G"
						else
							tech = "E"
						end

						local signal_num = tonumber(signal)
						local color = beautiful.fg_normal
						if signal_num < 10 then
							color = color_bad
						elseif signal_num < 30 then
							color = color_degraded
						else
							color = color_good
						end

						result.mobile_text = string.format("<span foreground='%s'>%s</span>", color, tech)
					else
						result.mobile_text = "" -- not connected, don't display
					end

					result.mobile_done = true
					try_display()
				end
			)
		end
	)
end

gears.timer({timeout = 5, autostart = true, callback = update_net_combined})
gears.timer.delayed_call(update_net_combined)

network:buttons(
	gears.table.join(
		awful.button(
			{},
			1,
			function()
				awful.spawn(wez("sleep 0.2 && env NEWT_COLORS='root=,default' nmtui", {class = "popup"}), false)
				awful.spawn.with_shell("nm-applet & sleep 30 && pkill nm-applet")
			end
		),
		awful.button(
			{},
			3,
			function()
				awful.spawn(wez("sudo nethogs; exec bash"))
				awful.spawn(wez("speedtest; exec bash"))
			end
		)
	)
)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- BLUETOOTH ------------------------------------------------
------------------------------------------------------------------------------------------------------------

local bluetooth = wibox.widget.textbox()

local function update_bluetooth()
	awful.spawn.easy_async_with_shell(
		[[hciconfig -a; hcitool dev | sed '1d' | wc -l]],
		function(stdout)
			local powered = stdout:match("UP")
			local connected = tonumber(stdout:match("(%d+)%s*$")) or 0

			local icon_char = powered and "󰂯" or "󰂲"
			local color = not powered and color_degraded or (connected > 0 and color_good or beautiful.fg_normal)

			local icon_markup =
				string.format("<span font='%s' foreground='%s' size='13pt' rise='3000'>%s</span>", beautiful.font, color, icon_char)

			local number_markup = ""
			if powered and connected > 0 then
				number_markup = string.format("<span font='%s' foreground='%s'> %d</span>", beautiful.font, color, connected)
			end

			bluetooth.markup = icon_markup .. number_markup
		end
	)
end

gears.timer(
	{
		timeout = 3,
		autostart = true,
		callback = update_bluetooth
	}
)
gears.timer.delayed_call(update_bluetooth)

bluetooth:buttons(
	gears.table.join(
		awful.button(
			{},
			1,
			function()
				awful.spawn(wez("bluetuith", {class = "popup"}), false)
			end
		)
	)
)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- SYS MONITOR ----------------------------------------------
------------------------------------------------------------------------------------------------------------

local sys = wibox.widget.textbox()
local cpu_prev = nil

local function update_sys()
	-- === CPU ===
	local f_cpu = io.open("/proc/stat", "r")
	local line = f_cpu:read("*l")
	f_cpu:close()
	local u, n, s, i = line:match("cpu%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
	u, n, s, i = tonumber(u), tonumber(n), tonumber(s), tonumber(i)

	local prev = cpu_prev or {u = u, n = n, s = s, i = i}
	local dt = (u + n + s + i) - (prev.u + prev.n + prev.s + prev.i)
	local da = (u + n + s) - (prev.u + prev.n + prev.s)
	cpu_prev = {u = u, n = n, s = s, i = i}

	local cpu_usage = (dt > 0) and math.floor(da / dt * 100 + 0.5) or 0
	local cpu_color = beautiful.fg_normal
	if cpu_usage >= 90 then
		cpu_color = color_bad
	elseif cpu_usage >= 70 then
		cpu_color = color_degraded
	end

	-- === Memory ===
	local f_mem = io.open("/proc/meminfo", "r")
	local mem_total_kb, mem_free_kb
	for line in f_mem:lines() do
		if line:match("MemTotal") then
			mem_total_kb = tonumber(line:match("%d+"))
		elseif line:match("MemAvailable") then
			mem_free_kb = tonumber(line:match("%d+"))
		end
		if mem_total_kb and mem_free_kb then
			break
		end
	end
	f_mem:close()

	local mem_used = math.floor((mem_total_kb - mem_free_kb) / 1024)
	local mem_total = math.floor(mem_total_kb / 1024)
	local mem_used_percent = (mem_total_kb - mem_free_kb) / mem_total_kb * 100

	local mem_color = beautiful.fg_normal
	if mem_used_percent >= 90 then
		mem_color = color_bad
	elseif mem_used_percent >= 70 then
		mem_color = color_degraded
	end

	-- === Update widget ===
	sys.markup =
		string.format(
		"<span font='%s'><span foreground='%s'>%02d%% </span>  <span foreground='%s'>%d/%d </span></span>",
		beautiful.font,
		cpu_color,
		cpu_usage,
		mem_color,
		mem_used,
		mem_total
	)
end

gears.timer({timeout = 3, autostart = true, callback = update_sys})
gears.timer.delayed_call(update_sys)
sys:buttons(
	gears.table.join(
		awful.button(
			{},
			1,
			function()
				awful.spawn(wez("htop"))
			end
		)
	)
)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- DISK -----------------------------------------------------
------------------------------------------------------------------------------------------------------------

local disk = wibox.widget.textbox()
local function parse_gb(avail_str)
	local num, unit = avail_str:match("(%d+%.?%d*)([GMK])")
	if not num or not unit then
		return 0
	end
	num = tonumber(num)
	if unit == "M" then
		return num / 1024
	elseif unit == "K" then
		return num / (1024 * 1024)
	elseif unit == "G" then
		return num
	else
		return 0
	end
end
local function update_disk()
	awful.spawn.easy_async_with_shell(
		"df -h / | awk 'NR==2 {print $4}'",
		function(stdout)
			local avail = stdout:gsub("%s+", "")
			local avail_gb = parse_gb(avail)
			local color = beautiful.fg_normal
			if avail_gb < 10 then
				color = color_bad
			elseif avail_gb < 100 then
				color = color_degraded
			end
			disk.markup = string.format("<span font='%s' foreground='%s'>%sB 󰉋 </span>", beautiful.font, color, avail)
		end
	)
end
gears.timer({timeout = 601, autostart = true, callback = update_disk})
gears.timer.delayed_call(update_disk)
disk:buttons(
	gears.table.join(
		awful.button(
			{},
			1,
			function()
				awful.spawn("baobab", false)
			end
		)
	)
)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- VOLUME ---------------------------------------------------
------------------------------------------------------------------------------------------------------------

local volume = wibox.widget.textbox()
local function update_volume()
	awful.spawn.easy_async_with_shell(
		"env XDG_RUNTIME_DIR=/run/user/$(id -u) wpctl get-volume @DEFAULT_SINK@",
		function(stdout, _, _, exitcode)
			if exitcode ~= 0 or not stdout then
				volume.markup = string.format("<span font='%s' size='13pt' rise='7000'>󰟢 </span>", beautiful.font)
				return
			end
			local muted = stdout:match("MUTED")
			local icon = muted and "󰸈 " or "󰕾 "
			volume.markup = string.format("<span font='%s' size='13pt' rise='7000'>%s</span>", beautiful.font, icon)
		end
	)
end
volume:buttons(
	gears.table.join(
		awful.button(
			{},
			1,
			function()
				awful.spawn("pavucontrol", false)
			end
		)
	)
)
_G.update_volume_icon = update_volume
gears.timer.delayed_call(update_volume)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- BATTERY --------------------------------------------------
------------------------------------------------------------------------------------------------------------

local battery = wibox.widget.textbox()
local function update_battery()
	awful.spawn.easy_async_with_shell(
		"bash -c 'STATUS=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null); " ..
			'CAPACITY=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null); echo "$STATUS $CAPACITY"\'',
		function(stdout)
			local status, percent_str = stdout:match("(%a+)%s+(%d+)")
			local percent = tonumber(percent_str)
			if not status or not percent then
				battery.markup = "<span foreground='" .. color_bad .. "'> ?</span>"
				return
			end

			local icon
			local color = beautiful.fg_normal

			if status == "Charging" or status == "Full" then
				icon = ""
				color = color_good
			else
				if percent <= 5 then
					icon = ""
					color = color_bad
				elseif percent <= 10 then
					icon = ""
					color = color_bad
				elseif percent <= 20 then
					icon = ""
					color = color_degraded
				elseif percent <= 50 then
					icon = ""
					color = beautiful.fg_normal
				elseif percent <= 80 then
					icon = ""
					color = beautiful.fg_normal
				elseif percent <= 90 then
					icon = ""
					color = beautiful.fg_normal
				else
					icon = ""
					color = color_good
				end
			end

			battery.markup =
				string.format("<span font='%s' foreground='%s'>%s%% %s </span>", beautiful.font, color, percent, icon)
		end
	)
end

gears.timer({timeout = 10, autostart = true, callback = update_battery})
gears.timer.delayed_call(update_battery)

------------------------------------------------------------------------------------------------------------
----------------------------------------------- DATE & TIME ------------------------------------------------
------------------------------------------------------------------------------------------------------------

local clock = wibox.widget.textbox()
local function update_clock()
	clock.markup = string.format("<span font='%s'>%s</span>", beautiful.font, os.date("%d.%m  %b %H:%M  "))
end
gears.timer({timeout = 60, autostart = true, callback = update_clock})
gears.timer.delayed_call(update_clock)
clock:buttons(
	gears.table.join(
		awful.button(
			{},
			1,
			function()
				awful.spawn("firefox --new-window https://calendar.google.com/calendar", false)
			end
		)
	)
)

------------------------------------------------------------------------------------------------------------
------------------------------------------------- SEPERATOR ------------------------------------------------
------------------------------------------------------------------------------------------------------------

local function sep()
	return wibox.widget(
		{
			markup = string.format(
				"<span font='%s' foreground='%s' size='13pt' rise='9000'> ❮ </span>",
				beautiful.font,
				"#8700ff"
			),
			widget = wibox.widget.textbox
		}
	)
end

------------------------------------------------------------------------------------------------------------
------------------------------------------------- STATUSBAR ------------------------------------------------
------------------------------------------------------------------------------------------------------------

statusbar.widget = {
	layout = wibox.layout.fixed.horizontal,
	icon_text("", network),
	sep(),
	icon_text("", bluetooth),
	sep(),
	icon_text("", volume),
	sep(),
	icon_text("", disk),
	sep(),
	icon_text("", sys),
	sep(),
	icon_text("", battery),
	sep(),
	icon_text("", clock),
	sep()
}

return statusbar
