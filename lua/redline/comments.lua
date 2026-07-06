---Comment model and actions. The comment list on the session is the source
---of truth; extmarks are ephemeral view state redrawn by ui/threads.lua.
---
---Fields deliberately mirror GitHub's review-comment API (path, line, side,
---start_line, start_side, body) so a draft can be exported as markdown or
---submitted as a PR review comment without translation.

local M = {}

---@class redline.RemoteMeta
---@field gh_id integer
---@field author string
---@field in_reply_to integer|nil
---@field created_at string

---@class redline.Comment
---@field id integer session-local id
---@field path string repo-relative path → GitHub `path`
---@field line integer end (or only) line → GitHub `line`
---@field side 'LEFT'|'RIGHT' → GitHub `side`
---@field start_line integer|nil first line of a multi-line comment → GitHub `start_line`
---@field start_side 'LEFT'|'RIGHT'|nil → GitHub `start_side`
---@field body string markdown; suggestions embed a ```suggestion fence
---@field kind 'comment'|'suggestion'
---@field state 'draft'|'submitted'|'outdated' outdated = anchor lines changed underneath it
---@field reply_to integer|nil gh_id of the remote comment this draft replies to
---@field remote redline.RemoteMeta|nil set for comments fetched from GitHub

---Resolve the review context from the current buffer.
---@return { session: redline.Session, buf: integer, side: 'LEFT'|'RIGHT', path: string }|nil
local function context()
    local session = require('redline.session').current
    local side, path = vim.b.redline_side, vim.b.redline_path
    if not session or not side or not path then
        vim.notify('redline: place the cursor in a review diff buffer first', vim.log.levels.WARN)
        return nil
    end
    return { session = session, buf = vim.api.nvim_get_current_buf(), side = side, path = path }
end

---@param fields table partial redline.Comment
local function create(session, fields)
    fields.id = session.next_comment_id
    session.next_comment_id = session.next_comment_id + 1
    fields.state = fields.state or 'draft'
    fields.kind = fields.kind or 'comment'
    table.insert(session.comments, fields)
    require('redline.session').redraw()
end

---@param lines string[]
---@return string|nil nil when the input is effectively empty
local function body_of(lines)
    local body = table.concat(lines, '\n'):gsub('%s+$', '')
    return body ~= '' and body or nil
end

---Add a comment. With no arguments, comments on the cursor line.
---@param line1? integer
---@param line2? integer
function M.add(line1, line2)
    local ctx = context()
    if not ctx then
        return
    end
    line1 = line1 or vim.api.nvim_win_get_cursor(0)[1]
    line2 = line2 or line1
    if line1 > line2 then
        line1, line2 = line2, line1
    end
    require('redline.ui.input').open({
        title = (' %s:%d%s (%s) '):format(ctx.path, line1, line2 ~= line1 and ('-' .. line2) or '', ctx.side),
        on_confirm = function(lines)
            local body = body_of(lines)
            if not body then
                return
            end
            create(ctx.session, {
                path = ctx.path,
                side = ctx.side,
                line = line2,
                start_line = line1 ~= line2 and line1 or nil,
                start_side = line1 ~= line2 and ctx.side or nil,
                body = body,
            })
        end,
    })
end

---Comment on the last visual selection ('< and '> marks).
function M.add_visual()
    M.add(vim.fn.line("'<"), vim.fn.line("'>"))
end

---Suggest a change: like a comment, but the input is prefilled with a
---```suggestion fence containing the selected lines for editing.
---@param line1 integer
---@param line2 integer
function M.suggest(line1, line2)
    local ctx = context()
    if not ctx then
        return
    end
    if ctx.side ~= 'RIGHT' then
        vim.notify('redline: suggestions must target the new (right) side', vim.log.levels.WARN)
        return
    end
    if line1 > line2 then
        line1, line2 = line2, line1
    end
    local current = vim.api.nvim_buf_get_lines(ctx.buf, line1 - 1, line2, false)
    local initial = { '```suggestion' }
    vim.list_extend(initial, current)
    table.insert(initial, '```')
    require('redline.ui.input').open({
        title = (' suggest %s:%d%s '):format(ctx.path, line1, line2 ~= line1 and ('-' .. line2) or ''),
        initial = initial,
        cursor = { 2, 0 },
        on_confirm = function(lines)
            local body = body_of(lines)
            if not body then
                return
            end
            create(ctx.session, {
                path = ctx.path,
                side = 'RIGHT',
                line = line2,
                start_line = line1 ~= line2 and line1 or nil,
                start_side = line1 ~= line2 and 'RIGHT' or nil,
                body = body,
                kind = 'suggestion',
            })
        end,
    })
end

---Suggest from the last visual selection.
function M.suggest_visual()
    M.suggest(vim.fn.line("'<"), vim.fn.line("'>"))
