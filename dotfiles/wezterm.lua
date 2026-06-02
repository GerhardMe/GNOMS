local wezterm = require("wezterm")
local act = wezterm.action

return {
    font = wezterm.font_with_fallback(
        {
            {family = "JetBrains Mono NL", weight = "DemiBold"},
            {family = "JetBrains Mono", weight = "DemiBold"},
            {family = "JetBrainsMono Nerd Font"}, -- patched version with glyphs
            {family = "Font Awesome 6 Free"}, -- optional, for explicit FA support
            {family = "Noto Color Emoji"} -- for emoji fallback
        }
    ),
    font_size = 11.0,
    --color_scheme = "deep",
    colors = {
        background = "#000000",
        foreground = "#ffffff",
        cursor_bg = "#8700FF",
        cursor_border = "#8700FF",
        ansi = {
            "#000000", -- black
            "#b90000", -- red
            "#00b600", -- green
            "#FFFF00", -- yellow
            "#0000FF", -- blue
            "#8700FF", -- magenta/purple (your violet)
            "#00cccc", -- cyan (your prompt cyan)
            "#C0C0C0" -- white
        },
        brights = {
            "#808080", -- bright black / gray
            "#ff0000", -- bright red
            "#00ff00", -- bright green
            "#FFFF55", -- bright yellow
            "#5555FF", -- bright blue
            "#AF5FFF", -- bright magenta (lighter violet variant)
            "#00ffff", -- bright cyan (lighter cyan variant)
            "#FFFFFF" -- bright white
        }
    },
    bold_brightens_ansi_colors = true,
    background = {
        {source = {Color = "#000000"}, opacity = 0.70, width = "100%", height = "100%"},
        {
            source = {File = os.getenv("HOME") .. "/.cache/gnoms/top_fade.png"},
            opacity = 1.0,
            width = "100%",
            height = 80,
            vertical_align = "Top",
            repeat_x = "NoRepeat",
            repeat_y = "NoRepeat"
        }
    },
    text_background_opacity = 1,
    window_decorations = "RESIZE",
    enable_tab_bar = false,
    enable_scroll_bar = false,
    default_cursor_style = "SteadyUnderline",
    scrollback_lines = 100000,
    force_reverse_video_cursor = false,
    selection_word_boundary = ' \t\n{}[]()"\'`.,;:!?',
    mouse_bindings = {
        -- Normal selection completes and COPIES to Clipboard
        {
            event = {Up = {streak = 1, button = "Left"}},
            mods = "NONE",
            action = act.CompleteSelection("Clipboard")
        },
        -- Shift+Left: if you were selecting, complete+copy; else open link
        {
            event = {Up = {streak = 1, button = "Left"}},
            mods = "SHIFT",
            action = act.CompleteSelectionOrOpenLinkAtMouseCursor("Clipboard")
        },
        -- “Up-only” gotcha: also swallow the matching Down so TUI apps don’t get half events
        {
            event = {Down = {streak = 1, button = "Left"}},
            mods = "SHIFT",
            action = act.Nop
        },
        -- Kill middle/right mouse paste entirely
        {event = {Down = {streak = 1, button = "Middle"}}, mods = "NONE", action = act.Nop},
        {event = {Up = {streak = 1, button = "Middle"}}, mods = "NONE", action = act.Nop},
        {event = {Down = {streak = 1, button = "Right"}}, mods = "NONE", action = act.Nop},
        {event = {Up = {streak = 1, button = "Right"}}, mods = "NONE", action = act.Nop}
    },
    -- keys: Shift+Insert paste; Ctrl+Shift C/V as backups; Alt+C copies selection (explicit)
    keys = {
        {key = "Insert", mods = "SHIFT", action = act.PasteFrom("Clipboard")}
    },
    enable_wayland = false,
    window_padding = {left = 4, right = 4, top = 3, bottom = 3},
    window_close_confirmation = "NeverPrompt",
    audible_bell = "Disabled"
}
