---Inline comment display: a sign-column marker on commented lines plus each
---comment thread rendered as one connected, bordered card in virt_lines
---beneath its anchor. Comments on the same location (an original comment and
---its replies) are grouped into a single thread, ordered oldest-first to
---mirror GitHub — the newest reply sits at the bottom. Redrawn from session
---state on every session.redraw().

local config = require('redline.config')
local util = require('redline.ui.util')

local M = {}

local ns = vim.api.nvim_create_namespace('redline.threads')

---When true only the sign markers are shown (:Review toggle-threads).
M.collapsed = false

vim.api.nvim_set_hl(0, 'RedlineSign', { link = 'DiagnosticSignInfo', default = true })
vim.api.nvim_set_hl(0, 'RedlineSignDraft', { link = 'DiagnosticSignHint', default = true })
vim.api.nvim_set_hl(0, 'RedlineCommentRange', { link = 'CursorLine', default = true })
-- Card pieces.
vim.api.nvim_set_hl(0, 'RedlineCardBorder', { link = 'FloatBorder', default = true })
vim.api.nvim_set_hl(0, 'RedlineCardBody', { link = 'NormalFloat', default = true })
vim.api.nvim_set_hl(0, 'RedlineCardAuthor', { link = 'Title', default = true })
vim.api.nvim_set_hl(0, 'RedlineCardBadge', { link = 'Special', default = true })
vim.api.nvim_set_hl(0, 'RedlineCardReply', { link = 'Function', default = true })
vim.api.nvim_set_hl(0, 'RedlineCardMeta', { link = 'Comment', default = true })
vim.api.nvim_set_hl(0, 'RedlineCardSuggest', { link = 'DiffAdd', default = true })
vim.api.nvim_set_hl(0, 'RedlineCardOutdated', { link = 'DiagnosticVirtualTextWarn', default = true })

function M.toggle()
    M.collapsed = not M.collapsed
    require('redline.session').redraw()
end

local MIN_W, MAX_W = 34, 74

---Absolute epoch seconds for a UTC calendar date (Howard Hinnant's
---days-from-civil algorithm). Timezone/DST independent, unlike os.time, which
---interprets its table as local time.
local function utc_epoch(y, mo, d, h, mi, s)
    y = y - (mo <= 2 and 1 or 0)
    local era = math.floor((y >= 0 and y or y - 399) / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (mo > 2 and mo - 3 or mo + 9) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468
    return days * 86400 + h * 3600 + mi * 60 + s
end

---Seconds between now and an ISO 8601 UTC timestamp (GitHub returns UTC).
---`os.time()` with no argument is already an absolute epoch, so no timezone
---conversion is involved.
---@param iso string
---@return integer|nil
local function seconds_ago(iso)
    local y, mo, d, h, mi, s = iso:match('(%d+)-(%d+)-(%d+)T(%d+):(%d+):?(%d*)')
    if not y then
        return nil
    end
    local t = utc_epoch(tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s) or 0)
    return os.time() - t
end

---Relative age like "3d" / "5h" / "2m" from an ISO 8601 UTC timestamp.
local function ago(iso)
    if type(iso) ~= 'string' then
        return nil
    end
    local diff = seconds_ago(iso)
    if not diff then
        return nil
    end
    if diff < 60 then
        return 'now'
    elseif diff < 3600 then
        return math.floor(diff / 60) .. 'm'
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. 'h'
    else
        return math.floor(diff / 86400) .. 'd'
    end
end

---Identity of the thread a comment belongs to: replies share their root's id
---so an original comment and all its replies land in one thread.
---@param c redline.Comment
---@return string
local function thread_key(c)
    if c.remote then
        return 'r' .. (c.remote.in_reply_to or c.remote.gh_id)
    elseif c.reply_to then
        return 'r' .. c.reply_to
    end
    return 'd' .. c.id
end

---Chronological order within a thread: existing (remote) comments first, in
---posted order; then local drafts in creation order. Oldest ends up on top,
---the newest reply at the bottom — matching GitHub.
---@param a redline.Comment
---@param b redline.Comment
---@return boolean
local function thread_order(a, b)
    local ar, br = a.remote ~= nil, b.remote ~= nil
    if ar ~= br then
        return ar
    end
    if ar then
        if a.remote.created_at ~= b.remote.created_at then
            return a.remote.created_at < b.remote.created_at -- ISO 8601 sorts lexically
        end
        return a.remote.gh_id < b.remote.gh_id
    end
    return a.id < b.id
end

---Trim a header chunk list (author + badges + meta) to fit inside `avail`
---display cells: drop trailing chunks first, then truncate the name.
---@param header table[] { {text, hl}, ... }; header[1] is the author/name
---@param avail integer
local function fit_header(header, avail)
    local function width()
        local w = 0
        for _, chunk in ipairs(header) do
            w = w + vim.fn.strdisplaywidth(chunk[1])
        end
        return w
    end
    while #header > 1 and width() > avail do
        table.remove(header)
    end
    if width() > avail then
        header[1][1] = util.truncate(header[1][1], avail)
    end
end

