local export = require('redline.export')
local config = require('redline.config')

---A fake session with just the fields export/comments need.
local function fake_session()
    return {
        source = { title = 'worktree vs HEAD' },
        files = {
            { path = 'lua/a.lua', status = 'M', additions = 1, deletions = 0 },
            { path = 'lua/b.lua', status = 'M', additions = 2, deletions = 2 },
        },
        comments = {},
    }
end

describe('export.render', function()
    -- Body goldens below assert exact output, so pin the preamble off; a
    -- dedicated test covers the preamble-on path.
    config.setup({ export = { preamble = false } })

    it('returns nil with no comments', function()
        eq(nil, export.render(fake_session()))
    end)

    it('prepends the agent preamble when enabled', function()
        config.setup({ export = { preamble = true } })
        local s = fake_session()
        s.comments = {
            { id = 1, path = 'lua/a.lua', line = 3, side = 'RIGHT', body = 'x', kind = 'comment', state = 'draft' },
        }
        local text = export.render(s)
        assert(vim.startswith(text, table.concat(export.PREAMBLE, '\n')), 'starts with preamble')
        assert(text:find('# Code review:', 1, true), 'still has the heading')
        config.setup({ export = { preamble = false } })
    end)

    it('renders GitHub-style sections in file order', function()
        local s = fake_session()
        s.comments = {
            {
                id = 2,
                path = 'lua/b.lua',
                line = 7,
                side = 'RIGHT',
                body = 'second file',
                kind = 'comment',
                state = 'draft',
            },
            {
                id = 1,
                path = 'lua/a.lua',
                line = 3,
                side = 'RIGHT',
                body = 'first file',
                kind = 'comment',
                state = 'draft',
            },
        }
        local expected = table.concat({
            '# Code review: worktree vs HEAD — ' .. os.date('%Y-%m-%d'),
            '',
            '## `lua/a.lua`',
            '',
            '### `lua/a.lua:3` (RIGHT)',
            '',
            'first file',
            '',
            '## `lua/b.lua`',
            '',
            '### `lua/b.lua:7` (RIGHT)',
            '',
            'second file',
            '',
        }, '\n')
        eq(expected, export.render(s))
    end)

    it('renders ranges, suggestion fences and outdated markers verbatim', function()
        local s = fake_session()
        s.comments = {
            {
                id = 1,
                path = 'lua/a.lua',
                line = 14,
                start_line = 10,
                side = 'RIGHT',
                start_side = 'RIGHT',
                body = '```suggestion\nlocal x = 1\n```',
                kind = 'suggestion',
                state = 'outdated',
            },
        }
        local expected = table.concat({
            '# Code review: worktree vs HEAD — ' .. os.date('%Y-%m-%d'),
            '',
            '## `lua/a.lua`',
            '',
            '### `lua/a.lua:10-14` (RIGHT)',
            '> outdated: the code under this comment has changed',
            '',
            '```suggestion',
            'local x = 1',
            '```',
            '',
        }, '\n')
        eq(expected, export.render(s))
    end)

    it('skips remote and submitted comments', function()
        local s = fake_session()
        s.comments = {
            { id = 1, path = 'lua/a.lua', line = 1, side = 'RIGHT', body = 'x', state = 'submitted' },
            {
                id = 2,
                path = 'lua/a.lua',
                line = 2,
                side = 'RIGHT',
                body = 'y',
                state = 'draft',
                remote = { gh_id = 1, author = 'someone', created_at = '' },
            },
        }
        eq(nil, export.render(s))
    end)
end)
