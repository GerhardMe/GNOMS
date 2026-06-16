return {
    -- Fuzzy finder
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {"nvim-lua/plenary.nvim"}
    },
    -- Treesitter
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate"
    },
    -- LSP
    {"neovim/nvim-lspconfig"},
    -- Multiple cursors (VS Code-style)
    {
        "mg979/vim-visual-multi",
        branch = "master",
        init = function()
            -- keep defaults (Ctrl-n, Ctrl-Down/Up, etc.)
            -- but set a sane leader so prompts show \ as VM leader
            vim.g.VM_leader = "\\"
        end
    },
    -- File explorer
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = {"nvim-tree/nvim-web-devicons"},
        config = function()
            local function on_attach(bufnr)
                local api = require("nvim-tree.api")
                local function o(desc)
                    return {desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true}
                end

                api.config.mappings.default_on_attach(bufnr)

                -- remove tree's default <Tab>=preview and set your keys (as before)
                pcall(vim.keymap.del, "n", "<Tab>", {buffer = bufnr})
                vim.keymap.set("n", "<Tab>", "<cmd>wincmd w<CR>", o("Next Window"))
                vim.keymap.set("n", "<S-Tab>", "<cmd>wincmd W<CR>", o("Prev Window"))
                vim.keymap.set("n", "<CR>", api.node.open.vertical, o("Open: Vertical Split"))
                vim.keymap.set("n", "v", api.node.open.vertical, o("Open: Vertical Split"))
                vim.keymap.set("n", "s", api.node.open.horizontal, o("Open: Horizontal Split"))
            end
            require("nvim-tree").setup(
                {
                    view = {
                        width = 30,
                        side = "left",
                        preserve_window_proportions = true
                    },
                    renderer = {
                        highlight_opened_files = "all",
                        root_folder_label = false
                    },
                    actions = {
                        open_file = {
                            quit_on_open = false,
                            resize_window = true,
                            window_picker = {enable = false}
                        }
                    },
                    on_attach = on_attach
                }
            )
        end
    },
    {
        "echasnovski/mini.map",
        version = false,
        config = function()
            local map = require("mini.map")
            map.setup({
                integrations = {
                    map.gen_integration.builtin_search(),
                    map.gen_integration.gitsigns(),
                    map.gen_integration.diagnostic(),
                },
                symbols = {
                    encode = map.gen_encode_symbols.dot("4x2"),
                },
                window = {
                    width = 18,
                    show_integration_count = false,
                },
            })
            map.open()
            vim.keymap.set("n", "<leader>mm", map.toggle, { noremap = true, silent = true, desc = "Toggle minimap" })
        end
    },
    -- Git signs
    {
        "lewis6991/gitsigns.nvim",
        dependencies = {"nvim-lua/plenary.nvim"},
        config = function()
            require("gitsigns").setup(
                {
                    signs = {
                        add = {text = "│"},
                        change = {text = "│"},
                        delete = {text = "_"},
                        topdelete = {text = "‾"},
                        changedelete = {text = "~"},
                        untracked = {text = "┆"}
                    },
                    current_line_blame = false
                }
            )
        end
    },
    {
        "stevearc/conform.nvim",
        event = {"BufWritePre"},
        opts = {
            format_on_save = function(_)
                return {timeout_ms = 1500, lsp_fallback = true}
            end,
            formatters_by_ft = {
                lua = {"stylua"},
                javascript = {"prettier"},
                typescript = {"prettier"},
                tsx = {"prettier"},
                jsx = {"prettier"},
                json = {"prettier"},
                yaml = {"prettier"},
                css = {"prettier"},
                html = {"prettier"},
                markdown = {"prettier"},
                python = {"black"},
                sh = {"shfmt"},
                nix = {"nixfmt"}, -- or "alejandra"
                ["_"] = {"trim_whitespace"}
            }
        },
        config = function(_, opts)
            local conform = require("conform")
            conform.setup(opts)

            local function format_then_write()
                conform.format({async = false, lsp_fallback = true})
                vim.cmd("silent! write")
            end

            -- kill any old <C-s> (since you said it doesn't work / not needed)
            pcall(vim.keymap.del, "n", "<C-s>")
            pcall(vim.keymap.del, "x", "<C-s>")
            pcall(vim.keymap.del, "i", "<C-s>")

            -- ONE simple global map: normal-mode 's' => format + save
            vim.keymap.set("n", "s", format_then_write, {noremap = true, silent = true, desc = "Format + Save"})
        end
    }
}
