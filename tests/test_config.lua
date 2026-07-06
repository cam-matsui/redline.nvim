-- Config merge and validation.

local config = require('redline.config')

---Run `fn` with vim.notify capturing messages; returns the captured list.
local function capture_notify(fn)
    local msgs = {}
    local real = vim.notify
    vim.notify = function(msg)
        table.insert(msgs, msg)
    end
    local ok, err = pcall(fn)
    vim.notify = real
    assert(ok, err)
    return msgs
end

describe('config.setup', function()
    it('warns on an unknown top-level key', function()
        local msgs = capture_notify(function()
            config.setup({ auto_refrsh = true }) -- typo
        end)
        local hit = false
        for _, m in ipairs(msgs) do
            if m:find('auto_refrsh', 1, true) then
                hit = true
            end
        end
        assert(hit, 'warns about the misspelled key')
        config.setup({}) -- reset to defaults
    end)

    it('warns on an unknown nested key', function()
        local msgs = capture_notify(function()
            config.setup({ export = { destinaton = '/tmp/x' } }) -- typo
        end)
        local hit = false
        for _, m in ipairs(msgs) do
            if m:find('export.destinaton', 1, true) then
                hit = true
            end
        end
        assert(hit, 'warns about the nested typo')
        config.setup({})
    end)

    it('is quiet for a valid config', function()
        local msgs = capture_notify(function()
            config.setup({ auto_refresh = true, export = { destination = '.redline/review.md', preamble = false } })
        end)
        eq({}, msgs)
        config.setup({})
    end)

    it('rejects a wrong-typed value', function()
        local threw = not pcall(function()
            config.setup({ auto_refresh = 'yes' }) -- should be boolean
        end)
        assert(threw, 'validate errors on a bad type')
        config.setup({})
    end)
end)
