local M = {}

local state = { win = nil, buf = nil, root = nil, files = {}, timer = nil, pr = nil }

local function lines(cmd, cwd)
    local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then return {} end
    return vim.split(vim.trim(result.stdout or ""), "\n", { trimempty = true })
end

local function gh_pr(root)
    if vim.fn.executable("gh") ~= 1 then return nil end
    local result = vim.system({ "gh", "pr", "view", "--json", "baseRefName,commits" }, {
        cwd = root,
        text = true,
    }):wait()
    if result.code ~= 0 or not result.stdout or result.stdout == "" then return nil end
    local ok, value = pcall(vim.json.decode, result.stdout)
    return ok and value or nil
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
end

local function open_file(path)
    vim.cmd("edit " .. vim.fn.fnameescape(state.root .. "/" .. path))
end

local function fuzzy_files()
    if #state.files == 0 then return end
    require("telescope.pickers").new({}, {
        prompt_title = "Branch files",
        finder = require("telescope.finders").new_table({ results = state.files }),
        sorter = require("telescope.config").values.generic_sorter({}),
        previewer = require("telescope.previewers").vim_buffer_cat.new({}),
        attach_mappings = function(prompt_bufnr, map)
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")
            local function select()
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then open_file(entry[1] or entry.value) end
            end
            map("i", "<CR>", select)
            map("n", "<CR>", select)
            return true
        end,
    }):find()
end

function M.refresh()
    local file = vim.fn.expand("%:p")
    local root = vim.fs.root(file ~= "" and file or vim.fn.getcwd(), { ".git" })
    if not root then return end

    if state.root ~= root then state.pr = gh_pr(root) end
    local pr = state.pr
    local base = branch_base(root, pr)
    if not base then return end
    local committed = lines({ "git", "diff", "--name-status", base .. "...HEAD" }, root)
    local working = lines({ "git", "diff", "--name-status", "HEAD" }, root)
    vim.list_extend(working, lines({ "git", "diff", "--name-status", "--cached" }, root))
    local untracked = lines({ "git", "ls-files", "--others", "--exclude-standard" }, root)
    local seen, diff = {}, {}
    for _, item in ipairs(committed) do
        local path = item:match("^%S+%s+(.+)$") or item
        seen[path] = true
        table.insert(diff, item)
    end
    for _, item in ipairs(working) do
        local path = item:match("^%S+%s+(.+)$") or item
        if not seen[path] then seen[path] = true; table.insert(diff, item) end
    end
    for _, path in ipairs(untracked) do
        if not seen[path] then seen[path] = true; table.insert(diff, "?? " .. path) end
    end
    local files, display = {}, {
        " BRANCH  " .. (lines({ "git", "branch", "--show-current" }, root)[1] or "HEAD"),
        " BASE    " .. base,
        "",
    }

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

    state.root, state.files = root, files
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
        state.buf = vim.api.nvim_create_buf(false, true)
        vim.bo[state.buf].buftype = "nofile"
        vim.bo[state.buf].bufhidden = "wipe"
        vim.bo[state.buf].swapfile = false
        vim.keymap.set("n", "<CR>", fuzzy_files, { buffer = state.buf, desc = "Find branch file" })
        vim.keymap.set("n", "/", fuzzy_files, { buffer = state.buf, desc = "Fuzzy-find branch file" })
        vim.keymap.set("n", "r", M.refresh, { buffer = state.buf, desc = "Refresh branch files" })
    end
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, display)
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].filetype = "git"

    if not state.win or not vim.api.nvim_win_is_valid(state.win) then
        vim.cmd("botright 38vnew")
        state.win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(state.win, state.buf)
        vim.wo[state.win].number = false
        vim.wo[state.win].relativenumber = false
        vim.wo[state.win].winfixwidth = true
    end
end

function M.refresh_debounced()
    if state.timer then state.timer:stop(); state.timer:close() end
    state.timer = vim.defer_fn(function()
        state.timer = nil
        if state.win and vim.api.nvim_win_is_valid(state.win) then M.refresh() end
    end, 150)
end

function M.toggle()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, true)
        state.win = nil
    else
        M.refresh()
    end
end

function M.setup()
    vim.keymap.set("n", "<leader>gf", M.toggle, { desc = "Toggle branch files" })
    vim.api.nvim_create_autocmd({ "FocusGained", "BufWritePost", "FileChangedShellPost" }, {
        callback = M.refresh_debounced,
        desc = "Refresh Git branch sidebar",
    })
end

return M
