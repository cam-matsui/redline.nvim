local comments = require('redline.comments')

---Remap `line` from `old` to `new` content.
local function remap(old, new, line)
    return comments.remap_line(comments.diff_hunks(old, new), line)
end

describe('comment remapping', function()
    it('keeps lines before any change', function()
        eq(1, remap({ 'a', 'b', 'c' }, { 'a', 'b', 'X', 'c' }, 1))
    end)

    it('shifts lines after an insertion', function()
        eq(4, remap({ 'a', 'b', 'c' }, { 'a', 'b', 'X', 'c' }, 3))
    end)

    it('shifts lines after a deletion', function()
        eq(2, remap({ 'a', 'b', 'c' }, { 'a', 'c' }, 3))
    end)

    it('invalidates a deleted line', function()
        eq(nil, remap({ 'a', 'b', 'c' }, { 'a', 'c' }, 2))
    end)

    it('invalidates a rewritten line', function()
        eq(nil, remap({ 'a', 'b', 'c' }, { 'a', 'B', 'c' }, 2))
    end)

    it('handles no changes', function()
        eq(2, remap({ 'a', 'b' }, { 'a', 'b' }, 2))
    end)

    it('accumulates offsets across hunks', function()
        local old = { 'a', 'b', 'c', 'd', 'e' }
        local new = { 'X', 'a', 'b', 'd', 'e', 'Y' } -- insert before, delete c, append
        eq(5, remap(old, new, 5)) -- +1 from the insert, -1 from the delete
        eq(4, remap(old, new, 4))
        eq(nil, remap(old, new, 3))
    end)
end)
