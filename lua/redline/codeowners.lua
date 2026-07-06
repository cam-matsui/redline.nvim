---CODEOWNERS parsing and matching. GitHub picks the *last* matching rule for
---a path and assigns its owners; we replicate that so a PR review can be
---filtered to the files you own. Patterns follow gitignore syntax.
---
---Matching is done on path *segments* rather than a single translated Lua
---pattern: Lua patterns can't express "match whole segments" or optional
---`**` groups, which led to substring false positives (`bar.lua` matching
---`foobar.lua`) and `**` failing to match zero directories.

local M = {}

---@class redline.CodeownersRule
---@field pattern string original pattern text
---@field owners string[] @user, @org/team, or email
---@field segs string[] pattern split into segments, ready for glob matching

---Escape a literal run for use inside a Lua pattern.
local function escape(s)
    return (s:gsub('[%^%$%(%)%%%.%[%]%+%-]', '%%%1'))
end

---Does a single path segment match a single pattern segment? `*` matches any
---run within the segment, `?` a single char; neither crosses `/` (there are
---no slashes inside a segment).
---@param seg_pat string
---@param seg string
---@return boolean
local function seg_matches(seg_pat, seg)
    -- Fast path: a literal segment (very common) needs no pattern build.
    if not seg_pat:find('[*?]') then
        return seg_pat == seg
    end
    local out = {}
    for i = 1, #seg_pat do
        local ch = seg_pat:sub(i, i)
        if ch == '*' then
            out[#out + 1] = '[^/]*'
        elseif ch == '?' then
            out[#out + 1] = '[^/]'
        else
            out[#out + 1] = escape(ch)
        end
    end
    return seg:match('^' .. table.concat(out) .. '$') ~= nil
end

---Glob-match pattern segments against path segments, where `**` matches zero
---or more whole segments.
---@param pat string[]
---@param pi integer
---@param path string[]
---@param si integer
---@return boolean
local function glob(pat, pi, path, si)
    while pi <= #pat do
        if pat[pi] == '**' then
            -- Try consuming 0, 1, 2, … segments here.
            for k = si, #path + 1 do
                if glob(pat, pi + 1, path, k) then
                    return true
                end
            end
            return false
        end
        if si > #path or not seg_matches(pat[pi], path[si]) then
            return false
        end
        pi = pi + 1
        si = si + 1
    end
    return si > #path
end

---Parse CODEOWNERS text into ordered rules (comments/blank lines dropped).
---@param text string
---@return redline.CodeownersRule[]
function M.parse(text)
    local rules = {}
    for line in (text .. '\n'):gmatch('(.-)\n') do
        local trimmed = line:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed ~= '' and trimmed:sub(1, 1) ~= '#' then
            local fields = vim.split(trimmed, '%s+', { trimempty = true })
            local pattern = table.remove(fields, 1)

            local body = pattern:gsub('^/', ''):gsub('/$', '')
            -- A pattern with an internal/leading slash is anchored to the repo
            -- root; a bare name (no slash) floats and matches at any depth.
            local anchored = pattern:sub(1, 1) == '/' or body:find('/') ~= nil
            local segs = vim.split(body, '/', { plain = true, trimempty = true })
            if #segs > 0 then
                if not anchored then
                    table.insert(segs, 1, '**') -- match at any directory depth
                end
                -- A trailing `**` lets bare names and directory patterns
                -- (`docs/`) match the files beneath them; since `**` also
                -- matches zero segments, exact file patterns still match.
                table.insert(segs, '**')
                table.insert(rules, { pattern = pattern, owners = fields, segs = segs })
            end
        end
    end
    return rules
end

---Owners of a path per GitHub's last-match-wins rule.
---@param rules redline.CodeownersRule[]
---@param path string repo-relative
---@return string[] owners (empty if unowned)
function M.owners_of(rules, path)
    local path_segs = vim.split(path, '/', { plain = true, trimempty = true })
    local owners = {}
    for _, rule in ipairs(rules) do
        if glob(rule.segs, 1, path_segs, 1) then
            owners = rule.owners -- keep scanning; last match wins
        end
    end
    return owners
end

---Set of paths owned by `me` — matching the viewer's login or any of their
---team handles (case-insensitively; GitHub handles are case-insensitive).
---@param rules redline.CodeownersRule[]
---@param paths string[]
---@param me string[] handles that are "mine": '@login' and '@org/team' forms
---@return table<string, true>
function M.owned_by(rules, paths, me)
    local mine = {}
    for _, handle in ipairs(me) do
        mine[handle:lower()] = true
    end
    local result = {}
    for _, path in ipairs(paths) do
        for _, owner in ipairs(M.owners_of(rules, path)) do
            if mine[owner:lower()] then
                result[path] = true
                break
            end
        end
    end
    return result
end

return M
