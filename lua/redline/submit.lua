---PR review submission: validate draft comments against the PR's diff
---hunks, POST one atomic review, then send thread replies (which GitHub's
---review endpoint does not accept).

local gh = require('redline.gh')
local hunks = require('redline.hunks')

local M = {}

local EVENTS = {
    { label = 'Comment', event = 'COMMENT' },
    { label = 'Approve', event = 'APPROVE' },
    { label = 'Request changes', event = 'REQUEST_CHANGES' },
}

---Split drafts into review comments and thread replies, flagging comments
---GitHub would reject (outside any diff hunk → the whole POST 422s).
---@param session redline.Session
---@return redline.Comment[] comments, redline.Comment[] replies, redline.Comment[] violations
local function classify(session)
    local comments, replies, violations = {}, {}, {}
    for _, c in ipairs(session.comments) do
        if not c.remote and c.state ~= 'submitted' then
            if c.reply_to then
                table.insert(replies, c)
            else
                local patch = session.pr.patches[c.path]
                -- No patch text (very large or binary file): submit
                -- optimistically rather than block the review.
                if patch and not hunks.comment_in_hunks(c, hunks.ranges(patch)) then
                    table.insert(violations, c)
                else
                    table.insert(comments, c)
                end
            end
        end
    end
    return comments, replies, violations
end

---@param c redline.Comment
---@return table GitHub review-comment payload
local function payload_of(c)
    local p = { path = c.path, body = c.body, line = c.line, side = c.side }
    if c.start_line then
        p.start_line = c.start_line
        p.start_side = c.start_side or c.side
    end
    return p
end

---@param session redline.Session
---@param replies redline.Comment[]
---@param done fun(failed: integer)
local function send_replies(session, replies, done)
    local pr = session.pr
    local failed = 0
    local function step(i)
        local c = replies[i]
        if not c then
            done(failed)
            return
        end
        gh.post(
            ('repos/%s/%s/pulls/%d/comments'):format(pr.owner, pr.repo, pr.number),
            { body = c.body, in_reply_to = c.reply_to },
            { cwd = session.root },
            function(data, err)
                if data then
                    c.state = 'submitted'
                else
                    failed = failed + 1
                    vim.notify(
                        ('redline: reply on %s:%d failed:\n%s'):format(c.path, c.line, err or ''),
                        vim.log.levels.ERROR
                    )
                end
                step(i + 1)
            end
        )
    end
    step(1)
end

---@param session redline.Session
---@param event string APPROVE | REQUEST_CHANGES | COMMENT
---@param body string review summary (may be empty)
---@param comments redline.Comment[]
---@param replies redline.Comment[]
local function post_review(session, event, body, comments, replies)
    local pr = session.pr
    local review = {
        commit_id = pr.head_oid,
        event = event,
        body = body,
    }
    -- Omit the key entirely when empty: an empty Lua table would encode as a
    -- JSON object ({}), and GitHub rejects anything but an array here.
    if #comments > 0 then
        review.comments = vim.tbl_map(payload_of, comments)
    end
    gh.post(
        ('repos/%s/%s/pulls/%d/reviews'):format(pr.owner, pr.repo, pr.number),
        review,
        { cwd = session.root },
        function(data, err)
            if not data then
                vim.notify('redline: review submission failed:\n' .. (err or ''), vim.log.levels.ERROR)
                return
            end
            for _, c in ipairs(comments) do
                c.state = 'submitted'
            end
            send_replies(session, replies, function(failed)
                require('redline.session').redraw()
                local msg = ('redline: review submitted (%s, %d comment%s) — %s'):format(
                    event,
                    #comments,
                    #comments == 1 and '' or 's',
                    pr.url
                )
                if failed > 0 then
                    msg = msg .. ('\n%d thread repl%s failed'):format(failed, failed == 1 and 'y' or 'ies')
                end
                vim.notify(msg, failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
            end)
        end
    )
end

---Interactive submit flow for the current PR session.
---@param session redline.Session
function M.start(session)
    local comments, replies, violations = classify(session)

    if #violations > 0 then
        local names = vim.tbl_map(function(c)
            return ('  %s:%d'):format(c.path, c.line)
        end, violations)
        local choice = vim.fn.confirm(
            ('%d comment%s target lines outside the PR diff (GitHub rejects these):\n%s'):format(
                #violations,
                #violations == 1 and '' or 's',
                table.concat(names, '\n')
            ),
            '&Skip them\n&Abort',
            2
        )
        if choice ~= 1 then
            return
        end
    end

    if #comments == 0 and #replies == 0 then
        local ok = vim.fn.confirm('No draft comments — submit a review without comments?', '&Yes\n&No', 2)
        if ok ~= 1 then
            return
        end
    end

    -- GitHub hard-rejects APPROVE/REQUEST_CHANGES on your own PR (422);
    -- don't offer verdicts that cannot succeed.
    gh.viewer(function(login)
        local events = EVENTS
        if login and session.pr.author == login then
            events = { EVENTS[1] } -- COMMENT only
            vim.notify('redline: this is your own PR — GitHub only allows Comment reviews on it', vim.log.levels.INFO)
        end
        M.pick_event(session, events, comments, replies)
    end)
end

---@param session redline.Session
---@param events table
---@param comments redline.Comment[]
---@param replies redline.Comment[]
function M.pick_event(session, events, comments, replies)
    vim.ui.select(events, {
        prompt = 'Submit review',
        format_item = function(e)
            return e.label
        end,
    }, function(choice)
        if not choice then
            return
        end
        require('redline.ui.input').open({
            title = ' review summary (optional) ',
            on_confirm = function(lines)
                local body = table.concat(lines, '\n'):gsub('%s+$', '')
                -- A COMMENT review with no body and no inline comments is
                -- rejected by GitHub; when the session only holds thread
                -- replies, send those directly instead of wrapping them in
                -- an (invalid) empty review.
                if choice.event == 'REQUEST_CHANGES' and body == '' and #comments == 0 then
                    vim.notify(
                        'redline: GitHub requires a summary or inline comments to request changes',
                        vim.log.levels.WARN
                    )
                    return
                end
                if #comments == 0 and body == '' and choice.event == 'COMMENT' then
                    if #replies == 0 then
                        vim.notify('redline: nothing to submit', vim.log.levels.WARN)
                        return
                    end
                    send_replies(session, replies, function(failed)
                        require('redline.session').redraw()
                        vim.notify(
                            ('redline: %d thread repl%s sent%s'):format(
                                #replies - failed,
                                (#replies - failed) == 1 and 'y' or 'ies',
                                failed > 0 and (', %d failed'):format(failed) or ''
                            ),
                            failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
                        )
                    end)
                    return
                end
                post_review(session, choice.event, body, comments, replies)
            end,
        })
    end)
end

return M
