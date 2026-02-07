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
        keys = {
            { "<C-p>", function() require("telescope.builtin").find_files() end, desc = "Find file" },
            { "<leader>fg", function() require("telescope.builtin").live_grep() end, desc = "Search in files" },
            { "<leader>fb", function() require("telescope.builtin").buffers() end, desc = "Open buffers" },
            { "<leader>fd", function() require("telescope.builtin").diagnostics() end, desc = "LSP diagnostics" },
            { "<leader>fs", function() require("telescope.builtin").lsp_document_symbols() end, desc = "Symbols in file" },
            { "<leader>fw", function() require("telescope.builtin").lsp_workspace_symbols() end, desc = "Symbols in project" },
        },
    },

    -- File tree
    {
        "nvim-tree/nvim-tree.lua",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            vim.g.loaded_netrw = 1
            vim.g.loaded_netrwPlugin = 1
            require("nvim-tree").setup()
        end,
        keys = {
            { "<leader>e", "<cmd>NvimTreeToggle<CR>", desc = "Toggle file tree" },
            { "<leader>f", "<cmd>NvimTreeFindFile<CR>", desc = "Reveal current file" },
        },
    },

    -- LSP
    {
        "neovim/nvim-lspconfig",
        config = function()
            require("lspconfig").rust_analyzer.setup({})
        end,
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
        vim.keymap.set("n", "gr", function()                             -- show usages
            vim.notify("Finding references...")
            vim.lsp.buf.references()
        end, opts)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)        -- go to definition
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)              -- hover docs
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)    -- rename symbol
        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts)        -- show diagnostic under cursor
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)         -- previous diagnostic
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)         -- next diagnostic
        vim.keymap.set("n", "<leader>q", ":cclose<CR>", opts)
    end,
})
