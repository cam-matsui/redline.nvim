---Side-by-side renderer: a dedicated tabpage with a file panel and two
---read-only scratch buffers in native diff mode (LEFT = base, RIGHT = head).
---
---The two diff buffers persist across file switches — only their lines,
---name, and filetype change — so window layout, diffthis state, and
---buffer-local keymaps are set up exactly once per session.

local config = require('redline.config')

local M = {}

local ns = vim.api.nvim_create_namespace('redline.render')
local augroup = vim.api.nvim_create_augroup('redline.render', { clear = false })

---@param side 'LEFT'|'RIGHT'
local function make_diff_buf(side)
    local buf = vim.api.nvim_create_buf(false, true) -- unlisted scratch
    vim.b[buf].redline_side = side
    vim.bo[buf].modifiable = false
    pcall(vim.api.nvim_buf_set_name, buf, 'redline://' .. side)
    require('redline.command').apply_diff_keymaps(buf)
    return buf
end

---@param session redline.Session
function M.open(session)
    local opts = config.get()

    vim.cmd.tabnew()
    local left_win = vim.api.nvim_get_current_win()
    vim.cmd('rightbelow vertical split')
    local right_win = vim.api.nvim_get_current_win()
    local panel_pos = opts.panel.position == 'right' and 'botright' or 'topleft'
    vim.cmd(('%s %dvsplit'):format(panel_pos, opts.panel.width))
    local panel_win = vim.api.nvim_get_current_win()

    local layout = {
        tabpage = vim.api.nvim_get_current_tabpage(),
        panel_win = panel_win,
        left_win = left_win,
        right_win = right_win,
        left_buf = make_diff_buf('LEFT'),
        right_buf = make_diff_buf('RIGHT'),
        panel_buf = vim.api.nvim_create_buf(false, true),
    }
    session.layout = layout

    vim.api.nvim_win_set_buf(left_win, layout.left_buf)
    vim.api.nvim_win_set_buf(right_win, layout.right_buf)
    vim.api.nvim_win_set_buf(panel_win, layout.panel_buf)
    vim.wo[panel_win].winfixwidth = true

    for _, win in ipairs({ left_win, right_win }) do
        vim.api.nvim_win_call(win, function()
            vim.cmd.diffthis()
        end)
    end

    require('redline.ui.panel').setup(session)

    -- Closing any layout window ends the review; guarded against re-entry by
    -- session.stop() clearing M.current first.
    for _, win in ipairs({ panel_win, left_win, right_win }) do
        vim.api.nvim_create_autocmd('WinClosed', {
            group = augroup,
            pattern = tostring(win),
            once = true,
            callback = vim.schedule_wrap(function()
                require('redline.session').stop()
            end),
        })
    end

    -- Agent-review loop: when Neovim regains focus, re-read the working tree so
    -- the diff and comment anchors track edits an agent made while we were away.
    -- Only when this review tab is the active one, so background focus events
    -- (or another tab's work) don't churn the session.
    if opts.auto_refresh then
        vim.api.nvim_create_autocmd('FocusGained', {
            group = augroup,
            callback = function()
                local current = require('redline.session').current
                if current == session and layout.tabpage == vim.api.nvim_get_current_tabpage() then
                    require('redline.session').refresh()
                end
            end,
        })
    end
end

---@param buf integer
---@param lines string[]|nil
---@param placeholder string|nil virt line shown when there is no content
local function set_content(buf, lines, placeholder)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    if not lines and placeholder then
        vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
            virt_text = { { placeholder, 'Comment' } },
            virt_text_pos = 'overlay',
        })
    end
end

---@param session redline.Session
---@param entry redline.FileEntry
---@param base string[]|nil
---@param head string[]|nil
function M.show_file(session, entry, base, head)
    local layout = session.layout
    if not (layout.left_buf and vim.api.nvim_buf_is_valid(layout.left_buf)) then
        return
    end

    local left_placeholder = entry.binary and '[binary file]' or '[new file]'
    local right_placeholder = entry.binary and '[binary file]' or '[deleted]'
    set_content(layout.left_buf, base, left_placeholder)
    set_content(layout.right_buf, head, right_placeholder)

    local ft = vim.filetype.match({ filename = entry.path }) or ''
    for _, buf in ipairs({ layout.left_buf, layout.right_buf }) do
        local side = vim.b[buf].redline_side
        vim.b[buf].redline_path = entry.path
        pcall(vim.api.nvim_buf_set_name, buf, ('redline://%s/%s'):format(side, entry.path))
        if vim.bo[buf].filetype ~= ft then
            vim.bo[buf].filetype = ft
        end
    end

    for _, win in ipairs({ layout.left_win, layout.right_win }) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_cursor(win, { 1, 0 })
        end
    end
    vim.cmd.diffupdate()
    if vim.api.nvim_win_is_valid(layout.right_win) then
        vim.api.nvim_set_current_win(layout.right_win)
    end
end

---@param session redline.Session
function M.close(session)
    local layout = session.layout
    -- Autocmds first, so tearing down windows doesn't re-trigger stop().
    vim.api.nvim_clear_autocmds({ group = augroup })
    for _, win in ipairs({ layout.panel_win, layout.left_win, layout.right_win }) do
        if win and vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
    for _, buf in ipairs({ layout.panel_buf, layout.left_buf, layout.right_buf }) do
        if buf and vim.api.nvim_buf_is_valid(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
end

---@param session redline.Session
---@param side 'LEFT'|'RIGHT'
---@return integer
function M.target_buf(session, side)
    return side == 'LEFT' and session.layout.left_buf or session.layout.right_buf
end

return M
