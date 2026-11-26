-- Client updates: borders and shape, focus follows the mouse, floating on top.

local awful = require("awful")
local beautiful = require("beautiful")

------------------------------------------------------------------------------------------------------------
------------------------------------------------- UPDATING CLIENTS -----------------------------------------
------------------------------------------------------------------------------------------------------------

-- Border and shape
local function update_client_decoration(c)
	local clients = c.screen.tiled_clients
	local only_one = (#clients == 1)
	local is_floating = c.floating
	local is_fullscreen = c.fullscreen

	if (only_one and not is_floating) or is_fullscreen then
		c.border_width = 0
		c.shape = nil
	else
		c.border_width = beautiful.border_width
		c.shape = beautiful.client_shape
	end
end


-- mouse can change focus
client.connect_signal(
	"mouse::enter",
	function(c)
		c:emit_signal("request::activate", "mouse_enter", {raise = false})
	end
)

------------------------------------------- Other client updates -------------------------------------------

client.connect_signal(
	"manage",
	function(c)
		if awesome.startup and not c.size_hints.user_position and not c.size_hints.program_position then
			awful.placement.no_offscreen(c)
		end
		update_client_decoration(c)
		c.maximized = false
	end
)

client.connect_signal(
	"focus",
	function(c)
		c.border_color = beautiful.border_focus
		update_client_decoration(c)
	end
)

client.connect_signal(
	"unfocus",
	function(c)
		c.border_color = beautiful.border_normal
		update_client_decoration(c)
	end
)

tag.connect_signal(
	"property::selected",
	function(t)
		for _, c in ipairs(t:clients()) do
			update_client_decoration(c)
		end
	end
)

client.connect_signal(
	"property::floating",
	function(c)
		if not c.fullscreen then
			if c.floating then
				c.ontop = true
			else
				c.ontop = false
			end
		end
		update_client_decoration(c)
	end
)

client.connect_signal("property::fullscreen", update_client_decoration)
