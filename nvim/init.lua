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

-- Reload buffers an agent in a terminal pane has changed on disk. Focus never leaves Neovim then, so
-- checktime runs on a timer and on cursor and terminal events, not only on FocusGained.
vim.opt.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI", "TermLeave", "TermClose" }, {
    callback = function()
        if vim.fn.getcmdwintype() == "" then
            vim.cmd.checktime()
        end
    end,
})
vim.uv.new_timer():start(1000, 1000, vim.schedule_wrap(function()
    if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
        vim.cmd.checktime()
    end
end))
vim.api.nvim_create_autocmd("FileChangedShellPost", {
    callback = function(args)
        vim.notify("Reloaded " .. vim.fn.fnamemodify(args.file, ":~:."), vim.log.levels.INFO)
    end,
})

-- Terminal: one key out of a Claude Code pane. <Esc> stays with the program inside.
vim.keymap.set("t", "<C-p>", "<C-\\><C-n>", { desc = "Leave terminal mode" })

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

-- The files under the cwd for Telescope, with the most recently used buffers first
function RecentThenAllFiles()
    local cwd = vim.uv.cwd()
    local current = vim.api.nvim_get_current_buf()
    local seen = {}
    local results = {}
    local function add(path)
        if not seen[path] then
            seen[path] = true
            table.insert(results, path)
        end
    end

    local buffers = vim.fn.getbufinfo({ buflisted = 1 })
    table.sort(buffers, function(a, b) return a.lastused > b.lastused end)
    local recent = 0
    for _, buffer in ipairs(buffers) do
        local usable = buffer.bufnr ~= current and buffer.name ~= "" and vim.bo[buffer.bufnr].buftype == ""
        if usable and recent < 10 then
            add(vim.fs.relpath(cwd, buffer.name) or buffer.name)
            recent = recent + 1
        end
    end

    local listing = vim.system({ "rg", "--files" }, { cwd = cwd, text = true }):wait()
    for _, path in ipairs(vim.split(listing.stdout or "", "\n", { trimempty = true })) do
        add(path)
    end

    local config = require("telescope.config").values
    require("telescope.pickers").new({}, {
        prompt_title = "Find file",
        finder = require("telescope.finders").new_table({
            results = results,
            entry_maker = require("telescope.make_entry").gen_from_file({ cwd = cwd }),
        }),
        sorter = config.file_sorter({}),
        previewer = config.file_previewer({}),
    }):find()
end

-- Plugins
local function agent_workspaces_available()
    if vim.fn.executable("gh") == 1 then
        local result = vim.system({
            "gh", "repo", "view", "devslash-paul/agent-workspaces.nvim", "--json", "name",
        }, { text = true }):wait()
        if result.code == 0 then return true end
    end

    -- Fall back to the user's GitHub SSH access when gh is unavailable or unauthenticated.
    if vim.fn.executable("git") ~= 1 then return false end
    local result = vim.system({
        "git", "ls-remote", "--exit-code", "git@github.com:devslash-paul/agent-workspaces.nvim.git", "HEAD",
    }, {
        text = true,
        env = { GIT_SSH_COMMAND = "ssh -o BatchMode=yes -o ConnectTimeout=5" },
    }):wait()
    return result.code == 0
