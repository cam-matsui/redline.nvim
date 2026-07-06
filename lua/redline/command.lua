---:Review subcommand dispatch, completion, <Plug> mappings, and the
---buffer-local default keymaps applied to review buffers.

local M = {}

---Start a local (git) review.
---@param kind 'worktree'|'branch'
---@param ref string|nil base ref for branch reviews
local function start_local(kind, ref)
    require('redline.git').root(function(root)
        if not root then
            return -- git already reported the error (not a repo)
        end
        local function begin(src)
            if src then
                require('redline.session').start(src, root)
            end
        end
        if kind == 'worktree' then
            require('redline.source.worktree').create(root, begin)
        else
            require('redline.source.branch').create(ref, root, begin)
        end
    end)
end

---Require an active session, or explain how to start one.
---@return redline.Session|nil
local function need_session()
    local session = require('redline.session').current
    if not session then
        vim.notify('redline: no active review (start one with :Review)', vim.log.levels.WARN)
    end
    return session
end

---Open the real file behind the RIGHT diff buffer at the cursor line.
local function open_real_file()
    local session = need_session()
    if not session then
        return
    end
    local path = vim.b.redline_path
    if not path then
        vim.notify('redline: not in a review diff buffer', vim.log.levels.WARN)
        return
    end
    if not session.root then
        vim.notify('redline: no local clone of this PR to open files from', vim.log.levels.WARN)
        return
    end
    local entry = session.files[session.file_index]
    if entry and entry.status == 'D' then
        vim.notify('redline: file was deleted', vim.log.levels.WARN)
        return
    end
    local line = vim.api.nvim_win_get_cursor(0)[1]
    vim.cmd('tab drop ' .. vim.fn.fnameescape(session.root .. '/' .. path))
    pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
end

---@type table<string, fun(cmd: table)>
local subcommands = {
    branch = function(cmd)
        start_local('branch', cmd.fargs[2])
    end,
    pr = function(cmd)
        require('redline.source.pr').start(cmd.fargs[2])
    end,
    requests = function()
        require('redline.source.pr').requests()
    end,
    comment = function(cmd)
        local comments = require('redline.comments')
        if cmd.range > 0 then
            comments.add(cmd.line1, cmd.line2)
        else
            comments.add()
        end
    end,
    suggest = function(cmd)
        if cmd.range == 0 then
            vim.notify('redline: select the lines to suggest a change for', vim.log.levels.WARN)
            return
        end
        require('redline.comments').suggest(cmd.line1, cmd.line2)
    end,
    edit = function()
        require('redline.comments').edit_at_cursor()
    end,
    delete = function()
        require('redline.comments').delete_at_cursor()
    end,
    reply = function()
        require('redline.comments').reply_at_cursor()
    end,
    next = function()
        require('redline.comments').jump(1)
    end,
    prev = function()
        require('redline.comments').jump(-1)
    end,
    list = function()
        require('redline.comments').pick()
    end,
    export = function(cmd)
        require('redline.export').export(cmd.fargs[2])
    end,
    submit = function()
        require('redline.gh').submit_review()
    end,
    refresh = function()
        require('redline.session').refresh()
    end,
    files = function()
        local session = need_session()
        if session and vim.api.nvim_win_is_valid(session.layout.panel_win) then
            vim.api.nvim_set_current_win(session.layout.panel_win)
        end
    end,
    overview = function()
        require('redline.ui.overview').open()
    end,
    ['toggle-threads'] = function()
        require('redline.ui.threads').toggle()
    end,
    mine = function()
        require('redline.session').set_filter_owned(nil)
    end,
    close = function()
        require('redline.session').stop()
    end,
}

---@param cmd table nvim_create_user_command callback argument
function M.dispatch(cmd)
    local sub = cmd.fargs[1]
    if sub == nil then
        start_local('worktree')
        return
    end
    local handler = subcommands[sub]
    if not handler then
        vim.notify(('redline: unknown subcommand %q (:Review <Tab> lists them)'):format(sub), vim.log.levels.ERROR)
        return
    end
    handler(cmd)
end

