-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git", "clone", "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- Mouse
vim.opt.mouse = "a"

-- Basics
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.termguicolors = true

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.smartindent = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- Splits
vim.opt.splitbelow = true
vim.opt.splitright = true

-- Treesitter (built-in since nvim 0.10)
vim.api.nvim_create_autocmd("FileType", {
    pattern = "*",
    callback = function()
        pcall(vim.treesitter.start)
    end,
})

-- A better hover implementation
--
local function hover_with_definition()
    local win = vim.api.nvim_get_current_win()
    local client = vim.lsp.get_clients({ bufnr = 0 })[1]
    local params = vim.lsp.util.make_position_params(
        win,
        client and client.offset_encoding or "utf-16"
    )

    vim.lsp.buf_request(0, "textDocument/definition", params, function(_, definition)
        local location

        if definition then
            if definition.uri or definition.targetUri then
                location = definition
            elseif definition[1] then
                location = definition[1]
            end
        end

        vim.lsp.buf_request(0, "textDocument/hover", params, function(_, hover)
            if not hover or not hover.contents then
                return
            end

            local lines = {}

            if location then
                local uri = location.uri or location.targetUri
                local range = location.range or location.targetSelectionRange

                if uri and range then
                    local path = vim.fn.fnamemodify(
                        vim.uri_to_fname(uri),
                        ":."
                    )
                    local line = range.start.line + 1

                    table.insert(
                        lines,
                        string.format("Defined at: %s:%d", path, line)
                    )
                    table.insert(lines, "")
                end
            end

            vim.list_extend(
                lines,
                vim.lsp.util.convert_input_to_markdown_lines(hover.contents)
            )

            vim.lsp.util.open_floating_preview(lines, "markdown", {
                border = "rounded",
            })
        end)
    end)
end

-- Markdown: don't hide syntax behind conceal
vim.g.markdown_recommended_style = 0
vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function()
        vim.opt_local.conceallevel = 0
        vim.opt_local.wrap = true
        vim.opt_local.linebreak = true
    end,
})

-- Plugins
require("lazy").setup({
    -- Colorscheme
    {
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            vim.cmd.colorscheme("tokyonight")
        end,
    },

    -- Fuzzy finder
    {
        "nvim-telescope/telescope.nvim",
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            require("telescope").setup({
                defaults = {
                    path_display = { "filename_first" },
                },
            })
        end,
        keys = {
            { "<C-p>", function() require("telescope.builtin").find_files() end, desc = "Find file" },
            { "<leader>fg", function() require("telescope.builtin").live_grep() end, desc = "Search in files" },
            { "<leader>fb", function() require("telescope.builtin").buffers() end, desc = "Open buffers" },
            { "<leader>fd", function() require("telescope.builtin").diagnostics() end, desc = "LSP diagnostics" },
            { "<leader>fs", function() require("telescope.builtin").lsp_document_symbols() end, desc = "Symbols in file" },
            { "<leader>fw", function() require("telescope.builtin").lsp_dynamic_workspace_symbols() end, desc = "Symbols in project" },
        },
    },

    -- File tree
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            vim.g.loaded_netrw = 1
            vim.g.loaded_netrwPlugin = 1
            require("nvim-tree").setup({
                actions = {
                    open_file = {
                        resize_window = false,
                    },
                },
            })
        end,
        keys = {
            { "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file tree" },
            { "<leader>f", "<cmd>NvimTreeFindFile<CR>", desc = "Reveal current file" },
        },
    },

    -- LSP (nvim-lspconfig still needed for server configs, but use new API)
    {
        "neovim/nvim-lspconfig",
        config = function()
            if vim.fn.executable("rust-analyzer") == 1 then
                vim.lsp.config("rust_analyzer", {})
                vim.lsp.enable("rust_analyzer")
            end

            -- TypeScript 7+ (native) ships its own language server: `tsc --lsp --stdio`.
            -- TypeScript 6 and older need typescript-language-server (ts_ls).
            -- Pick per project from the project's installed typescript, falling back
            -- to the tsc on PATH when the project has none.
            local ts_roots = { "tsconfig.json", "jsconfig.json", "package.json", ".git" }
            local ts_filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" }

            -- nearest node_modules (walking up, for hoisted monorepos) that has typescript
            local function ts_node_modules(root)
                local dir = root
                while dir do
                    if vim.uv.fs_stat(dir .. "/node_modules/typescript/package.json") then
                        return dir .. "/node_modules"
                    end
                    local parent = vim.fs.dirname(dir)
                    dir = parent ~= dir and parent or nil
                end
            end

            local global_ts_major
            local function ts_major(root)
                local node_modules = ts_node_modules(root)
                if node_modules then
                    local ok, pkg = pcall(vim.json.decode,
                        table.concat(vim.fn.readfile(node_modules .. "/typescript/package.json"), "\n"))
                    local major = ok and tonumber(tostring(pkg.version):match("^(%d+)"))
                    if major then return major end
                end
                if global_ts_major == nil then
                    local out = vim.fn.executable("tsc") == 1
                        and vim.system({ "tsc", "--version" }, { text = true }):wait().stdout
                        or ""
                    global_ts_major = tonumber(out:match("Version%s+(%d+)")) or 0
                end
                return global_ts_major
            end

            -- attach only when the project's TypeScript matches this server
            local function ts_root_dir(native)
                return function(bufnr, on_dir)
                    local root = vim.fs.root(bufnr, ts_roots)
                    if root and (ts_major(root) >= 7) == native then
                        on_dir(root)
                    end
                end
            end

            vim.lsp.config("tsc_lsp", {
                -- prefer the project's own tsc, else the one on PATH
                cmd = function(dispatchers, config)
                    local node_modules = config.root_dir and ts_node_modules(config.root_dir)
                    local local_tsc = node_modules and node_modules .. "/.bin/tsc"
                    local exe = local_tsc and vim.uv.fs_stat(local_tsc) and local_tsc or "tsc"
                    return vim.lsp.rpc.start({ exe, "--lsp", "--stdio" }, dispatchers)
                end,
                filetypes = ts_filetypes,
                root_dir = ts_root_dir(true),
            })
            vim.lsp.enable("tsc_lsp")

            if vim.fn.executable("typescript-language-server") == 1 then
                vim.lsp.config("ts_ls", { root_dir = ts_root_dir(false) })
                vim.lsp.enable("ts_ls")
            end
        end,
    },

    -- Git stuff
    {
        "tpope/vim-fugitive",
    },

    -- Markdown: off by default so you edit raw text; toggle on to read
    {
        "MeanderingProgrammer/render-markdown.nvim",
        dependencies = { "nvim-web-devicons" },
        ft = "markdown",
        opts = { enabled = false },
        keys = {
            { "<leader>mr", "<cmd>RenderMarkdown toggle<CR>", desc = "Toggle markdown render" },
        },
    },

    -- Symbol tree (like IntelliJ's Structure view)
    {
        "stevearc/aerial.nvim",
        config = function()
            require("aerial").setup({
                layout = { min_width = 30 },
                attach_mode = "global",
            })
        end,
        keys = {
            { "<leader>a", "<cmd>AerialToggle!<CR>", desc = "Toggle symbol tree" },
        },
    },
})

