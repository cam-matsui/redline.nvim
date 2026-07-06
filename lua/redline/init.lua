---redline.nvim — review local diffs and GitHub PRs inside Neovim.
---
---Comments use GitHub's review-comment schema (path/line/side/body with
---```suggestion fences), so the same review works as a markdown export for a
---coding agent and as a PR review submitted through the gh CLI.
---
---`setup()` is optional; `:Review` works out of the box with defaults.

local M = {}

---@param opts? redline.Config
function M.setup(opts)
    require('redline.config').setup(opts)
end

return M
