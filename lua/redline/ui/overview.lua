---PR overview: a standard GitHub-style summary of the current PR — state,
---description, CI checks, commit history, and the conversation (top-level,
---non-inline comments) — rendered in a scrollable float. Read-only; `q` or
---`<Esc>` closes it and returns to the diff.

local gh = require('redline.gh')
local util = require('redline.ui.util')

local M = {}

local ns = vim.api.nvim_create_namespace('redline.overview')

local hl = {
    title = 'RedlineOvTitle',
    section = 'RedlineOvSection',
    meta = 'RedlineOvMeta',
    hash = 'RedlineOvHash',
    author = 'RedlineOvAuthor',
    pass = 'RedlineOvPass',
    fail = 'RedlineOvFail',
    pending = 'RedlineOvPending',
    neutral = 'RedlineOvNeutral',
}

local function set_hl(name, link)
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
end
set_hl(hl.title, 'Title')
set_hl(hl.section, 'Function')
set_hl(hl.meta, 'Comment')
set_hl(hl.hash, 'Identifier')
set_hl(hl.author, 'Special')
set_hl(hl.pass, 'DiagnosticOk')
set_hl(hl.fail, 'DiagnosticError')
set_hl(hl.pending, 'DiagnosticWarn')
set_hl(hl.neutral, 'Comment')

local WIDTH = 84

---A tiny line/highlight accumulator so rendering reads top-to-bottom.
local function builder()
    local b = { lines = {}, marks = {} }
    ---Append a line; `spans` = { { col_start, col_end, hl }, ... } (col_end -1 = EOL).
    function b.add(text, spans)
        table.insert(b.lines, text or '')
        local row = #b.lines - 1
        for _, s in ipairs(spans or {}) do
            table.insert(b.marks, { row, s[1], s[2], s[3] })
        end
        return row
    end
    ---Whole-line highlight convenience.
    function b.line(text, group)
        return b.add(text, group and { { 0, -1, group } } or nil)
    end
    return b
end

---Word-wrap markdown `text` to `width`, keeping fenced code blocks verbatim.
---@return string[]
local function wrap(text, width)
    return vim.tbl_map(function(wl)
        return wl.text
    end, util.wrap_markdown(text, width))
end

---@param title string
---@param width integer
local function section(b, title, width)
    b.line('')
    local bar = ('── %s '):format(title)
    bar = bar .. ('─'):rep(math.max(0, width - vim.fn.strdisplaywidth(bar)))
    b.line(bar, hl.section)
    b.line('')
end

---Glyph + highlight for a check-run conclusion/state.
---@return string glyph, string highlight
local function check_style(status, conclusion)
    local c = (conclusion or ''):upper()
    local s = (status or ''):upper()
    if c == 'SUCCESS' then
        return '✓', hl.pass
    elseif
        c == 'FAILURE'
        or c == 'ERROR'
        or c == 'TIMED_OUT'
        or c == 'CANCELLED'
        or c == 'ACTION_REQUIRED'
        or c == 'STARTUP_FAILURE'
    then
        return '✗', hl.fail
    elseif c == 'SKIPPED' or c == 'NEUTRAL' then
        return '○', hl.neutral
    elseif s == 'COMPLETED' then
        return '✓', hl.pass -- completed with an unknown-but-not-failing conclusion
    else
        return '●', hl.pending -- QUEUED / IN_PROGRESS / PENDING
    end
end

---Short human date from an ISO timestamp (YYYY-MM-DD).
local function short_date(iso)
    return type(iso) == 'string' and iso:sub(1, 10) or ''
end

