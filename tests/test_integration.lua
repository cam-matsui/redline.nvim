-- End-to-end smoke test: build a real git repo in a temp dir, start a
-- worktree review headless, and assert the session, buffers, and export.

local function sh(args, cwd)
    local out = vim.system(args, { text = true, cwd = cwd }):wait()
    assert(out.code == 0, ('command %s failed: %s'):format(table.concat(args, ' '), out.stderr or ''))
    return out.stdout
end

---@return string repo root
local function make_repo()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    sh({ 'git', 'init', '-b', 'main' }, dir)
    sh({ 'git', 'config', 'user.email', 'test@example.com' }, dir)
    sh({ 'git', 'config', 'user.name', 'test' }, dir)
    vim.fn.writefile({ 'line 1', 'line 2', 'line 3' }, dir .. '/keep.txt')
    vim.fn.writefile({ 'old' }, dir .. '/gone.txt')
    sh({ 'git', 'add', '.' }, dir)
    sh({ 'git', 'commit', '-m', 'init' }, dir)
    -- Working tree changes: modify, delete, add untracked.
    vim.fn.writefile({ 'line 1', 'line 2 changed', 'line 3', 'line 4' }, dir .. '/keep.txt')
    vim.fn.delete(dir .. '/gone.txt')
    vim.fn.writefile({ 'brand new' }, dir .. '/new.txt')
    return dir
end

---Wait until `cond` returns truthy or fail the test.
local function wait_for(cond, what)
    local ok = vim.wait(5000, cond, 10)
    assert(ok, 'timed out waiting for ' .. what)
end

describe('worktree review (integration)', function()
    local session_mod = require('redline.session')

    it('opens a session with the changed files', function()
        local dir = make_repo()
        vim.cmd.cd(dir)

        require('redline.source.worktree').create(dir, function(src)
            session_mod.start(src, dir)
        end)
        -- redline_path is set by show_file, so this waits for the first file
        -- to actually be on screen (file_index alone is set before content loads).
        wait_for(function()
            local s = session_mod.current
            return s ~= nil
                and s.layout.right_buf ~= nil
                and vim.api.nvim_buf_is_valid(s.layout.right_buf)
                and vim.b[s.layout.right_buf].redline_path == 'gone.txt'
        end, 'session to open')

        local s = session_mod.current
        eq(
            { { 'gone.txt', 'D' }, { 'keep.txt', 'M' }, { 'new.txt', 'A' } },
            vim.tbl_map(function(e)
                return { e.path, e.status }
            end, s.files)
        )

        -- First file (gone.txt, deleted): base has content, head is empty.
        eq({ 'old' }, vim.api.nvim_buf_get_lines(s.layout.left_buf, 0, -1, false))
        eq({ '' }, vim.api.nvim_buf_get_lines(s.layout.right_buf, 0, -1, false))

        -- Switch to keep.txt and check both sides.
        local shown = false
        session_mod.goto_file(2, function()
            shown = true
        end)
        wait_for(function()
            return shown
        end, 'keep.txt to render')
        eq({ 'line 1', 'line 2', 'line 3' }, vim.api.nvim_buf_get_lines(s.layout.left_buf, 0, -1, false))
        eq(
            { 'line 1', 'line 2 changed', 'line 3', 'line 4' },
            vim.api.nvim_buf_get_lines(s.layout.right_buf, 0, -1, false)
        )
        eq('RIGHT', vim.b[s.layout.right_buf].redline_side)
        eq('keep.txt', vim.b[s.layout.right_buf].redline_path)

        -- Panel shows the title, a summary line, a blank, then one line per file.
        local panel = vim.api.nvim_buf_get_lines(s.layout.panel_buf, 0, -1, false)
        eq(' worktree vs HEAD', panel[1])
        assert(panel[2]:find('3 files', 1, true), 'summary line shows file count')
        eq(3 + #s.files, #panel)

        -- A comment on the RIGHT side lands in the export.
        table.insert(s.comments, {
            id = s.next_comment_id,
            path = 'keep.txt',
            line = 2,
            side = 'RIGHT',
            body = 'why was this changed?',
            kind = 'comment',
            state = 'draft',
        })
        s.next_comment_id = s.next_comment_id + 1
        session_mod.redraw()
        local text = require('redline.export').render(s)
        assert(text:find('### `keep.txt:2` %(RIGHT%)'), 'export contains the comment header')
        assert(text:find('why was this changed?', 1, true), 'export contains the body')

        -- Refresh after an external edit remaps the comment anchor.
        vim.fn.writefile({ 'inserted above', 'line 1', 'line 2 changed', 'line 3', 'line 4' }, dir .. '/keep.txt')
        local remapped = false
        require('redline.comments').remap(s, function()
            remapped = true
        end)
        wait_for(function()
            return remapped
        end, 'comment remap')
        eq(3, s.comments[1].line)
        eq('draft', s.comments[1].state)

        session_mod.stop()
        eq(nil, session_mod.current)
    end)
end)
