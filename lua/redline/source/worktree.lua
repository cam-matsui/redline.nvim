---Working tree vs HEAD — "what did the agent just change".

local source = require('redline.source')

local M = {}

---@param root string
---@param cb fun(src: redline.Source)
function M.create(root, cb)
    cb(source.local_source('worktree', 'worktree vs HEAD', 'HEAD', root))
end

return M
