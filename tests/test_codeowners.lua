-- CODEOWNERS parsing and last-match-wins ownership resolution.

local co = require('redline.codeowners')

local SAMPLE = [[
# comment
*           @global-owner

/docs/      @docs-team
*.lua       @lua-owner
/lua/redline/gh.lua  @gh-owner @lua-owner
lib/**      @lib-team
build/                @ci
]]

describe('codeowners.parse', function()
    it('drops comments and blank lines, keeps order', function()
        local rules = co.parse(SAMPLE)
        eq(6, #rules)
        eq('*', rules[1].pattern)
        eq({ '@global-owner' }, rules[1].owners)
    end)

    it('captures multiple owners on a rule', function()
        local rules = co.parse(SAMPLE)
        eq({ '@gh-owner', '@lua-owner' }, rules[4].owners)
    end)
end)

describe('codeowners.owners_of', function()
    local rules = co.parse(SAMPLE)

    it('falls back to a catch-all rule', function()
        eq({ '@global-owner' }, co.owners_of(rules, 'README.md'))
    end)

    it('lets a later rule win over an earlier match', function()
        -- both `*` and `*.lua` match; `*.lua` comes later
        eq({ '@lua-owner' }, co.owners_of(rules, 'foo/bar.lua'))
    end)

    it('honors an anchored exact path over a glob', function()
        eq({ '@gh-owner', '@lua-owner' }, co.owners_of(rules, 'lua/redline/gh.lua'))
    end)

    it('matches a trailing-slash directory rule at any depth', function()
        eq({ '@docs-team' }, co.owners_of(rules, 'docs/guide/intro.md'))
    end)

    it('matches ** across path segments', function()
        eq({ '@lib-team' }, co.owners_of(rules, 'lib/a/b/c.js'))
    end)

    it('matches a bare directory name as a prefix', function()
        eq({ '@ci' }, co.owners_of(rules, 'build/output.tar'))
    end)

    it('returns empty for an unmatched anchored pattern', function()
        local r = co.parse('/only/here @x')
        eq({}, co.owners_of(r, 'somewhere/else.txt'))
    end)

    it('does not match a pattern as a substring of a segment', function()
        eq({}, co.owners_of(co.parse('bar.lua @x'), 'foobar.lua'))
        eq({}, co.owners_of(co.parse('foo @x'), 'food.txt'))
        eq({ '@x' }, co.owners_of(co.parse('bar.lua @x'), 'bar.lua'))
        eq({ '@x' }, co.owners_of(co.parse('bar.lua @x'), 'a/b/bar.lua'))
    end)

    it('matches a bare name as a directory at any depth', function()
        local r = co.parse('docs @x')
        eq({ '@x' }, co.owners_of(r, 'docs/readme.md'))
        eq({ '@x' }, co.owners_of(r, 'a/docs/readme.md'))
        eq({}, co.owners_of(r, 'mydocs/readme.md'))
    end)

    it('lets ** match zero directories', function()
        eq({ '@x' }, co.owners_of(co.parse('a/**/b.txt @x'), 'a/b.txt'))
        eq({ '@x' }, co.owners_of(co.parse('a/**/b.txt @x'), 'a/x/y/b.txt'))
        eq({}, co.owners_of(co.parse('a/**/b.txt @x'), 'a/x/zzb.txt'))
    end)

    it('matches a leading **/ at the repo root', function()
        local r = co.parse('**/foo.txt @x')
        eq({ '@x' }, co.owners_of(r, 'foo.txt'))
        eq({ '@x' }, co.owners_of(r, 'a/b/foo.txt'))
    end)

    it('matches a trailing /** for everything beneath', function()
        local r = co.parse('app/** @x')
        eq({ '@x' }, co.owners_of(r, 'app/main.lua'))
        eq({ '@x' }, co.owners_of(r, 'app/a/b.lua'))
        eq({}, co.owners_of(r, 'apple/main.lua'))
    end)
end)

describe('codeowners.owned_by', function()
    local rules = co.parse(SAMPLE)
    local paths = { 'README.md', 'foo/bar.lua', 'lua/redline/gh.lua', 'docs/x.md' }

    it('selects files owned by the viewer login', function()
        local owned = co.owned_by(rules, paths, { '@lua-owner' })
        eq(true, owned['foo/bar.lua'])
        eq(true, owned['lua/redline/gh.lua'])
        eq(nil, owned['README.md'])
        eq(nil, owned['docs/x.md'])
    end)

    it('matches team handles too, case-insensitively', function()
        local owned = co.owned_by(rules, paths, { '@Docs-Team' })
        eq(true, owned['docs/x.md'])
        eq(nil, owned['foo/bar.lua'])
    end)
end)
