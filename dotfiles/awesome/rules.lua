-- Client rules: which windows float, where they go, and their size.

local awful = require("awful")
local beautiful = require("beautiful")
local client_input = require("keys")

------------------------------------------------------------------------------------------------------------
------------------------------------------------- CLIENT RULES ---------------------------------------------
------------------------------------------------------------------------------------------------------------

awful.rules.rules = {
	-- All clients:
	{
		rule = {},
		properties = {
			border_width = beautiful.border_width,
			border_color = beautiful.border_normal,
			focus = awful.client.focus.filter,
			raise = true,
			keys = client_input.keys,
			buttons = client_input.buttons,
			screen = awful.screen.preferred,
			placement = awful.placement.no_offscreen
		}
	},
	-- Floating clients:
	{
		rule_any = {
			instance = {},
			class = {
				"arandr",
				".blueman-manager-wrapped",
				"tor browser",
				"pavucontrol",
				"baobab",
				"Qalculate-gtk",
				"proton-vpn"
			},
			name = {"blueman-manager"},
			role = {"blueman-manager"}
		},
		properties = {
			floating = true,
			placement = function(c)
				awful.placement.centered(
					c,
					{
						parent = awful.screen.focused(),
						honor_workarea = false,
						honor_padding = true
					}
				)
			end
		}
	},
	-- ARandR:
	{
		rule_any = {
			instance = {},
			class = {
				"arandr"
			}
		},
		properties = {
			floating = true,
			ontop = true,
			placement = function(c)
				awful.placement.centered(
					c,
					{
						parent = awful.screen.focused(),
						honor_workarea = false,
						honor_padding = true
					}
				)
			end,
			width = 1000,
			height = 600
		}
	},
	-- iPhone camera window (phonecam), movable; f in mpv for fullscreen:
	{
		rule = {instance = "phonecam"},
		properties = {
			floating = true,
			ontop = true,
			placement = awful.placement.centered
		}
	},
	-- Terminal popups:
	{
		rule_any = {class = {"popup"}, instance = {"popup"}},
		properties = {
			floating = true,
			placement = function(c)
				awful.placement.centered(
					c,
					{
						parent = awful.screen.focused(),
						honor_workarea = false,
						honor_padding = true
					}
				)
			end,
			width = 1000,
			height = 800,
			ontop = true
		}
	},
	-- Battery warnings:
	{
		rule = {name = "battery_warning_popup"},
		properties = {
			floating = true,
			placement = function(c)
				awful.placement.centered(
					c,
					{
						parent = awful.screen.focused(),
						honor_workarea = false,
						honor_padding = true
					}
				)
			end,
			width = 1000,
			height = 200,
			ontop = true
		}
	},
	-- Terminals:
	{
		rule_any = {class = {"WezTerm", "Xfce4-terminal", "XTerm", "URxvt", "Alacritty", "kitty", "st"}},
		properties = {size_hints_honor = false}
	}
}
