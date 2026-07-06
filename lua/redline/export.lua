---Export draft comments as deterministic markdown mirroring GitHub's
---review-comment fields. The output is meant to be handed to a coding agent
---(or a human) — the format is documented in the README and stable.

local M = {}

---Agent-facing instructions prepended to an export when `export.preamble` is
---on, so the file is self-contained: whoever (or whatever) reads it knows how
---to act on the comments without any out-of-band explanation.
M.PREAMBLE = {
    '> Apply this code review. Each `### path:line (SIDE)` heading marks a',
    '> comment on that location: RIGHT = the new/current code, LEFT = the base.',
    '> A ```suggestion block is an exact replacement for the referenced line(s).',
    '> Make the edits, then delete this file.',
    '',
}

---Build the export text for a session.
---@param session redline.Session
---@return string|nil nil when there is nothing to export
function M.render(session)
    local comments = require('redline.comments').ordered(session, function(c)
        return not c.remote and c.state ~= 'submitted'
    end)
    if #comments == 0 then
        return nil
    end

    local lines = {}
    if require('redline.config').get().export.preamble then
        vim.list_extend(lines, M.PREAMBLE)
    end
    vim.list_extend(lines, {
        ('# Code review: %s — %s'):format(session.source.title, os.date('%Y-%m-%d')),
        '',
    })
    local current_file = nil
    for _, c in ipairs(comments) do
        if c.path ~= current_file then
            current_file = c.path
            table.insert(lines, ('## `%s`'):format(c.path))
            table.insert(lines, '')
        end
        local loc = c.start_line and ('%d-%d'):format(c.start_line, c.line) or tostring(c.line)
        table.insert(lines, ('### `%s:%s` (%s)'):format(c.path, loc, c.side))
        if c.state == 'outdated' then
            table.insert(lines, '> outdated: the code under this comment has changed')
        end
        table.insert(lines, '')
        vim.list_extend(lines, vim.split(c.body, '\n', { plain = true }))
        table.insert(lines, '')
    end
    return table.concat(lines, '\n')
end

---Export to `destination` (or config.export.destination): 'buffer' opens a
---markdown split, 'register' yanks to "+", anything else is a file path.
---@param destination? string
function M.export(destination)
    local session = require('redline.session').current
    if not session then
        vim.notify('redline: no active review', vim.log.levels.WARN)
        return
    end
    local text = M.render(session)
    if not text then
        vim.notify('redline: no comments to export', vim.log.levels.INFO)
        return
    end
    destination = destination or require('redline.config').get().export.destination

    if destination == 'register' then
        vim.fn.setreg('+', text)
        vim.notify('redline: review copied to "+ register')
    elseif destination == 'buffer' then
        vim.cmd('botright new')
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
        vim.bo[buf].buftype = 'nofile'
        vim.bo[buf].bufhidden = 'wipe'
        vim.bo[buf].swapfile = false
        vim.bo[buf].filetype = 'markdown'
    else
        -- A relative path resolves against the repo root, not Neovim's cwd, so
        -- a fixed destination like '.redline/review.md' always lands in the
        -- project being reviewed regardless of where nvim was launched.
        local path = destination
        if session.root and not vim.startswith(path, '/') then
            path = session.root .. '/' .. path
        end
        path = vim.fn.fnamemodify(path, ':p')
        vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
        vim.fn.writefile(vim.split(text, '\n', { plain = true }), path)
        vim.notify('redline: review written to ' .. path)
    end
end

return M
