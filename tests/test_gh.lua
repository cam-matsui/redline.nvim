-- gh.lua is exercised with vim.system stubbed out — no network, no gh binary.

local gh = require('redline.gh')

---Run `fn` with vim.system replaced by a fake that records the call and
---responds with `result`.
local function with_fake_system(result, fn)
    local calls = {}
    local real = vim.system
    vim.system = function(cmd, opts, on_exit)
        table.insert(calls, { cmd = cmd, opts = opts })
        on_exit(result)
    end
    local ok, err = pcall(fn, calls)
    vim.system = real
    assert(ok, err)
end

describe('gh wrapper', function()
    it('flattens paginated --slurp output', function()
        local pages = '[[{"id":1},{"id":2}],[{"id":3}]]'
        with_fake_system({ code = 0, stdout = pages }, function(calls)
            local got
            gh.api('repos/x/y/pulls/1/files', { paginate = true }, function(data)
                got = data
            end)
            vim.wait(1000, function()
                return got ~= nil
            end)
            eq({ { id = 1 }, { id = 2 }, { id = 3 } }, got)
            assert(vim.list_contains(calls[1].cmd, '--paginate'))
            assert(vim.list_contains(calls[1].cmd, '--slurp'))
        end)
    end)

    it('posts JSON bodies via stdin, never argv', function()
        with_fake_system({ code = 0, stdout = '{"id": 9}' }, function(calls)
            local got
            gh.post('repos/x/y/pulls/1/reviews', { event = 'APPROVE', body = 'lgtm' }, {}, function(data)
                got = data
            end)
            vim.wait(1000, function()
                return got ~= nil
            end)
            eq(9, got.id)
            local call = calls[1]
            assert(vim.list_contains(call.cmd, '--method'))
            assert(vim.list_contains(call.cmd, '--input'))
            eq({ body = 'lgtm', event = 'APPROVE' }, vim.json.decode(call.opts.stdin))
        end)
    end)

    it('queries review requests for the authenticated user', function()
        with_fake_system({ code = 0, stdout = '[{"number":7,"title":"x"}]' }, function(calls)
            local got
            gh.review_requests(function(data)
                got = data
            end)
            vim.wait(1000, function()
                return got ~= nil
            end)
            eq(7, got[1].number)
            local cmd = calls[1].cmd
            assert(vim.list_contains(cmd, 'search'))
            assert(vim.list_contains(cmd, 'prs'))
            assert(vim.list_contains(cmd, '--review-requested'))
            assert(vim.list_contains(cmd, '@me'))
        end)
    end)

    it('reports errors without decoding', function()
        with_fake_system({ code = 1, stderr = 'HTTP 422' }, function()
            local err
            gh.post('repos/x/y/pulls/1/reviews', {}, {}, function(data, e)
                err = e or (data == nil and 'nil' or '')
            end)
            vim.wait(1000, function()
                return err ~= nil
            end)
            eq('HTTP 422', err)
        end)
    end)
end)
