-- Startup: run startup.sh, restore the visible tags after a reload, and preload
-- a Firefox on the hidden "preload" tag (except in server mode).

local gears = require("gears")
local awful = require("awful")
local home = os.getenv("HOME")

------------------------------------------------------------------------------------------------------------
------------------------------------------------- STARTUP --------------------------------------------------
------------------------------------------------------------------------------------------------------------

gears.timer.delayed_call(
	function()
		-- --- server mode check (sync + simple) ---
		local function is_server_mode()
			local xdg = os.getenv("XDG_CONFIG_HOME")
			local home = os.getenv("HOME") or "~"
			local state_file = (xdg and (xdg .. "/mode/state")) or (home .. "/.config/mode/state")
			local f = io.open(state_file, "r")
			if not f then
				return false
			end
			local s = f:read("*a") or ""
			f:close()
			s = s:gsub("%s+", "")
			return s == "server"
		end

		-- Find the first valid "preload" tag across all screens
		local function find_preload_tag()
			for s in screen do
				if s.valid then
					local t = awful.tag.find_by_name(s, "preload")
					if t and t.screen and t.screen.valid then
						return t
					end
				end
			end
			return nil
		end

		-- Async: is Firefox already running?
		local function firefox_running(cb)
			awful.spawn.easy_async_with_shell(
				[[pgrep -x firefox >/dev/null && echo RUNNING || echo NOT]],
				function(out)
					cb(out:match("RUNNING") ~= nil)
				end
			)
		end

		-- Spawn FF and move it to the tag once managed
		local function spawn_firefox_on_tag(t)
			local placed = false
			local function on_manage(c)
				if placed then
					return
				end
				if c.class and c.class:lower() == "firefox" then
					placed = true
					client.disconnect_signal("manage", on_manage)
					if t and t.screen and t.screen.valid then
						c:move_to_tag(t)
					end
				end
			end
			client.connect_signal("manage", on_manage)
			awful.spawn("firefox --new-instance --private-window about:blank")
		end

		-- Get back to old TAG if reloaded
		local function reload_tag()
			local f = io.open("/tmp/awesome-visible-tags", "r")
			if not f then
				return
			end

			local restore_map = {}
			local lines = {}
			for line in f:lines() do
				table.insert(lines, line)
				local screen_id, tag_name = line:match("^(%d+):(.+)$")
				if screen_id and tag_name then
					restore_map[tonumber(screen_id)] = tag_name
				end
			end
			f:close()

			for s in screen do
				local i = s.index
				local wanted = restore_map[i]
				if wanted then
					local found = false
					for _, t in ipairs(s.tags or {}) do
						if t.name == wanted then
							t:view_only()
							found = true
							break
						end
					end
				end
			end

			os.remove("/tmp/awesome-visible-tags")
		end

		-- startup programs
		awful.spawn.with_shell(home .. "/GNOMS/scripts/startup.sh")

		-- reload TAGs
		gears.timer(
			{
				timeout = 0,
				autostart = true,
				single_shot = true,
				callback = function()
					reload_tag()
				end
			}
		)

		-- Delay a tick to let X settle (dock/external monitors etc.)
		gears.timer(
			{
				timeout = 0.7,
				autostart = true,
				single_shot = true,
				callback = function()
					-- if server mode, do nothing
					if is_server_mode() then
						return
					end

					local preload_tag = find_preload_tag()
					if not preload_tag then
						return
					end

					firefox_running(
						function(running)
							if running then
								return
							end
							spawn_firefox_on_tag(preload_tag)
						end
					)
				end
			}
		)
	end
)
