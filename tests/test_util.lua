-- Text helpers shared by the floating UIs.

local util = require('redline.ui.util')

describe('util.truncate', function()
    it('leaves short strings alone', function()
        eq('hello', util.truncate('hello', 10))
    end)
    it('marks the cut with an ellipsis', function()
        eq('hel…', util.truncate('hello world', 4))
    end)
end)

describe('util.pad', function()
    it('pads to the exact display width', function()
        eq('hi   ', util.pad('hi', 5))
    end)
    it('truncates rather than overflow', function()
        eq(5, vim.fn.strdisplaywidth(util.pad('hello world', 5)))
    end)
end)

describe('util.wrap_line', function()
    it('wraps on word boundaries', function()
        eq({ 'a b c', 'd e f' }, util.wrap_line('a b c d e f', 5))
    end)
    it('hard-breaks a word longer than the width', function()
        local out = util.wrap_line('supercalifragilistic', 6)
        for _, l in ipairs(out) do
            assert(vim.fn.strdisplaywidth(l) <= 6, 'each piece fits: ' .. l)
        end
        eq('supercalifragilistic', table.concat(out))
    end)
end)

describe('util.wrap_markdown', function()
    it('preserves indentation inside a fenced block', function()
        local body = 'do this:\n```suggestion\n    if x then\n        y()\n    end\n```'
        local out = util.wrap_markdown(body, 40)
        local kinds, texts = {}, {}
        for _, wl in ipairs(out) do
            table.insert(kinds, wl.kind)
            table.insert(texts, wl.text)
        end
        eq('prose', kinds[1])
        eq('fence', kinds[2])
        eq('code', kinds[3])
        eq('    if x then', texts[3]) -- indentation intact, not reflowed
        eq('        y()', texts[4])
        eq('fence', kinds[6])
    end)

    it('word-wraps prose but not code', function()
        local out = util.wrap_markdown('one two three four five', 8)
        for _, wl in ipairs(out) do
            eq('prose', wl.kind)
            assert(vim.fn.strdisplaywidth(wl.text) <= 8, 'prose fits width')
        end
    end)
end)
