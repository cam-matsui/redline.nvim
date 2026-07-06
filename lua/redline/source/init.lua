---Source interface and the shared builder for local (git-based) sources.
---
---A Source feeds the session with files and file contents. Both callbacks are
---invoked on the main loop.

local git = require('redline.git')

local M = {}

---@class redline.Source
---@field kind 'worktree'|'branch'|'pr'
---@field title string shown in the panel header and export header
---@field can_submit boolean PR sources only
---@field pr redline.PrInfo|nil PR sources only; copied onto the session
---@field list_files fun(cb: fun(files: redline.FileEntry[]|nil))
---@field get_content fun(entry: redline.FileEntry, cb: fun(base: string[]|nil, head: string[]|nil)) nil base = added, nil head = deleted
---@field threads nil|fun(cb: fun(comments: redline.Comment[]|nil)) PR sources only: existing review comments
---@field owned nil|fun(paths: string[], cb: fun(owned: table<string, true>|nil)) PR sources only: CODEOWNERS ownership

---Parse `git diff --name-status -M` output.
---@param lines string[]
---@return redline.FileEntry[]
local function parse_name_status(lines)
    local entries = {}
    for _, line in ipairs(lines) do
        local parts = vim.split(line, '\t', { plain = true })
        local status = parts[1]:sub(1, 1)
        if status == 'R' or status == 'C' then
            table.insert(entries, {
                path = parts[3],
                old_path = parts[2],
                status = 'R',
                additions = 0,
                deletions = 0,
            })
        elseif parts[2] then
            table.insert(entries, {
                path = parts[2],
                status = status,
                additions = 0,
                deletions = 0,
            })
        end
    end
    return entries
end

---Fold `git diff --numstat` counts (and binary markers) into entries.
---Rename lines use a `{old => new}` syntax we don't parse; those keep 0/0.
---@param entries redline.FileEntry[]
---@param lines string[]
local function apply_numstat(entries, lines)
    local by_path = {}
    for _, e in ipairs(entries) do
        by_path[e.path] = e
    end
    for _, line in ipairs(lines) do
        local add, del, path = line:match('^(%S+)\t(%S+)\t(.+)$')
        local entry = path and by_path[path]
        if entry then
            if add == '-' then
                entry.binary = true
            else
                entry.additions = tonumber(add) or 0
                entry.deletions = tonumber(del) or 0
            end
        end
    end
end

---Build a Source that diffs the working tree against `base_rev`.
---@param kind 'worktree'|'branch'
---@param title string
---@param base_rev string commit-ish the LEFT side is read from
---@param root string absolute repo root
---@return redline.Source
function M.local_source(kind, title, base_rev, root)
    ---@type redline.Source
    return {
        kind = kind,
        title = title,
        can_submit = false,

        list_files = function(cb)
            local pending, entries, failed = 3, nil, false
            local untracked_paths = nil
            local numstat_lines = {}
            local function finish()
                pending = pending - 1
                if pending > 0 then
                    return
                end
                if failed then
                    cb(nil)
                    return
                end
                apply_numstat(entries, numstat_lines)
                for _, path in ipairs(untracked_paths) do
                    table.insert(entries, { path = path, status = 'A', additions = 0, deletions = 0 })
                end
                table.sort(entries, function(a, b)
                    return a.path < b.path
                end)
                cb(entries)
            end
            git.run({ 'diff', '--name-status', '-M', base_rev }, { cwd = root }, function(lines)
                if lines then
                    entries = parse_name_status(lines)
                else
                    failed = true
                end
                finish()
            end)
            git.run({ 'diff', '--numstat', '-M', base_rev }, { cwd = root }, function(lines)
                numstat_lines = lines or {}
                finish()
            end)
            git.run({ 'ls-files', '--others', '--exclude-standard' }, { cwd = root }, function(lines)
                untracked_paths = lines or {}
                finish()
            end)
        end,

        get_content = function(entry, cb)
            if entry.binary then
                cb(nil, nil)
                return
            end
            local head = nil
            if entry.status ~= 'D' then
                local abs = root .. '/' .. entry.path
                if vim.fn.filereadable(abs) == 1 then
                    head = vim.fn.readfile(abs)
                end
            end
            if entry.status == 'A' then
                cb(nil, head)
                return
            end
            git.show(base_rev, entry.old_path or entry.path, root, function(base)
                cb(base, head)
            end)
        end,
    }
end

return M