---@param arglead string
---@param cmdline string
function M.complete(arglead, cmdline)
    -- Only complete the first argument (the subcommand).
    local before_cursor = cmdline:gsub('%S*$', '')
    if before_cursor:find('^%s*%S+%s+%S') then
        return {}
    end
    local names = vim.tbl_keys(subcommands)
    table.sort(names)
    return vim.tbl_filter(function(name)
        return vim.startswith(name, arglead)
    end, names)
end

---Define <Plug> mappings. Called once from plugin/redline.lua.
function M.setup_plug()
    local function plug(mode, name, rhs)
        vim.keymap.set(mode, '<Plug>(Review' .. name .. ')', rhs, { silent = true })
    end
    plug('n', 'Comment', function()
        require('redline.comments').add()
    end)
    -- Visual-mode actions leave visual mode via :<C-u> so '< and '> are set.
    plug('x', 'Comment', ":<C-u>lua require('redline.comments').add_visual()<CR>")
    plug('x', 'Suggest', ":<C-u>lua require('redline.comments').suggest_visual()<CR>")
    plug('n', 'Edit', function()
        require('redline.comments').edit_at_cursor()
    end)
    plug('n', 'Delete', function()
        require('redline.comments').delete_at_cursor()
    end)
    plug('n', 'Reply', function()
        require('redline.comments').reply_at_cursor()
    end)
    plug('n', 'NextComment', function()
        require('redline.comments').jump(1)
    end)
    plug('n', 'PrevComment', function()
        require('redline.comments').jump(-1)
    end)
    plug('n', 'NextFile', function()
        require('redline.session').next_file()
    end)
    plug('n', 'PrevFile', function()
        require('redline.session').prev_file()
    end)
    plug('n', 'OpenFile', open_real_file)
    plug('n', 'Export', function()
        require('redline.export').export()
    end)
    plug('n', 'Submit', function()
        require('redline.gh').submit_review()
    end)
    plug('n', 'Refresh', function()
        require('redline.session').refresh()
    end)
    plug('n', 'ToggleThreads', function()
        require('redline.ui.threads').toggle()
    end)
    plug('n', 'FilterOwned', function()
        require('redline.session').set_filter_owned(nil)
    end)
    plug('n', 'Overview', function()
        require('redline.ui.overview').open()
    end)
    plug('n', 'Close', function()
        require('redline.session').stop()
    end)
end

---Maps shared by every review buffer (diff sides and panel).
---@param buf integer
---@param keys redline.KeymapConfig
local function apply_common(buf, keys)
    local function map(mode, lhs, plug_name)
        if lhs and lhs ~= '' then
            vim.keymap.set(mode, lhs, '<Plug>(Review' .. plug_name .. ')', { buffer = buf, remap = true })
        end
    end
    map('n', keys.next_file, 'NextFile')
    map('n', keys.prev_file, 'PrevFile')
    map('n', keys.export, 'Export')
    map('n', keys.submit, 'Submit')
    map('n', keys.refresh, 'Refresh')
    map('n', keys.filter_owned, 'FilterOwned')
    map('n', keys.overview, 'Overview')
    map('n', keys.close, 'Close')
    return map
end

---Default keymaps for the two diff buffers.
---@param buf integer
function M.apply_diff_keymaps(buf)
    local keys = require('redline.config').get().keymaps
    if not keys.enabled then
        return
    end
    local map = apply_common(buf, keys)
    map('n', keys.comment, 'Comment')
    map('x', keys.comment, 'Comment')
    map('x', keys.suggest, 'Suggest')
    map('n', keys.edit, 'Edit')
    map('n', keys.delete, 'Delete')
    map('n', keys.reply, 'Reply')
    map('n', keys.next_comment, 'NextComment')
    map('n', keys.prev_comment, 'PrevComment')
    map('n', keys.open_file, 'OpenFile')
end

---Default keymaps for the file panel.
---@param buf integer
function M.apply_panel_keymaps(buf)
    local keys = require('redline.config').get().keymaps
    if not keys.enabled then
        return
    end
    apply_common(buf, keys)
    vim.keymap.set('n', '<CR>', function()
        local session = require('redline.session').current
        if not session then
            return
        end
        local index = require('redline.ui.panel').file_at(session, vim.api.nvim_win_get_cursor(0)[1])
        if index then
            require('redline.session').goto_file(index)
        end
    end, { buffer = buf })
end

return M
