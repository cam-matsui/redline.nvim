---File-list side panel. Rendered entirely from session state; `render()` is
---cheap and called on every redraw.

local M = {}

local ns = vim.api.nvim_create_namespace('redline.panel')

vim.api.nvim_set_hl(0, 'RedlineTitle', { link = 'Title', default = true })
vim.api.nvim_set_hl(0, 'RedlineAdd', { link = 'Added', default = true })
vim.api.nvim_set_hl(0, 'RedlineDelete', { link = 'Removed', default = true })
vim.api.nvim_set_hl(0, 'RedlineChange', { link = 'Changed', default = true })
vim.api.nvim_set_hl(0, 'RedlineComment', { link = 'DiagnosticInfo', default = true })
vim.api.nvim_set_hl(0, 'RedlinePanelMeta', { link = 'Comment', default = true })
vim.api.nvim_set_hl(0, 'RedlinePanelDir', { link = 'Comment', default = true })

local status_hl = { A = 'RedlineAdd', D = 'RedlineDelete', M = 'RedlineChange', R = 'RedlineChange' }

---One-time buffer/window options and keymaps for the panel.
---@param session redline.Session
function M.setup(session)
    local layout = session.layout
    pcall(vim.api.nvim_buf_set_name, layout.panel_buf, 'redline://panel')
    vim.bo[layout.panel_buf].modifiable = false
    vim.b[layout.panel_buf].redline_panel = true

    local wo = vim.wo[layout.panel_win]
    wo.number = false
    wo.relativenumber = false
    wo.signcolumn = 'no'
    wo.foldcolumn = '0'
    wo.cursorline = true
    wo.wrap = false
    wo.winbar = ''

    require('redline.command').apply_panel_keymaps(layout.panel_buf)
end

---Line number in the panel where the file list starts (after title, summary,
---and a blank line).
local HEADER_LINES = 3

---@param session redline.Session
---@param lnum integer 1-based cursor line in the panel
---@return integer|nil absolute index into session.files
function M.file_at(session, lnum)
    local row = lnum - HEADER_LINES
    local visible = require('redline.session').visible_indices(session)
    return visible[row]
end

---@param session redline.Session
function M.render(session)
    local buf = session.layout.panel_buf
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return
    end

    local draft_counts = {}
    for _, c in ipairs(session.comments) do
        if c.state ~= 'submitted' then
            draft_counts[c.path] = (draft_counts[c.path] or 0) + 1
        end
    end

    local visible = require('redline.session').visible_indices(session)

    -- Summary of what's shown: file count and total diffstat.
    local total_add, total_del = 0, 0
    for _, i in ipairs(visible) do
        total_add = total_add + (session.files[i].additions or 0)
        total_del = total_del + (session.files[i].deletions or 0)
    end
    local summary = (' %d file%s'):format(#visible, #visible == 1 and '' or 's')
    if session.filter_owned and session.owned then
        summary = summary .. ' owned by you'
    end
    if total_add > 0 or total_del > 0 then
        summary = summary .. ('  ·  +%d −%d'):format(total_add, total_del)
    end

    local lines = { ' ' .. session.source.title, summary, '' }
    for _, i in ipairs(visible) do
        local entry = session.files[i]
        local marker = (i == session.file_index) and '▸' or ' '
        local counts = ''
        if entry.additions > 0 or entry.deletions > 0 then
            counts = (' +%d -%d'):format(entry.additions, entry.deletions)
        end
        local comments = draft_counts[entry.path] and (' ●%d'):format(draft_counts[entry.path]) or ''
        table.insert(lines, ('%s%s %s%s%s'):format(marker, entry.status, entry.path, counts, comments))
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.hl.range(buf, ns, 'RedlineTitle', { 0, 0 }, { 0, -1 })
    vim.hl.range(buf, ns, 'RedlinePanelMeta', { 1, 0 }, { 1, -1 })
    for display, i in ipairs(visible) do
        local entry = session.files[i]
        local row = HEADER_LINES + display - 1
        local line = lines[row + 1]
        -- The current-file marker '▸' is multibyte; find the status letter's
        -- byte offset instead of assuming column 1.
        local status_col = (i == session.file_index) and #'▸' or 1
        vim.hl.range(buf, ns, status_hl[entry.status] or 'RedlineChange', { row, status_col }, { row, status_col + 1 })
        -- Dim the directory portion of the path (basename stays default fg).
        local path_start = status_col + 2 -- status letter + separating space
        local slash = entry.path:match('^.*()/')
        if slash then
            vim.hl.range(buf, ns, 'RedlinePanelDir', { row, path_start }, { row, path_start + slash })
        end
        local counts_at, counts_end = line:find(' %+%d+ %-%d+')
        if counts_at then
            local minus_at = line:find(' %-%d+', counts_at + 1)
            vim.hl.range(buf, ns, 'RedlineAdd', { row, counts_at }, { row, minus_at })
            vim.hl.range(buf, ns, 'RedlineDelete', { row, minus_at }, { row, counts_end })
        end
        local dot_at = line:find(' ●%d+$')
        if dot_at then
            vim.hl.range(buf, ns, 'RedlineComment', { row, dot_at }, { row, -1 })
        end
    end
end

return M