---Header/divider chunks for one comment in a thread (without border pieces).
---@param c redline.Comment
---@param is_root boolean first (oldest) comment in the thread
---@return table[] chunks
local function comment_header(c, is_root)
    local header = {}
    if not is_root then
        table.insert(header, { '↳ ', 'RedlineCardReply' })
    end
    if c.remote then
        table.insert(header, { '@' .. c.remote.author, 'RedlineCardAuthor' })
    else
        table.insert(header, { 'you', 'RedlineCardAuthor' })
        table.insert(header, { ' (draft)', 'RedlineCardBadge' })
    end
    if c.kind == 'suggestion' then
        table.insert(header, { ' · suggestion', 'RedlineCardBadge' })
    end
    if c.state == 'outdated' then
        table.insert(header, { ' · outdated', 'RedlineCardOutdated' })
    end
    if is_root then
        local loc = c.start_line and ('L%d-%d'):format(c.start_line, c.line) or ('L%d'):format(c.line)
        table.insert(header, { ' · ' .. loc, 'RedlineCardMeta' })
    end
    if c.remote and ago(c.remote.created_at) then
        table.insert(header, { ' · ' .. ago(c.remote.created_at), 'RedlineCardMeta' })
    end
    return header
end

---Build the virt_lines for a whole thread as one connected card. `comments`
---is oldest-first; each after the first is drawn as a `├─ ↳ … ┤` divider so
---the box reads as a single thread.
---@param comments redline.Comment[]
---@param width integer total card width in cells
---@return string[][][] virt_lines
local function thread_card(comments, width)
    local border = 'RedlineCardBorder'
    local inner = width - 4 -- "│ " + " │"
    local lines = {}

    for i, c in ipairs(comments) do
        local is_root = i == 1
        local header = comment_header(c, is_root)
        fit_header(header, width - 6) -- "╭─ " + " " + at least one "─" + corner

        local fill = math.max(1, width - 4 - (function()
            local w = 0
            for _, chunk in ipairs(header) do
                w = w + vim.fn.strdisplaywidth(chunk[1])
            end
            return w
        end)())
        local corner_l = is_root and '╭─ ' or '├─ '
        local corner_r = is_root and '╮' or '┤'
        local top = { { corner_l, border } }
        vim.list_extend(top, header)
        table.insert(top, { ' ' .. ('─'):rep(fill) .. corner_r, border })
        table.insert(lines, top)

        -- Body: prose is word-wrapped; ```suggestion (or any fenced) lines are
        -- preserved verbatim so indentation survives, highlighted like a diff.
        for _, wl in ipairs(util.wrap_markdown(c.body, inner)) do
            local body_hl = 'RedlineCardBody'
            if wl.kind == 'fence' then
                body_hl = 'RedlineCardMeta'
            elseif wl.kind == 'code' then
                body_hl = 'RedlineCardSuggest'
            end
            table.insert(lines, {
                { '│ ', border },
                { util.pad(wl.text, inner), body_hl },
                { ' │', border },
            })
        end
    end

    table.insert(lines, { { '╰' .. ('─'):rep(width - 2) .. '╯', border } })
    return lines
end

---@param session redline.Session
function M.decorate(session)
    local entry = session.files[session.file_index]
    local layout = session.layout
    if not entry or not (layout.left_buf and vim.api.nvim_buf_is_valid(layout.left_buf)) then
        return
    end

    local bufs = { LEFT = layout.left_buf, RIGHT = layout.right_buf }
    local wins = { LEFT = layout.left_win, RIGHT = layout.right_win }
    for _, buf in pairs(bufs) do
        vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end

    -- Group this file's comments into threads, preserving first-seen order for
    -- stable placement when several threads share a line.
    local threads, order = {}, {}
    for _, c in ipairs(session.comments) do
        if c.path == entry.path then
            local key = c.side .. '\0' .. thread_key(c)
            local t = threads[key]
            if not t then
                t = { side = c.side, list = {} }
                threads[key] = t
                table.insert(order, key)
            end
            table.insert(t.list, c)
        end
    end

    local sign = config.get().signs.comment
    for _, key in ipairs(order) do
        local t = threads[key]
        table.sort(t.list, thread_order)
        local buf = bufs[t.side]
        local win = wins[t.side]
        local last = vim.api.nvim_buf_line_count(buf)

        -- Sign + subtle line highlight over every line any comment covers, so
        -- a block comment's extent is visible.
        for _, c in ipairs(t.list) do
            local sign_hl = c.remote and 'RedlineSign' or 'RedlineSignDraft'
            for l = math.min(c.start_line or c.line, last), math.min(c.line, last) do
                vim.api.nvim_buf_set_extmark(buf, ns, l - 1, 0, {
                    sign_text = sign,
                    sign_hl_group = sign_hl,
                    line_hl_group = 'RedlineCommentRange',
                })
            end
        end

        if not M.collapsed then
            -- Anchor the whole thread beneath the root (oldest) comment's line.
            local anchor = math.min(t.list[1].line, last) - 1
            local win_w = (win and vim.api.nvim_win_is_valid(win)) and vim.api.nvim_win_get_width(win) or 80
            local width = math.max(MIN_W, math.min(MAX_W, win_w - 2))
            vim.api.nvim_buf_set_extmark(buf, ns, anchor, 0, {
                virt_lines = thread_card(t.list, width),
            })
        end
    end
end

---Number of virtual lines currently rendered for the thread anchored at
---`line` in `buf` (0 when threads are collapsed or none exist). Used to open a
---reply input below the whole thread rather than mid-thread.
---@param buf integer
---@param line integer 1-based
---@return integer
function M.thread_height(buf, line)
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        return 0
    end
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { line - 1, 0 }, { line - 1, -1 }, { details = true })
    local h = 0
    for _, m in ipairs(marks) do
        if m[4].virt_lines then
            h = h + #m[4].virt_lines
        end
    end
    return h
end

-- Exposed for tests.
M._thread_key = thread_key
M._thread_order = thread_order

return M
