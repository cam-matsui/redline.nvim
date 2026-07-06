-- Thread grouping and ordering for inline comment display.

local threads = require('redline.ui.threads')

local function remote(gh_id, reply_to, at)
    return {
        id = -gh_id,
        remote = { gh_id = gh_id, in_reply_to = reply_to, author = 'a', created_at = at },
    }
end

describe('threads._thread_key', function()
    it('gives a standalone draft its own key', function()
        eq('d7', threads._thread_key({ id = 7 }))
    end)

    it('groups a remote reply with its root', function()
        local root = remote(100, nil, '2026-07-01T00:00:00Z')
        local reply = remote(101, 100, '2026-07-02T00:00:00Z')
        eq(threads._thread_key(root), threads._thread_key(reply))
    end)

    it('groups a draft reply with the remote root it answers', function()
        local root = remote(100, nil, '2026-07-01T00:00:00Z')
        local draft_reply = { id = 5, reply_to = 100 }
        eq(threads._thread_key(root), threads._thread_key(draft_reply))
    end)
end)

describe('threads._thread_order', function()
    it('sorts remote comments oldest-first', function()
        local a = remote(100, nil, '2026-07-01T09:00:00Z')
        local b = remote(101, 100, '2026-07-02T09:00:00Z')
        assert(threads._thread_order(a, b), 'older remote sorts before newer')
        assert(not threads._thread_order(b, a), 'and not the reverse')
    end)

    it('puts existing remote comments before local drafts', function()
        local r = remote(100, nil, '2026-07-01T09:00:00Z')
        local d = { id = 1 }
        assert(threads._thread_order(r, d), 'remote before draft')
        assert(not threads._thread_order(d, r), 'draft after remote')
    end)

    it('sorts drafts by creation order', function()
        assert(threads._thread_order({ id = 1 }, { id = 2 }), 'earlier draft first')
    end)

    it('produces oldest-first, newest-last when sorted', function()
        local list = {
            { id = 9 }, -- a fresh draft reply (newest)
            remote(101, 100, '2026-07-02T09:00:00Z'),
            remote(100, nil, '2026-07-01T09:00:00Z'),
        }
        table.sort(list, threads._thread_order)
        eq(100, list[1].remote.gh_id) -- oldest original on top
        eq(101, list[2].remote.gh_id)
        eq(9, list[3].id) -- newest draft reply at the bottom
    end)
end)