end

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
            -- Recent buffers first, most recent nearest the prompt, then every file: up and down walk the recent
            -- files before any typing, and typing fuzzes over all of them
            { "<C-p>", function() RecentThenAllFiles() end, desc = "Find file" },
            { "<leader>fg", function() require("telescope.builtin").live_grep() end, desc = "Search in files" },
            { "<leader>fb", function() require("telescope.builtin").buffers() end, desc = "Open buffers" },
            { "<leader>fd", function() require("telescope.builtin").diagnostics({ bufnr = 0 }) end, desc = "Diagnostics in file" },
            { "<leader>fD", function() require("telescope.builtin").diagnostics() end, desc = "Diagnostics in workspace" },
            -- IntelliJ's file-structure popup: aerial's tree in file order, members indented under their type
            {
                "<leader>fs",
                function()
                    require("aerial")
                    local telescope = require("telescope")
                    telescope.load_extension("aerial")
                    telescope.extensions.aerial.aerial({
                        show_columns = "symbols",
                        sorting_strategy = "ascending",
                        layout_config = { prompt_position = "top" },
                        get_entry_text = function(item)
                            return string.rep("    ", item.level or 0) .. item.name
                        end,
                    })
                end,
                desc = "Structure of file",
            },
            { "<leader>fS", function() require("telescope.builtin").lsp_document_symbols() end, desc = "All symbols in file" },
            { "<leader>fw", function() require("telescope.builtin").lsp_dynamic_workspace_symbols() end, desc = "Symbols in project" },
            -- Replaces Neovim's built-in grr, which fills the quickfix pane
            { "grr", function() require("telescope.builtin").lsp_references({ include_declaration = false }) end, desc = "References" },
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
                -- Wide enough for the agent-workspaces pane's branch names and conversation titles
                view = { width = 52 },
                update_focused_file = { enable = true },
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

    -- Claude Code / Codex conversations grouped by Git worktree, below nvim-tree.
    -- The private GitHub repository is available to lazy.nvim via the configured gh auth.
    {
        url = "git@github.com:devslash-paul/agent-workspaces.nvim.git",
        name = "agent-workspaces.nvim",
        enabled = agent_workspaces_available(),
        lazy = false,
        config = function()
            require("agent-workspaces").setup({
                -- A worker silent for three hours is sent /handoff and stopped; the overseer respawns it.
                retire_after = { worker = 3 * 60 * 60 },
                providers = {
                    claude = {
                        -- Pinned per role, so changing the default model in Claude Code moves neither.
                        role_args = {
                            overseer = { "--model", "claude-fable-5-1" },
                            worker = { "--model", "claude-opus-5-5" },
                        },
                    },
                },
            })
        end,
        keys = {
            { "<leader>aw", "<cmd>AgentWorkspacesToggle<CR>", desc = "Toggle agent workspaces" },
            { "<leader>ar", "<cmd>AgentWorkspacesRefresh<CR>", desc = "Refresh agent workspaces" },
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
                    -- one server per monorepo, so references reach the packages that import this one
                    local root = vim.fs.root(bufnr, { "pnpm-workspace.yaml", ts_roots })
                    if root and (ts_major(root) >= 7) == native then
                        on_dir(root)
                    end
                end
            end

            -- tsserver searches only the projects it has loaded, and loads one when a file of it opens. The repo's
            -- <git common dir>/nvim-ts-projects names packages, one per line, for the main checkout and every worktree;
            -- one source file of each is opened at start, so references reach them without a buffer open.
            local function load_named_projects(client)
                local root = client.root_dir
                if not root then
                    return
                end
                local common = vim.trim(vim.system({ "git", "-C", root, "rev-parse", "--path-format=absolute",
                    "--git-common-dir" }, { text = true }):wait().stdout or "")
                local list = common .. "/nvim-ts-projects"
                if common == "" or not vim.uv.fs_stat(list) then
                    return
                end
                local wanted = {}
                for _, line in ipairs(vim.fn.readfile(list)) do
                    local name = vim.trim(line:gsub("#.*", ""))
                    if name ~= "" then
                        wanted[name] = true
                    end
                end
                local files = vim.system({ "git", "-C", root, "ls-files", "--", "*package.json", "*.ts", "*.tsx" },
                    { text = true }):wait().stdout or ""
                local paths = vim.split(files, "\n", { trimempty = true })
                for _, manifest in ipairs(paths) do
                    if manifest:match("package%.json$") then
                        local ok, pkg = pcall(vim.json.decode, table.concat(vim.fn.readfile(root .. "/" .. manifest), "\n"))
                        if ok and wanted[pkg.name] then
                            local src = vim.fs.dirname(manifest) .. "/src/"
                            for _, path in ipairs(paths) do
                                if vim.startswith(path, src) and path:match("%.tsx?$") and not path:match("%.d%.ts$") then
                                    local file = root .. "/" .. path
                                    client:notify("textDocument/didOpen", {
                                        textDocument = {
                                            uri = vim.uri_from_fname(file),
                                            languageId = path:match("%.tsx$") and "typescriptreact" or "typescript",
                                            version = 0,
                                            text = table.concat(vim.fn.readfile(file), "\n"),
                                        },
                                    })
                                    break
                                end
                            end
                        end
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
                vim.lsp.config("ts_ls", { root_dir = ts_root_dir(false), on_init = load_named_projects })
                vim.lsp.enable("ts_ls")
            end

            -- Packages that import a library read it through its built declarations, so references and types across
            -- packages go stale as its source moves. Rebuild a declaration-emitting package on save, one build at a time.
            local declaration_builds = {}
            local function rebuild_declarations(dir)
                local build = declaration_builds[dir]
                if build then
                    build.again = true
                    return
                end
                declaration_builds[dir] = { again = false }
                local node_modules = ts_node_modules(dir)
                local tsc = node_modules and node_modules .. "/.bin/tsc" or "tsc"
                -- A failed build is not reported: the server already shows the same errors as diagnostics,
                -- and a package mid-edit fails to build on most saves.
                vim.system({ tsc, "-p", dir }, { text = true }, vim.schedule_wrap(function()
                    local again = declaration_builds[dir].again
                    declaration_builds[dir] = nil
                    if again then
                        rebuild_declarations(dir)
                    end
                end))
            end
            vim.api.nvim_create_autocmd("BufWritePost", {
                pattern = { "*.ts", "*.tsx" },
                callback = function(args)
                    if args.file:match("%.spec%.tsx?$") then
                        return
                    end
                    local dir = vim.fs.root(args.buf, "tsconfig.json")
                    local config = dir and table.concat(vim.fn.readfile(dir .. "/tsconfig.json"), "\n") or ""
                    if config:match('"declaration"%s*:%s*true') then
                        rebuild_declarations(dir)
                    end
                end,
            })

            if vim.fn.executable("pyright-langserver") == 1 then
                -- pyright resolves imports against the python on PATH; use the project's uv venv instead
                vim.lsp.config("pyright", {
                    before_init = function(_, config)
                        local python = config.root_dir and config.root_dir .. "/.venv/bin/python"
                        if python and vim.uv.fs_stat(python) then
                            config.settings.python = vim.tbl_extend("force", config.settings.python or {},
                                { pythonPath = python })
                        end
                    end,
                })
                vim.lsp.enable("pyright")
            end
            if vim.fn.executable("ruff") == 1 then
                vim.lsp.enable("ruff")
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
        lazy = false,
        config = function()
            require("aerial").setup({
                layout = { min_width = 30, default_direction = "right", placement = "edge" },
                attach_mode = "global",
                open_automatic = true,
                -- aerial's default kinds, plus Variable: the TypeScript server reports a type alias as a variable
                filter_kind = { "Class", "Constructor", "Enum", "Function", "Interface", "Module", "Method", "Struct", "Variable" },
                -- Keep top-level symbols and members of a type. Nothing from inside a function, method,
                -- variable or property body, and no anonymous callbacks.
                post_parse_symbol = function(_, item)
                    if item.name == "<function>" or item.name:match("callback$") then
                        return false
                    end
                    local parent = item.parent
                    if not parent then
                        return true
                    end
                    local containers = { Class = true, Interface = true, Struct = true, Enum = true, Module = true, Namespace = true }
                    return containers[parent.kind] == true
                end,
            })
        end,
        keys = {
            { "<leader>a", "<cmd>AerialToggle!<CR>", desc = "Toggle symbol tree" },
        },
    },

    -- Focus mode: the current buffer alone, 140 columns wide and centred, at any terminal size
    {
        "junegunn/goyo.vim",
        cmd = "Goyo",
        init = function()
            vim.g.goyo_width = 140
        end,
        keys = {
            { "<leader>Z", "<cmd>Goyo<CR>", desc = "Toggle focus mode" },
        },
    },
})

