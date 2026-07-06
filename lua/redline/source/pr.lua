---GitHub PR source. Metadata, file list, and threads come from the gh CLI;
---file contents come from local git at the PR's pinned SHAs (fetched on
---open), with the raw-contents API as a fallback when the fetch fails.

local git = require('redline.git')
local gh = require('redline.gh')

local M = {}

local status_map = {
    added = 'A',
    removed = 'D',
    modified = 'M',
    changed = 'M',
    renamed = 'R',
    copied = 'A',
}

---Fetch the PR's base/head commits so `git show <sha>:<path>` works.
---Failure is tolerated — get_content falls back to the contents API.
---@param pr redline.PrInfo
---@param root string
---@param cb fun()
local function fetch_oids(pr, root, cb)
    git.run({ 'fetch', '--quiet', 'origin', pr.base_oid, pr.head_oid }, { cwd = root, silent = true }, function(ok)
        if ok then
            cb()
            return
        end
        -- Some setups refuse fetching raw SHAs; the PR refspec always works
        -- on GitHub remotes.
        git.run(
            { 'fetch', '--quiet', 'origin', ('pull/%d/head'):format(pr.number), pr.base_ref },
            { cwd = root, silent = true },
            function()
                cb()
            end
        )
    end)
end

---@param pr redline.PrInfo
---@param root string|nil clone of the PR's repo; nil = contents API only
---@return redline.Source
local function make_source(pr, root)
    local content_cache = {} ---@type table<string, string[]|false>

    ---git-show first (when a matching clone is available), contents API second.
    ---@param sha string
    ---@param path string
    ---@param cb fun(lines: string[]|nil)
    local function file_at(sha, path, cb)
        local key = sha .. ':' .. path
        if content_cache[key] ~= nil then
            cb(content_cache[key] or nil)
            return
        end
        local function from_git(done)
            if root then
                git.show(sha, path, root, done)
            else
                done(nil)
            end
        end
        from_git(function(lines)
            if lines then
                content_cache[key] = lines
                cb(lines)
                return
            end
            gh.run({
                'api',
                ('repos/%s/%s/contents/%s?ref=%s'):format(pr.owner, pr.repo, path, sha),
                '-H',
                'Accept: application/vnd.github.raw+json',
            }, { cwd = root }, function(stdout)
                local content = nil
                if stdout then
                    content = vim.split(stdout, '\n', { plain = true })
                    if content[#content] == '' then
                        table.remove(content)
                    end
                end
                content_cache[key] = content or false
                cb(content)
            end)
        end)
    end

    ---Locate and read the repo's CODEOWNERS (nil if none). GitHub honors it in
    ---.github/, the root, or docs/, and resolves ownership from the *base*
    ---branch, so we read it there.
    ---@param cb fun(text: string|nil)
    local function codeowners_text(cb)
        local locations = { '.github/CODEOWNERS', 'CODEOWNERS', 'docs/CODEOWNERS' }
        local function try(i)
            local path = locations[i]
            if not path then
                cb(nil)
                return
            end
            file_at(pr.base_oid, path, function(lines)
                if lines then
                    cb(table.concat(lines, '\n'))
                else
                    try(i + 1)
                end
            end)
        end
        try(1)
    end

    ---@type redline.Source
    return {
        kind = 'pr',
        title = ('PR #%d: %s'):format(pr.number, pr.title),
        can_submit = true,
        pr = pr,

        owned = function(paths, cb)
            codeowners_text(function(text)
                if not text then
                    cb(nil) -- no CODEOWNERS: nothing to filter by
                    return
                end
                local rules = require('redline.codeowners').parse(text)
                gh.viewer_handles(function(handles)
                    cb(require('redline.codeowners').owned_by(rules, paths, handles))
                end)
            end)
        end,

        list_files = function(cb)
            gh.api(
                ('repos/%s/%s/pulls/%d/files'):format(pr.owner, pr.repo, pr.number),
                { paginate = true, cwd = root },
                function(files)
                    if not files then
                        cb(nil)
                        return
                    end
                    local entries = {}
                    for _, f in ipairs(files) do
                        local status = status_map[f.status]
                        if status then
                            pr.patches[f.filename] = f.patch -- nil for large/binary files
                            table.insert(entries, {
                                path = f.filename,
                                status = status,
                                old_path = f.previous_filename,
                                additions = f.additions or 0,
                                deletions = f.deletions or 0,
                            })
                        end
                    end
                    cb(entries)
                end
            )
        end,

        get_content = function(entry, cb)
            local function with_head(head)
                if entry.status == 'A' then
                    cb(nil, head)
                    return
                end
                file_at(pr.base_oid, entry.old_path or entry.path, function(base)
                    cb(base, head)
                end)
            end
            if entry.status == 'D' then
                with_head(nil)
            else
                file_at(pr.head_oid, entry.path, with_head)
            end
        end,

        threads = function(cb)
            gh.api(
                ('repos/%s/%s/pulls/%d/comments'):format(pr.owner, pr.repo, pr.number),
                { paginate = true, cwd = root },
                function(raw)
                    if not raw then
                        cb(nil)
                        return
                    end
                    local comments = {}
                    for _, rc in ipairs(raw) do
                        local line = rc.line ~= vim.NIL and rc.line or nil
                        table.insert(comments, {
                            id = -rc.id, -- negative: never collides with local ids
                            path = rc.path,
                            -- line == null means GitHub considers it outdated;
                            -- anchor at the original line so it still displays.
                            line = line or rc.original_line or 1,
                            side = (rc.side ~= vim.NIL and rc.side) or 'RIGHT',
                            start_line = rc.start_line ~= vim.NIL and rc.start_line or nil,
                            start_side = rc.start_side ~= vim.NIL and rc.start_side or nil,
                            body = rc.body or '',
                            kind = 'comment',
                            state = line and 'submitted' or 'outdated',
                            remote = {
                                gh_id = rc.id,
                                author = rc.user and rc.user.login or 'unknown',
                                in_reply_to = rc.in_reply_to_id ~= vim.NIL and rc.in_reply_to_id or nil,
                                created_at = rc.created_at or '',
                            },
                        })
                    end
                    cb(comments)
                end
            )
        end,
    }
end

---Parse the `:Review pr` argument: `123`, `#123`, or a full PR URL like
---https://github.com/owner/repo/pull/123 (URL works from any directory).
---@param arg string|integer|nil
---@return integer|nil number, string|nil owner, string|nil repo
function M.parse(arg)
    if arg == nil then
        return nil
    end
    arg = tostring(arg)
    local owner, repo, num = arg:match('github%.com/([^/%s]+)/([^/%s]+)/pull/(%d+)')
    if owner then
        return tonumber(num), owner, repo
    end
    local n = arg:match('^#?(%d+)$')
    return n and tonumber(n) or nil
end

---Open the review session once PR metadata and (optionally) a matching
---local clone are known.
---@param meta table gh pr view JSON
---@param owner string
---@param repo string
---@param root string|nil
local function open_session(meta, owner, repo, root)
    ---@type redline.PrInfo
    local pr = {
        number = meta.number,
        title = meta.title,
        owner = owner,
        repo = repo,
        base_oid = meta.baseRefOid,
        head_oid = meta.headRefOid,
        base_ref = meta.baseRefName,
        url = meta.url,
        author = meta.author and meta.author.login or nil,
        patches = {},
    }
    local function begin()
        require('redline.session').start(make_source(pr, root), root)
    end
    if root then
        fetch_oids(pr, root, begin)
    else
        begin()
    end
end

---Review a PR given by URL: resolves everything through gh, then checks
---whether the cwd happens to be a clone of that repo (faster content reads).
---@param number integer
---@param owner string
---@param repo string
---@param url_arg string
local function start_by_url(number, owner, repo, url_arg)
    gh.pr_view(url_arg, nil, function(meta)
        if not meta then
            return
        end
        git.root(function(root)
            if not root then
                open_session(meta, owner, repo, nil)
                return
            end
            gh.repo(root, function(cwd_owner, cwd_repo)
                local matches = cwd_owner == owner and cwd_repo == repo
                open_session(meta, owner, repo, matches and root or nil)
            end)
        end, true)
    end)
end

---List every open PR that requests you as a reviewer (across all repos) and
---open the chosen one in the review tool. Works from any directory.
function M.requests()
    if vim.fn.executable(require('redline.config').get().gh.cmd) ~= 1 then
        vim.notify('redline: PR review needs the gh CLI (https://cli.github.com)', vim.log.levels.ERROR)
        return
    end
    gh.review_requests(function(prs)
        if not prs then
            return -- gh.json already reported the failure
        end
        if #prs == 0 then
            vim.notify('redline: no PRs are waiting on your review', vim.log.levels.INFO)
            return
        end
        table.sort(prs, function(a, b)
            return (a.updatedAt or '') > (b.updatedAt or '')
        end)
        vim.ui.select(prs, {
            prompt = 'PRs awaiting your review',
            format_item = function(pr)
                local repo = pr.repository and pr.repository.nameWithOwner or '?'
                local author = pr.author and pr.author.login or '?'
                return ('%s #%d  %s  (@%s)'):format(repo, pr.number, pr.title, author)
            end,
        }, function(choice)
            if choice then
                M.start(choice.url)
            end
        end)
    end)
end

---Open a PR review. Accepts a number (`123`, `#123`) for a PR of the repo
---you are in, a full PR URL for any repo, or nothing to pick from a list.
---@param arg string|integer|nil
function M.start(arg)
    if vim.fn.executable(require('redline.config').get().gh.cmd) ~= 1 then
        vim.notify('redline: PR review needs the gh CLI (https://cli.github.com)', vim.log.levels.ERROR)
        return
    end
    local number, url_owner, url_repo = M.parse(arg)
    if arg ~= nil and not number then
        vim.notify('redline: cannot parse PR reference: ' .. tostring(arg), vim.log.levels.ERROR)
        return
    end
    if number and url_owner then
        start_by_url(number, url_owner, url_repo, tostring(arg))
        return
    end

    git.root(function(root)
        if not root then
            return
        end
        if not number then
            gh.pr_list(root, function(prs)
                if not prs or #prs == 0 then
                    vim.notify('redline: no open PRs', vim.log.levels.INFO)
                    return
                end
                vim.ui.select(prs, {
                    prompt = 'Review PR',
                    format_item = function(pr)
                        return ('#%d %s (@%s)'):format(pr.number, pr.title, pr.author.login)
                    end,
                }, function(choice)
                    if choice then
                        M.start(choice.number)
                    end
                end)
            end)
            return
        end

        gh.pr_view(tostring(number), root, function(meta)
            if not meta then
                return
            end
            gh.repo(root, function(owner, repo)
                if not owner then
                    vim.notify('redline: cannot resolve GitHub repo for ' .. root, vim.log.levels.ERROR)
                    return
                end
                open_session(meta, owner, repo, root)
            end)
        end)
    end)
end

return M
