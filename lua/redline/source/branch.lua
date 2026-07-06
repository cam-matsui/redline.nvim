---Working tree vs merge-base(ref) — review everything this branch changes,
---including uncommitted work.

local config = require('redline.config')
local git = require('redline.git')
local source = require('redline.source')

local M = {}

---@param ref string|nil explicit base ref; falls back to config.default_base,
---then to the remote default branch (origin/HEAD)
---@param root string
---@param cb fun(src: redline.Source|nil)
function M.create(ref, root, cb)
    local function with_ref(base_ref)
        git.run({ 'merge-base', base_ref, 'HEAD' }, { cwd = root }, function(lines)
            if not lines or not lines[1] then
                cb(nil)
                return
            end
            cb(source.local_source('branch', 'branch vs ' .. base_ref, lines[1], root))
        end)
    end

    ref = ref or config.get().default_base
    if ref then
        with_ref(ref)
        return
    end
    git.run({ 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD' }, { cwd = root, silent = true }, function(lines)
        if lines and lines[1] then
            with_ref(lines[1])
        else
            vim.notify(
                'redline: cannot detect base branch (no origin/HEAD); use :Review branch <ref> '
                    .. 'or set default_base in setup()',
                vim.log.levels.ERROR
            )
            cb(nil)
        end
    end)
end

return M
