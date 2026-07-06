---:checkhealth redline

local M = {}

function M.check()
    local health = vim.health
    health.start('redline.nvim')

    if vim.fn.has('nvim-0.11') == 1 then
        health.ok('Neovim ≥ 0.11')
    else
        health.error('Neovim 0.11 or newer is required')
    end

    if vim.fn.executable('git') == 1 then
        local version = vim.system({ 'git', '--version' }, { text = true }):wait().stdout or ''
        health.ok(vim.trim(version))
    else
        health.error('git not found (required for all reviews)')
    end

    local gh_cmd = require('redline.config').get().gh.cmd
    if vim.fn.executable(gh_cmd) == 1 then
        local auth = vim.system({ gh_cmd, 'auth', 'status' }, { text = true }):wait()
        if auth.code == 0 then
            health.ok('gh CLI found and authenticated')
        else
            health.warn('gh CLI found but not authenticated — run `gh auth login` (PR review only)')
        end
    else
        health.warn(('gh CLI (%s) not found — local review works, PR review does not'):format(gh_cmd))
    end

    local in_repo = vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { text = true }):wait()
    if in_repo.code == 0 then
        health.ok('inside a git repository: ' .. vim.trim(in_repo.stdout))
    else
        health.info('not inside a git repository right now — :Review needs one')
    end
end

return M
