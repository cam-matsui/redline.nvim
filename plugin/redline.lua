-- :Review command and <Plug> mapping registration. command.lua defers its own
-- requires, so loading costs almost nothing until :Review is actually used.

if vim.g.loaded_redline then
    return
end
vim.g.loaded_redline = 1

require('redline.command').setup_plug()

-- Plugin managers generate helptags on install/update — which never happens
-- for a local `dir=` checkout. Generate them ourselves so :help redline
-- always works.
local doc = vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))), 'doc')
if vim.uv.fs_stat(vim.fs.joinpath(doc, 'redline.txt')) and not vim.uv.fs_stat(vim.fs.joinpath(doc, 'tags')) then
    pcall(vim.cmd.helptags, vim.fn.fnameescape(doc))
end

vim.api.nvim_create_user_command('Review', function(cmd)
    require('redline.command').dispatch(cmd)
end, {
    nargs = '*',
    range = true,
    desc = 'redline.nvim: review local diffs and GitHub PRs',
    complete = function(arglead, cmdline, cursorpos)
        return require('redline.command').complete(arglead, cmdline, cursorpos)
    end,
})