-- Completion: on request only (<C-Space>), never automatic
vim.opt.completeopt = { "menu", "menuone", "noselect", "fuzzy", "popup" }
vim.opt.pumheight = 12
vim.opt.pumwidth = 32
vim.opt.pumborder = "rounded"
vim.opt.winborder = "rounded"

-- Menu and its docs window sit on their own darker surface so they don't bleed into code
local function popup_colours()
    vim.api.nvim_set_hl(0, "Pmenu", { bg = "#16161e", fg = "#c0caf5" })
    vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#283457", bold = true })
    vim.api.nvim_set_hl(0, "PmenuBorder", { bg = "#16161e", fg = "#3b4261" })
    vim.api.nvim_set_hl(0, "PmenuExtra", { bg = "#16161e", fg = "#565f89" })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = "#16161e" })
    vim.api.nvim_set_hl(0, "FloatBorder", { bg = "#16161e", fg = "#3b4261" })
end
popup_colours()
vim.api.nvim_create_autocmd("ColorScheme", { callback = popup_colours })

local function pum_or(key, fallback)
    return function()
        if vim.fn.pumvisible() == 1 then
            return key
        end
        return fallback
    end
end

-- LSP keybindings (active when an LSP server attaches)
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local opts = { buffer = args.buf }
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client:supports_method("textDocument/completion") then
            vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = false })
            vim.keymap.set("i", "<C-Space>", vim.lsp.completion.get, opts)
            local expr = { buffer = args.buf, expr = true }
            vim.keymap.set("i", "<Tab>", pum_or("<C-n>", "<Tab>"), expr)
            vim.keymap.set("i", "<S-Tab>", pum_or("<C-p>", "<S-Tab>"), expr)
            vim.keymap.set("i", "<CR>", pum_or("<C-y>", "<CR>"), expr)
        end
        -- Jumps when there is one definition; picks in a popup, as grr does, when there are several
        vim.keymap.set("n", "gd", function() require("telescope.builtin").lsp_definitions() end, opts)
        vim.keymap.set("n", "K", hover_with_definition, opts)              -- hover docs
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)    -- rename symbol
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
        -- Diagnostics on the cursor line, else every diagnostic in the buffer: a parse error mid-edit often lands
        -- on the line after the one being typed, which an unscoped open_float would show as nothing.
        vim.keymap.set("n", "gl", function()
            local line = vim.api.nvim_win_get_cursor(0)[1] - 1
            if #vim.diagnostic.get(0, { lnum = line }) > 0 then
                vim.diagnostic.open_float()
            else
                vim.diagnostic.open_float({ scope = "buffer" })
            end
        end, opts)
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

