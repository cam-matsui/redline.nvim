---Thin async wrapper around the gh CLI. All GitHub access (and auth) goes
---through gh; the plugin never handles tokens itself.

local config = require('redline.config')

local M = {}

---Run `gh <args>` and call `cb(stdout|nil)`. POST bodies are passed via
---stdin (`--input -`) by the callers, never interpolated into arguments.
---@param args string[]
---@param opts { stdin?: string, cwd?: string }
---@param cb fun(stdout: string|nil, err: string|nil) err combines gh's stderr and the API response body
function M.run(args, opts, cb)
    local cmd = vim.list_extend({ config.get().gh.cmd }, args)
    vim.system(cmd, { text = true, cwd = opts.cwd, stdin = opts.stdin }, function(out)
        vim.schedule(function()
            if out.code ~= 0 then
                -- gh api puts the HTTP status on stderr but the response body
                -- (with GitHub's actual error details) on stdout — keep both.
                local err = vim.trim((out.stderr or '') .. '\n' .. (out.stdout or ''))
                cb(nil, err)
                return
            end
            cb(out.stdout or '')
        end)
    end)
end

---Run gh and JSON-decode stdout. Errors are reported via vim.notify unless
---`opts.silent`.
---@param args string[]
---@param opts { stdin?: string, cwd?: string, silent?: boolean }
---@param cb fun(data: any|nil)
function M.json(args, opts, cb)
    M.run(args, opts, function(stdout, stderr)
        if not stdout then
            if not opts.silent then
                vim.notify(('redline: gh %s failed:\n%s'):format(args[1] or '', stderr or ''), vim.log.levels.ERROR)
            end
            cb(nil)
            return
        end
        local ok, data = pcall(vim.json.decode, stdout)
        cb(ok and data or nil)
    end)
end

---GET a REST endpoint (paginated array endpoints pass paginate=true).
---@param endpoint string e.g. 'repos/{owner}/{repo}/pulls/1/files'
---@param opts { paginate?: boolean, cwd?: string, silent?: boolean }
---@param cb fun(data: any|nil)
function M.api(endpoint, opts, cb)
    local args = { 'api', endpoint }
    if opts.paginate then
        table.insert(args, '--paginate')
        table.insert(args, '--slurp')
    end
    M.json(args, opts, function(data)
        if data and opts.paginate then
            -- --slurp wraps each page's array in an outer array; flatten.
            local flat = {}
            for _, page in ipairs(data) do
                vim.list_extend(flat, page)
            end
            cb(flat)
        else
            cb(data)
        end
    end)
end

---POST a REST endpoint with a JSON body via stdin.
---@param endpoint string
---@param body table
---@param opts { cwd?: string }
---@param cb fun(data: any|nil, err: string|nil)
function M.post(endpoint, body, opts, cb)
    M.run(
        { 'api', '--method', 'POST', endpoint, '--input', '-' },
        { stdin = vim.json.encode(body), cwd = opts.cwd },
        function(stdout, stderr)
            if not stdout then
                cb(nil, stderr)
                return
            end
            local ok, data = pcall(vim.json.decode, stdout)
            cb(ok and data or {}, nil)
        end
    )
end

---owner/name of the repo for `cwd`.
---@param cwd string
---@param cb fun(owner: string|nil, name: string|nil)
function M.repo(cwd, cb)
    M.json({ 'repo', 'view', '--json', 'owner,name' }, { cwd = cwd }, function(data)
        if data and data.owner then
            cb(data.owner.login, data.name)
        else
            cb(nil, nil)
        end
    end)
end

---Open PRs, newest first.
---@param cwd string
---@param cb fun(prs: table[]|nil)
function M.pr_list(cwd, cb)
    M.json({
        'pr',
        'list',
        '--json',
        'number,title,author,headRefName,updatedAt',
        '--limit',
        '50',
    }, { cwd = cwd }, cb)
end

---PR metadata needed to open a review session.
---@param selector string PR number (repo taken from cwd) or a full PR URL
---@param cwd string|nil
---@param cb fun(pr: table|nil)
function M.pr_view(selector, cwd, cb)
    M.json({
        'pr',
        'view',
        selector,
        '--json',
        'number,title,url,baseRefName,headRefName,baseRefOid,headRefOid,author',
    }, { cwd = cwd }, cb)
end

---Rich PR data for the overview screen: description, review/merge state, CI
---rollup, commit history, and the conversation (issue) comments — all in one
---`gh pr view` call.
---@param selector string PR number or URL
---@param cwd string|nil
---@param cb fun(pr: table|nil)
function M.pr_overview(selector, cwd, cb)
    M.json({
        'pr',
        'view',
        selector,
        '--json',
        table.concat({
            'number',
            'title',
            'url',
            'state',
            'isDraft',
            'author',
            'body',
            'baseRefName',
            'headRefName',
            'additions',
            'deletions',
            'changedFiles',
            'mergeable',
            'reviewDecision',
            'createdAt',
            'commits',
            'statusCheckRollup',
            'comments',
        }, ','),
    }, { cwd = cwd }, cb)
end

local viewer_login = nil
local viewer_handles = nil

---Clear the cached identity of the authenticated gh user. Called when a review
---session starts so switching gh accounts (`gh auth switch`) between reviews is
---picked up rather than served stale.
function M.reset_cache()
    viewer_login = nil
    viewer_handles = nil
end

---Login of the authenticated gh user (cached per session).
---@param cb fun(login: string|nil)
function M.viewer(cb)
    if viewer_login then
        cb(viewer_login)
        return
    end
    M.json({ 'api', 'user' }, { silent = true }, function(data)
        viewer_login = data and data.login or nil
        cb(viewer_login)
    end)
end

---CODEOWNERS handles that resolve to the authenticated user: their `@login`
---plus every `@org/team` they belong to. Team lookup needs the `read:org`
---scope; if it is unavailable the login alone is used (best effort).
---@param cb fun(handles: string[])
function M.viewer_handles(cb)
    if viewer_handles then
        cb(viewer_handles)
        return
    end
    M.viewer(function(login)
        local handles = {}
        if login then
            table.insert(handles, '@' .. login)
        end
        M.json({ 'api', 'user/teams', '--paginate' }, { silent = true }, function(teams)
            if type(teams) == 'table' then
                for _, t in ipairs(teams) do
                    if t.organization and t.slug then
                        table.insert(handles, ('@%s/%s'):format(t.organization.login, t.slug))
                    end
                end
            end
            viewer_handles = handles
            cb(handles)
        end)
    end)
end

---Open PRs across GitHub that request the authenticated user as a reviewer.
---Not scoped to any repo, so it works from anywhere.
---@param cb fun(prs: table[]|nil) each: { number, title, url, repository{ nameWithOwner }, author{ login }, updatedAt }
function M.review_requests(cb)
    M.json({
        'search',
        'prs',
        '--review-requested',
        '@me',
        '--state',
        'open',
        '--json',
        'number,title,url,repository,author,updatedAt',
        '--limit',
        '50',
    }, {}, cb)
end

---Submit the session's draft comments as one PR review, then send thread
---replies (GitHub's review endpoint doesn't accept in_reply_to).
function M.submit_review()
    local session = require('redline.session').current
    if not session then
        vim.notify('redline: no active review', vim.log.levels.WARN)
        return
    end
    if not (session.source.can_submit and session.pr) then
        vim.notify(
            'redline: only PR reviews can be submitted (use :Review export for local reviews)',
            vim.log.levels.WARN
        )
        return
    end
    require('redline.submit').start(session)
end

return M
