---Async git plumbing. Every function takes a callback invoked on the main
---loop (vim.schedule), so callers may touch buffers/windows freely.

local M = {}

---Run `git <args>` in `cwd` and call `cb(stdout_lines|nil)`.
---Non-zero exit calls `cb(nil)`; unless `opts.silent`, the git error is shown
---via vim.notify. Expected failures (e.g. `git show` on a file that does not
---exist at a revision) should pass `silent = true`.
---@param args string[]
---@param opts { cwd?: string, silent?: boolean }
---@param cb fun(lines: string[]|nil)
function M.run(args, opts, cb)
    local cmd = vim.list_extend({ 'git' }, args)
    vim.system(cmd, { text = true, cwd = opts.cwd }, function(out)
        vim.schedule(function()
            if out.code ~= 0 then
                if not opts.silent then
                    vim.notify(
                        ('redline: git %s failed:\n%s'):format(table.concat(args, ' '), out.stderr or ''),
                        vim.log.levels.ERROR
                    )
                end
                cb(nil)
                return
            end
            local stdout = out.stdout or ''
            -- Split keeping empty interior lines; drop the single trailing
            -- newline artifact so an empty file yields {}.
            local lines = vim.split(stdout, '\n', { plain = true })
            if lines[#lines] == '' then
                table.remove(lines)
            end
            cb(lines)
        end)
    end)
end

---Repo root for the cwd. `silent` suppresses the "not a repository" error
---for callers that treat that as a normal case.
---@param cb fun(root: string|nil)
---@param silent? boolean
function M.root(cb, silent)
    M.run({ 'rev-parse', '--show-toplevel' }, { silent = silent }, function(lines)
        cb(lines and lines[1] or nil)
    end)
end

---File contents at a revision, e.g. show('HEAD', 'lua/foo.lua', root, cb).
---cb(nil) when the file does not exist at that revision.
---@param rev string
---@param path string
---@param root string
---@param cb fun(lines: string[]|nil)
function M.show(rev, path, root, cb)
    M.run({ 'show', rev .. ':' .. path }, { cwd = root, silent = true }, cb)
end

return M