end

---Comment under the cursor (drafts before remote comments).
---@return redline.Comment|nil
function M.at_cursor()
    local ctx = context()
    if not ctx then
        return nil
    end
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local found = nil
    for _, c in ipairs(ctx.session.comments) do
        if c.path == ctx.path and c.side == ctx.side and lnum >= (c.start_line or c.line) and lnum <= c.line then
            if not c.remote then
                return c
            end
            found = found or c
        end
    end
    return found
end

---Warn instead of silently doing nothing when there is no comment to act on.
---@return redline.Comment|nil
local function required_at_cursor()
    local c = M.at_cursor()
    if not c then
        vim.notify(
            'redline: no comment under the cursor (its lines are highlighted; note LEFT/RIGHT sides are separate)',
            vim.log.levels.WARN
        )
    end
    return c
end

function M.edit_at_cursor()
    local c = required_at_cursor()
    if not c then
        return
    end
    if c.remote then
        vim.notify('redline: cannot edit a comment fetched from GitHub', vim.log.levels.WARN)
        return
    end
    local session = require('redline.session').current
    require('redline.ui.input').open({
        title = (' edit %s:%d '):format(c.path, c.line),
        initial = vim.split(c.body, '\n', { plain = true }),
        on_confirm = function(lines)
            local body = body_of(lines)
            if body then
                c.body = body
                require('redline.session').redraw()
            elseif session then
                M.remove(session, c)
            end
        end,
    })
end

function M.delete_at_cursor()
    local c = required_at_cursor()
    if not c then
        return
    end
    if c.remote then
        vim.notify('redline: cannot delete a comment fetched from GitHub', vim.log.levels.WARN)
        return
    end
    M.remove(require('redline.session').current, c)
    vim.notify(('redline: deleted comment at %s:%d'):format(c.path, c.line))
end

---Reply to the (remote) comment thread under the cursor.
function M.reply_at_cursor()
    local ctx = context()
    if not ctx then
        return
    end
    local c = M.at_cursor()
    if not c or not (c.remote and c.remote.gh_id) then
        vim.notify('redline: no GitHub comment thread under the cursor to reply to', vim.log.levels.WARN)
        return
    end
    local root_id = c.remote.in_reply_to or c.remote.gh_id
    -- Open the reply box beneath the whole thread, not the cursor line: the
    -- thread renders as virtual lines under c.line, so drop past them.
    local anchor = {
        win = vim.api.nvim_get_current_win(),
        line = c.line,
        below = require('redline.ui.threads').thread_height(ctx.buf, c.line),
    }
    require('redline.ui.input').open({
        title = (' reply to @%s '):format(c.remote.author),
        anchor = anchor,
        on_confirm = function(lines)
            local body = body_of(lines)
            if not body then
                return
            end
            create(ctx.session, {
                path = c.path,
                side = c.side,
                line = c.line,
                body = body,
                reply_to = root_id,
            })
        end,
    })
end

---@param session redline.Session
---@param comment redline.Comment
function M.remove(session, comment)
    for i, c in ipairs(session.comments) do
        if c == comment then
            table.remove(session.comments, i)
            break
        end
    end
    require('redline.session').redraw()
end

---All comments in review order: file order, then line, drafts stable.
---@param session redline.Session
---@param predicate? fun(c: redline.Comment): boolean
---@return redline.Comment[]
function M.ordered(session, predicate)
    local file_order = {}
    for i, entry in ipairs(session.files) do
        file_order[entry.path] = i
    end
    local list = vim.tbl_filter(function(c)
        return (not predicate or predicate(c)) and file_order[c.path] ~= nil
    end, session.comments)
    table.sort(list, function(a, b)
        if a.path ~= b.path then
            return file_order[a.path] < file_order[b.path]
        end
        if a.line ~= b.line then
            return a.line < b.line
        end
        return a.id < b.id
    end)
    return list
end