-- Git branch files: a deliberately small, right-hand navigation sidebar.
-- <leader>gf toggles it; / (or <CR>) fuzzy-finds its files.
do
    local git_sidebar = { win = nil, buf = nil, root = nil, files = {} }

    local function lines(cmd, cwd)
        local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
        if result.code ~= 0 then return {} end
        return vim.split(vim.trim(result.stdout or ""), "\n", { trimempty = true })
    end

    local function gh_pr(root)
        if vim.fn.executable("gh") ~= 1 then return nil end
        local result = vim.system({
            "gh", "pr", "view", "--json", "baseRefName,commits",
        }, { cwd = root, text = true }):wait()
        if result.code ~= 0 or not result.stdout or result.stdout == "" then return nil end
        return vim.json.decode(result.stdout)
    end

    -- The PR's base (or the default branch), preferring the remote ref because local main is often stale.
    -- @{upstream} is not used: it is usually origin/<this branch>, which diffs to nothing once pushed.
    local function branch_base(root, pr)
        local name = pr and pr.baseRefName
        if not name then
            local head = lines({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" }, root)[1]
            name = head and head:gsub("^origin/", "") or "main"
        end
        for _, candidate in ipairs({ "origin/" .. name, name }) do
            if #lines({ "git", "rev-parse", "--verify", "--quiet", candidate }, root) > 0 then
                return candidate
            end
        end
        return nil
    end

    local pr_cache = {}

    -- Files open in the window the sidebar was opened from, else the largest file window in the tab
    local function editor_window()
        local function usable(win)
            return win and vim.api.nvim_win_is_valid(win) and win ~= git_sidebar.win
                and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
                and vim.api.nvim_win_get_config(win).relative == ""
                and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == ""
                and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "NvimTree"
        end
        if usable(git_sidebar.source_win) then return git_sidebar.source_win end
        local best, best_area
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local area = vim.api.nvim_win_get_width(win) * vim.api.nvim_win_get_height(win)
            if usable(win) and (not best_area or area > best_area) then best, best_area = win, area end
        end
        return best
    end

    local function open_file(path)
        local target = editor_window()
        if target then
            vim.api.nvim_set_current_win(target)
        elseif git_sidebar.win and vim.api.nvim_win_is_valid(git_sidebar.win) then
            vim.api.nvim_set_current_win(git_sidebar.win)
            vim.cmd("leftabove vnew")
        end
        vim.cmd("edit " .. vim.fn.fnameescape(git_sidebar.root .. "/" .. path))
    end

    local function fuzzy_files()
        if #git_sidebar.files == 0 then return end
        require("telescope.pickers").new({}, {
            prompt_title = "Branch files",
            finder = require("telescope.finders").new_table({ results = git_sidebar.files }),
            sorter = require("telescope.config").values.generic_sorter({}),
            previewer = require("telescope.previewers").vim_buffer_cat.new({}),
            attach_mappings = function(_, map)
                local actions = require("telescope.actions")
                local action_state = require("telescope.actions.state")
                local function select()
                    local entry = action_state.get_selected_entry()
                    actions.close(_)
                    if entry then open_file(entry[1] or entry.value) end
                end
                map("i", "<CR>", select)
                map("n", "<CR>", select)
                return true
            end,
        }):find()
    end

    local function refresh()
        -- Terminal and plugin-pane buffers have no file path, and the cwd may be a removed worktree
        local file = vim.bo.buftype == "" and vim.fn.expand("%:p") or ""
        local cwd = vim.uv.cwd()
        local start = (file:sub(1, 1) == "/" and file) or (cwd and vim.fn.isdirectory(cwd) == 1 and cwd)
        local root = start and vim.fs.root(start, { ".git" })
        if not root then vim.notify("Not inside a Git repository", vim.log.levels.WARN); return end
        local branch = lines({ "git", "branch", "--show-current" }, root)[1] or "HEAD"
        local key = root .. ":" .. branch
        if pr_cache[key] == nil then
            pr_cache[key] = gh_pr(root) or false
        end
        local pr = pr_cache[key] or nil
        local base = branch_base(root, pr)
        if not base then vim.notify("Could not determine branch base", vim.log.levels.WARN); return end
        local fork = lines({ "git", "merge-base", base, "HEAD" }, root)[1]
        if not fork then vim.notify("No merge base with " .. base, vim.log.levels.WARN); return end

        -- Fork point to working tree: the branch's own commits plus uncommitted edits, nothing from base
        local diff = lines({ "git", "diff", "--name-status", "--find-renames", fork }, root)
        for _, path in ipairs(lines({ "git", "ls-files", "--others", "--exclude-standard" }, root)) do
            table.insert(diff, "?\t" .. path)
        end
        local commits = lines({ "git", "log", "--no-merges", "--format=%h  %s", fork .. "..HEAD" }, root)
        local files = {}
        local display = { " BRANCH  " .. branch, " BASE    " .. base .. " @ " .. fork:sub(1, 7), "" }
        if #commits > 0 then
            table.insert(display, " COMMITS")
            for _, commit in ipairs(commits) do
                table.insert(display, "   " .. commit)
            end
            table.insert(display, "")
        end
        table.insert(display, " CHANGED FILES")
        for _, item in ipairs(diff) do
            local path = item:match("([^\t]+)$") or item
            table.insert(files, path)
            table.insert(display, "   " .. item)
        end
        if #files == 0 then table.insert(display, "   (no changes since base)") end

        git_sidebar.root, git_sidebar.files = root, files
        if not git_sidebar.buf or not vim.api.nvim_buf_is_valid(git_sidebar.buf) then
            git_sidebar.buf = vim.api.nvim_create_buf(false, true)
            vim.bo[git_sidebar.buf].buftype = "nofile"
            vim.bo[git_sidebar.buf].bufhidden = "wipe"
            vim.bo[git_sidebar.buf].swapfile = false
            vim.keymap.set("n", "<CR>", fuzzy_files, { buffer = git_sidebar.buf, desc = "Find branch file" })
            vim.keymap.set("n", "/", fuzzy_files, { buffer = git_sidebar.buf, desc = "Fuzzy-find branch file" })
            vim.keymap.set("n", "r", refresh, { buffer = git_sidebar.buf, desc = "Refresh branch files" })
        end
        vim.bo[git_sidebar.buf].modifiable = true
        vim.api.nvim_buf_set_lines(git_sidebar.buf, 0, -1, false, display)
        vim.bo[git_sidebar.buf].modifiable = false
        vim.bo[git_sidebar.buf].filetype = "git"
        if not git_sidebar.win or not vim.api.nvim_win_is_valid(git_sidebar.win) then
            git_sidebar.source_win = vim.api.nvim_get_current_win()
            vim.cmd("botright 38vnew")
            git_sidebar.win = vim.api.nvim_get_current_win()
            vim.api.nvim_win_set_buf(git_sidebar.win, git_sidebar.buf)
            vim.wo[git_sidebar.win].number = false
            vim.wo[git_sidebar.win].relativenumber = false
            vim.wo[git_sidebar.win].winfixwidth = true
        end
    end

    vim.keymap.set("n", "<leader>gf", function()
        if git_sidebar.win and vim.api.nvim_win_is_valid(git_sidebar.win) then
            vim.api.nvim_win_close(git_sidebar.win, true)
            git_sidebar.win = nil
        else
            refresh()
        end
    end, { desc = "Toggle branch files" })
    vim.api.nvim_create_autocmd({ "FocusGained", "BufWritePost" }, { callback = function()
        if git_sidebar.win and vim.api.nvim_win_is_valid(git_sidebar.win) then refresh() end
    end })
end

vim.keymap.set("n", "<leader>z", function()
    local restore = vim.t.zoom_restore
    if restore then
        vim.t.zoom_restore = nil
        vim.cmd(restore)
        return
    end
    vim.t.zoom_restore = vim.fn.winrestcmd()
    vim.cmd("wincmd |")
    vim.cmd("wincmd _")
end, { desc = "Toggle zoom on the current split" })

-- Prettier from the project's own install, with the project's config: on save, and on <leader>cf
local prettier_filetypes = {
    javascript = true, javascriptreact = true, typescript = true, typescriptreact = true,
    json = true, jsonc = true, css = true, scss = true, html = true, markdown = true, yaml = true,
}

local function project_prettier(file)
    local dir = vim.fs.dirname(file)
    while dir do
        local bin = dir .. "/node_modules/.bin/prettier"
        if vim.uv.fs_stat(bin) then
            return bin
        end
        local parent = vim.fs.dirname(dir)
        dir = parent ~= dir and parent or nil
    end
end

local function prettier_format(bufnr)
    local file = vim.api.nvim_buf_get_name(bufnr)
    local prettier = file ~= "" and prettier_filetypes[vim.bo[bufnr].filetype] and project_prettier(file)
    if not prettier then
        return
    end
    local input = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") .. "\n"
    local result = vim.system({ prettier, "--stdin-filepath", file }, { stdin = input, text = true }):wait()
    -- A file prettier cannot parse is saved unformatted; the parse error already shows as a diagnostic.
    if result.code ~= 0 then
        return
    end
    if result.stdout == input then
        return
    end
    local view = vim.fn.winsaveview()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(result.stdout, "\n", { trimempty = false }))
    if vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1] == "" then
        vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, {})
    end
    vim.fn.winrestview(view)
end

vim.api.nvim_create_autocmd("BufWritePre", {
    callback = function(args)
        prettier_format(args.buf)
    end,
})
vim.keymap.set("n", "<leader>cf", function()
    prettier_format(0)
end, { desc = "Format with Prettier" })

-- The TypeScript server's own formatter ignores .prettierrc, so it never formats
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and (client.name == "ts_ls" or client.name == "tsc_lsp") then
            client.server_capabilities.documentFormattingProvider = false
            client.server_capabilities.documentRangeFormattingProvider = false
        end
    end,
})
