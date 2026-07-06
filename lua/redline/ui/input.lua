---Comment input: a small floating window holding a real markdown scratch
---buffer, so multi-line bodies, undo, and text objects all behave normally.
---
---Confirm with <C-s> (insert or normal) or <CR> in normal mode; cancel with
---q or <Esc><Esc> in normal mode. A single <Esc> only leaves insert mode, so
---a stray press never discards the comment. Closing the window any other way
---also cancels.

local M = {}

---@class redline.InputAnchor
---@field win integer window the buffer position is in
---@field line integer 1-based buffer line to anchor below
---@field below integer extra screen rows to drop (e.g. a thread's height), so
---       the float opens beneath any virtual lines under `line`

---@class redline.InputOpts
---@field title string window title
---@field initial string[]|nil prefilled lines (e.g. a ```suggestion fence)
---@field cursor { [1]: integer, [2]: integer }|nil initial cursor position
---@field anchor redline.InputAnchor|nil open below a specific line + its virt_lines instead of the cursor
---@field on_confirm fun(lines: string[])

---@param opts redline.InputOpts
function M.open(opts)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'markdown'
    if opts.initial then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.initial)
    end

    local height = math.max(#(opts.initial or {}) + 2, 5)
    -- Default: just below the cursor. With an anchor (e.g. a reply), open
    -- below the anchored line *and* the virtual lines rendered under it, so
    -- the box lands beneath the whole thread rather than mid-thread.
    local win_config = {
        relative = 'cursor',
        row = 1,
        col = 0,
        width = math.min(80, math.max(40, vim.o.columns - 20)),
        height = math.min(height, 20),
        style = 'minimal',
        border = 'rounded',
        title = opts.title,
        title_pos = 'left',
    }
    if opts.anchor then
        win_config.relative = 'win'
        win_config.win = opts.anchor.win
        win_config.bufpos = { opts.anchor.line - 1, 0 }
        win_config.row = opts.anchor.below + 1
    end
    local win = vim.api.nvim_open_win(buf, true, win_config)
    vim.wo[win].wrap = true

    local confirmed = false
    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    local function confirm()
        if confirmed then
            return
        end
        confirmed = true
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        close()
        opts.on_confirm(lines)
    end

    local map_opts = { buffer = buf, nowait = true }
    vim.keymap.set({ 'n', 'i' }, '<C-s>', confirm, map_opts)
    vim.keymap.set('n', '<CR>', confirm, map_opts)
    vim.keymap.set('n', 'q', close, map_opts)
    -- Double <Esc> to cancel: a single <Esc> in insert mode just returns to
    -- normal mode, so it can't accidentally throw the comment away.
    vim.keymap.set('n', '<Esc><Esc>', close, map_opts)

    -- Wipe the buffer whenever the window goes away (confirm, cancel, :q).
    vim.api.nvim_create_autocmd('WinClosed', {
        pattern = tostring(win),
        once = true,
        callback = function()
            vim.schedule(function()
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_delete(buf, { force = true })
                end
            end)
        end,
    })

    if opts.cursor then
        pcall(vim.api.nvim_win_set_cursor, win, opts.cursor)
    elseif not opts.initial then
        vim.cmd.startinsert()
    end
end

return M