---Jump to the next/previous comment, crossing file boundaries.
---@param dir 1|-1
function M.jump(dir)
    local session = require('redline.session').current
    if not session then
        return
    end
    local list = M.ordered(session)
    if #list == 0 then
        vim.notify('redline: no comments yet', vim.log.levels.INFO)
        return
    end
    local cur_path = session.files[session.file_index] and session.files[session.file_index].path
    local cur_line = vim.b.redline_path and vim.api.nvim_win_get_cursor(0)[1] or 0

    -- Find the first comment strictly after (or before) the cursor position.
    local file_order = {}
    for i, entry in ipairs(session.files) do
        file_order[entry.path] = i
    end
    local target = nil
    if dir == 1 then
        for _, c in ipairs(list) do
            local fo = file_order[c.path]
            if fo > (file_order[cur_path] or 0) or (c.path == cur_path and c.line > cur_line) then
                target = c
                break
            end
        end
        target = target or list[1] -- wrap
    else
        for i = #list, 1, -1 do
            local c = list[i]
            local fo = file_order[c.path]
            if fo < (file_order[cur_path] or math.huge) or (c.path == cur_path and c.line < cur_line) then
                target = c
                break
            end
        end
        target = target or list[#list]
    end
    M.goto_comment(target)
end

---@param comment redline.Comment
function M.goto_comment(comment)
    local session = require('redline.session').current
    if not session then
        return
    end
    for i, entry in ipairs(session.files) do
        if entry.path == comment.path then
            require('redline.session').goto_file(i, function()
                local renderer = require('redline.render').get(require('redline.config').get().view)
                local buf = renderer.target_buf(session, comment.side)
                local win = comment.side == 'LEFT' and session.layout.left_win or session.layout.right_win
                if vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_set_current_win(win)
                    local last = vim.api.nvim_buf_line_count(buf)
                    vim.api.nvim_win_set_cursor(win, { math.min(comment.line, last), 0 })
                end
            end)
            return
        end
    end
    vim.notify('redline: comment file is no longer in the review', vim.log.levels.WARN)
end

---vim.ui.select picker over all draft comments.
function M.pick()
    local session = require('redline.session').current
    if not session then
        return
    end
    local drafts = M.ordered(session, function(c)
        return c.state ~= 'submitted'
    end)
    if #drafts == 0 then
        vim.notify('redline: no draft comments', vim.log.levels.INFO)
        return
    end
    vim.ui.select(drafts, {
        prompt = 'Review comments',
        format_item = function(c)
            local first = c.body:match('[^\n]*')
            return ('%s:%d %s%s'):format(c.path, c.line, c.kind == 'suggestion' and '[suggestion] ' or '', first)
        end,
    }, function(choice)
        if choice then
            M.goto_comment(choice)
        end
    end)
end

---Redraw comment decorations for the currently shown file.
---@param session redline.Session
function M.decorate(session)
    require('redline.ui.threads').decorate(session)
end

---Remap comment anchors after the working tree changed: diff the head lines
---as last shown against the current head lines and shift comment lines
---through the hunks. Comments whose lines were rewritten become 'outdated'.
---@param session redline.Session
---@param done fun()
function M.remap(session, done)
    local paths = {}
    for _, c in ipairs(session.comments) do
        if c.side == 'RIGHT' and not c.remote and session.head_snapshots[c.path] then
            paths[c.path] = true
        end
    end
    local entry_by_path = {}
    for _, entry in ipairs(session.files) do
        entry_by_path[entry.path] = entry
    end

    local queue = vim.tbl_keys(paths)
    local function step()
        local path = table.remove(queue)
        if not path then
            done()
            return
        end
        local entry = entry_by_path[path]
        if not entry then
            -- File left the diff entirely; its comments are outdated.
            for _, c in ipairs(session.comments) do
                if c.path == path and not c.remote then
                    c.state = 'outdated'
                end
            end
            step()
            return
        end
        session.source.get_content(entry, function(_, head)
            local old = session.head_snapshots[path]
            if head and old then
                local hunks = M.diff_hunks(old, head)
                for _, c in ipairs(session.comments) do
                    if c.path == path and c.side == 'RIGHT' and not c.remote then
                        local new_line = M.remap_line(hunks, c.line)
                        local new_start = c.start_line and M.remap_line(hunks, c.start_line) or nil
                        if new_line and (not c.start_line or new_start) then
                            c.line = new_line
                            c.start_line = new_start
                        else
                            c.state = 'outdated'
                        end
                    end
                end
                session.head_snapshots[path] = vim.deepcopy(head)
            end
            step()
        end)
    end
    step()
end

---@param old string[]
---@param new string[]
---@return integer[][] vim.diff index hunks {start_a, count_a, start_b, count_b}
function M.diff_hunks(old, new)
    local a = table.concat(old, '\n') .. '\n'
    local b = table.concat(new, '\n') .. '\n'
    return vim.diff(a, b, { result_type = 'indices' }) --[[@as integer[][] ]]
end

---Map a line number in `old` through diff hunks to its line in `new`.
---Returns nil when the line itself was changed or removed.
---@param hunks integer[][]
---@param line integer
---@return integer|nil
function M.remap_line(hunks, line)
    local offset = 0
    for _, h in ipairs(hunks) do
        local start_a, count_a, _, count_b = h[1], h[2], h[3], h[4]
        if count_a == 0 then
            -- Pure insertion after old line start_a.
            if line > start_a then
                offset = offset + count_b
            end
        elseif line >= start_a and line < start_a + count_a then
            return nil -- line was rewritten or deleted
        elseif line >= start_a + count_a then
            offset = offset + (count_b - count_a)
        end
    end
    return line + offset
end

return M