---@param pr table gh pr view JSON (see gh.pr_overview)
---@param width integer|nil content width in cells (defaults to WIDTH)
---@return string[] lines, table[] marks
local function render(pr, width)
    local W = width or WIDTH
    local b = builder()

    -- Header: "#N  Title" with a state badge.
    local head = util.truncate(('#%d  %s'):format(pr.number, pr.title or ''), W - 8)
    local badge = pr.isDraft and 'DRAFT' or (pr.state or ''):upper()
    local badge_hl = pr.isDraft and hl.neutral
        or (pr.state == 'OPEN' and hl.pass)
        or (pr.state == 'MERGED' and hl.author)
        or hl.fail
    local pad = math.max(1, W - vim.fn.strdisplaywidth(head) - #badge)
    b.add(head .. (' '):rep(pad) .. badge, {
        { 0, #head, hl.title },
        { #head + pad, -1, badge_hl },
    })

    local author = pr.author and pr.author.login or '?'
    b.line(('@%s wants to merge %s → %s'):format(author, pr.headRefName or '?', pr.baseRefName or '?'), hl.meta)
    b.line(pr.url or '', hl.meta)

    -- Status line: review decision, mergeability, diffstat.
    local bits = {}
    local decision = pr.reviewDecision
    if decision and decision ~= '' then
        table.insert(bits, (decision:gsub('_', ' ')))
    end
    if pr.mergeable and pr.mergeable ~= 'UNKNOWN' then
        table.insert(bits, pr.mergeable == 'MERGEABLE' and 'mergeable' or 'conflicts')
    end
    table.insert(
        bits,
        ('+%d −%d in %d file%s'):format(
            pr.additions or 0,
            pr.deletions or 0,
            pr.changedFiles or 0,
            (pr.changedFiles == 1) and '' or 's'
        )
    )
    b.line('')
    b.line(table.concat(bits, '   ·   '), hl.meta)

    -- Description.
    section(b, 'Description', W)
    local body = vim.trim(pr.body or '')
    if body == '' then
        b.line('(no description)', hl.meta)
    else
        for _, l in ipairs(wrap(body, W)) do
            b.line(l)
        end
    end

    -- Checks.
    local checks = pr.statusCheckRollup or {}
    if #checks > 0 then
        section(b, ('Checks (%d)'):format(#checks), W)
        for _, c in ipairs(checks) do
            local glyph, ghl = check_style(c.status, c.conclusion or c.state)
            local name = c.name or c.context or c.workflowName or '(check)'
            if c.workflowName and c.name and c.workflowName ~= c.name then
                name = c.workflowName .. ' / ' .. c.name
            end
            b.add((' %s %s'):format(glyph, util.truncate(name, W - 3)), { { 0, 3, ghl } })
        end
    end

    -- Commits.
    local commits = pr.commits or {}
    section(b, ('Commits (%d)'):format(#commits), W)
    for _, c in ipairs(commits) do
        local sha = (c.oid or ''):sub(1, 8)
        local who = ''
        if c.authors and c.authors[1] then
            who = '@' .. (c.authors[1].login or c.authors[1].name or '?')
        end
        local who_w = vim.fn.strdisplaywidth(who)
        -- Truncate the message so the sha + right-aligned author always fit.
        local msg = util.truncate(c.messageHeadline or '', W - 4 - #sha - who_w - 1)
        local left = (' %s  %s'):format(sha, msg)
        local avail = W - vim.fn.strdisplaywidth(left) - who_w
        local line = avail > 0 and (left .. (' '):rep(avail) .. who) or (left .. ' ' .. who)
        b.add(line, {
            { 1, 1 + #sha, hl.hash },
            { #line - #who, -1, hl.author },
        })
    end

    -- Conversation (top-level issue comments, not inline review comments).
    local comments = pr.comments or {}
    section(b, ('Conversation (%d)'):format(#comments), W)
    if #comments == 0 then
        b.line('(no conversation comments)', hl.meta)
    else
        for i, c in ipairs(comments) do
            local who = c.author and c.author.login or '?'
            b.line(('@%s · %s'):format(who, short_date(c.createdAt)), hl.author)
            for _, l in ipairs(wrap(vim.trim(c.body or ''), W - 2)) do
                b.line('  ' .. l)
            end
            if i < #comments then
                b.line('')
            end
        end
    end

    return b.lines, b.marks
end

---Open the overview float for the given PR JSON.
---@param pr table
local function show(pr)
    -- Size content to the actual float width so nothing is clipped on narrow
    -- terminals (the window has no horizontal scroll).
    local content_w = math.max(40, math.min(WIDTH, vim.o.columns - 8))
    local lines, marks = render(pr, content_w)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, m in ipairs(marks) do
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1], m[2], {
            end_col = m[3] == -1 and nil or m[3],
            end_row = m[3] == -1 and m[1] + 1 or nil,
            hl_group = m[4],
        })
    end
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = 'redline-overview'

    local width = content_w + 4
    local height = math.min(#lines + 1, math.floor(vim.o.lines * 0.85))
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        row = math.floor((vim.o.lines - height) / 2 - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = 'minimal',
        border = 'rounded',
        title = ' PR overview ',
        title_pos = 'center',
    })
    -- Structured lines are pre-truncated to the content width; only free-form
    -- lines (merge summary, URL) can exceed it, so wrap keeps them visible
    -- rather than clipping at the (non-scrolling) window edge.
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].cursorline = true

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end
    for _, key in ipairs({ 'q', '<Esc>' }) do
        vim.keymap.set('n', key, close, { buffer = buf, nowait = true })
    end
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
end

---Fetch and display the overview for the active PR review session.
function M.open()
    local session = require('redline.session').current
    if not session or not session.pr then
        vim.notify('redline: PR overview is only available during a PR review', vim.log.levels.WARN)
        return
    end
    local pr = session.pr
    gh.pr_overview(tostring(pr.number), session.root, function(data)
        if not data then
            return -- gh.json already reported the error
        end
        if require('redline.session').current ~= session then
            return -- session changed while loading
        end
        show(data)
    end)
end

-- Exposed for tests.
M._render = render

return M
