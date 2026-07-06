-- PR overview rendering: a synthetic PR JSON should produce readable lines
-- with the expected sections.

local overview = require('redline.ui.overview')

local PR = {
    number = 42,
    title = 'Add a widget',
    url = 'https://github.com/o/r/pull/42',
    state = 'OPEN',
    isDraft = false,
    author = { login = 'alice' },
    body = 'This adds a widget.\n\nIt is very useful.',
    baseRefName = 'main',
    headRefName = 'feature',
    additions = 10,
    deletions = 2,
    changedFiles = 3,
    mergeable = 'MERGEABLE',
    reviewDecision = 'CHANGES_REQUESTED',
    commits = {
        { oid = 'abcdef1234567890', messageHeadline = 'First', authors = { { login = 'alice' } } },
        { oid = '1234567890abcdef', messageHeadline = 'Second', authors = { { login = 'bob' } } },
    },
    statusCheckRollup = {
        { name = 'build', status = 'COMPLETED', conclusion = 'SUCCESS' },
        { name = 'lint', status = 'COMPLETED', conclusion = 'FAILURE' },
        { context = 'legacy-ci', state = 'PENDING' },
    },
    comments = {
        { author = { login = 'bob' }, body = 'Please fix lint.', createdAt = '2026-07-01T10:00:00Z' },
    },
}

describe('overview render', function()
    local lines = overview._render(PR)
    local text = table.concat(lines, '\n')

    it('shows the header with number and title', function()
        assert(text:find('#42  Add a widget', 1, true), 'header present')
    end)

    it('shows the merge direction and review decision', function()
        assert(text:find('@alice wants to merge feature → main', 1, true), 'merge direction')
        assert(text:find('CHANGES REQUESTED', 1, true), 'review decision')
    end)

    it('renders each section', function()
        for _, s in ipairs({ 'Description', 'Checks (3)', 'Commits (2)', 'Conversation (1)' }) do
            assert(text:find(s, 1, true), 'section ' .. s)
        end
    end)

    it('lists commits with short shas', function()
        assert(text:find('abcdef12', 1, true), 'first sha')
        assert(text:find('First', 1, true), 'first message')
    end)

    it('includes check names and the conversation comment', function()
        assert(text:find('build', 1, true), 'check name')
        assert(text:find('Please fix lint.', 1, true), 'comment body')
    end)

    it('handles a missing body and empty conversation', function()
        local empty = vim.tbl_extend('force', PR, { body = '', comments = {} })
        local t = table.concat(overview._render(empty), '\n')
        assert(t:find('(no description)', 1, true), 'no-description placeholder')
        assert(t:find('(no conversation comments)', 1, true), 'empty conversation placeholder')
    end)
end)