-- LSP keybindings (active when an LSP server attaches)
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local opts = { buffer = args.buf }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)        -- go to definition
        vim.keymap.set("n", "K", hover_with_definition, opts)              -- hover docs
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)    -- rename symbol
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts)        -- show diagnostic under cursor
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)         -- previous diagnostic
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)         -- next diagnostic
        vim.keymap.set("n", "<leader>q", ":cclose<CR>", opts)
    end,
})

vim.keymap.set("n", "<leader>tw", function()
    local file = vim.fn.expand("%:p")
    local source_win = vim.api.nvim_get_current_win()

    local root = vim.fs.root(file, {
        "vitest.config.ts",
        "vitest.config.js",
        "package.json",
    })

    if not root then
        vim.notify("Could not find Vitest/package root", vim.log.levels.ERROR)
        return
    end

    vim.cmd("botright 60vnew")

    vim.fn.jobstart({
        "pnpm",
        "exec",
        "vitest",
        file,
    }, {
        term = true,
        cwd = root,
    })

    vim.api.nvim_set_current_win(source_win)
end, { desc = "Vitest watch current file" })
vim.keymap.set("n", "<leader>tf", function()
    local file = vim.fn.expand("%:p")
    local source_win = vim.api.nvim_get_current_win()

    local root = vim.fs.root(file, {
        "vitest.config.ts",
        "vitest.config.js",
        "package.json",
    })

    if not root then
        vim.notify("Could not find Vitest/package root", vim.log.levels.ERROR)
        return
    end

    vim.cmd("botright 60vnew")

    vim.fn.jobstart({
        "pnpm",
        "exec",
        "vitest",
        "run",
        file,
    }, {
        term = true,
        cwd = root,
    })

    vim.api.nvim_set_current_win(source_win)
end, { desc = "Vitest run current file once" })

vim.keymap.set("n", "<leader>tc", function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)

        if vim.bo[buf].buftype == "terminal" then
            vim.api.nvim_win_close(win, true)
        end
    end
end, { desc = "Close test terminal" })
