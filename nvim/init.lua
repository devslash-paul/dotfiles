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

    -- Claude Code / Codex conversations grouped by Git worktree, below nvim-tree.
    -- The private GitHub repository is available to lazy.nvim via the configured gh auth.
    {
        url = "git@github.com:devslash-paul/agent-workspaces.nvim.git",
        name = "agent-workspaces.nvim",
        enabled = agent_workspaces_available(),
        lazy = false,
        config = function()
            require("agent-workspaces").setup()
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

    local function branch_base(root, pr)
        if pr and pr.baseRefName then return pr.baseRefName end
        local upstream = lines({ "git", "rev-parse", "--abbrev-ref", "@{upstream}" }, root)[1]
        if upstream then return upstream end
        for _, candidate in ipairs({ "main", "master", "origin/main", "origin/master" }) do
            if #lines({ "git", "rev-parse", "--verify", candidate }, root) > 0 then
                return candidate
            end
        end
        return nil
    end

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
        local pr = gh_pr(root)
        local base = branch_base(root, pr)
        if not base then vim.notify("Could not determine branch base", vim.log.levels.WARN); return end

        local diff = lines({ "git", "diff", "--name-status", base .. "...HEAD" }, root)
        local files = {}
        local display = { " BRANCH  " .. (lines({ "git", "branch", "--show-current" }, root)[1] or "HEAD"),
            " BASE    " .. base, "" }
        if pr and pr.commits and #pr.commits > 0 then
            table.insert(display, " STACK / PR COMMITS")
            for _, commit in ipairs(pr.commits) do
                table.insert(display, string.format("   %s  %s", commit.oid:sub(1, 7), commit.messageHeadline))
            end
            table.insert(display, "")
        end
        table.insert(display, " CHANGED FILES")
        for _, item in ipairs(diff) do
            local path = item:match("^%S+%s+(.+)$") or item
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
