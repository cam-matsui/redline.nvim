-- Owned-files filter: visible_indices decides which files the panel shows.

local session = require('redline.session')

local function fake(files, owned, filter_owned)
    return {
        files = vim.tbl_map(function(p)
            return { path = p, status = 'M', additions = 0, deletions = 0 }
        end, files),
        owned = owned,
        filter_owned = filter_owned,
    }
end

describe('session.visible_indices', function()
    it('shows all files when the filter is off', function()
        local s = fake({ 'a', 'b', 'c' }, { a = true }, false)
        eq({ 1, 2, 3 }, session.visible_indices(s))
    end)

    it('shows only owned files when the filter is on', function()
        local s = fake({ 'a', 'b', 'c' }, { a = true, c = true }, true)
        eq({ 1, 3 }, session.visible_indices(s))
    end)

    it('shows all files when ownership is unknown even if filtering', function()
        local s = fake({ 'a', 'b' }, nil, true)
        eq({ 1, 2 }, session.visible_indices(s))
    end)

    it('never yields an empty panel: falls back to all files', function()
        local s = fake({ 'a', 'b' }, { z = true }, true)
        eq({ 1, 2 }, session.visible_indices(s))
    end)
end)
