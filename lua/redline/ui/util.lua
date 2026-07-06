---Shared text helpers for the floating UIs (comment cards, PR overview).
---Everything here is display-width aware so box borders line up even with
---wide (CJK/emoji) characters.

local M = {}

---Split a string into its characters (grapheme-ish, one Lua string per char).
local function chars(s)
    return vim.fn.split(s, '\\zs')
end

---First `width` display-cells worth of `s` (a byte-prefix of `s`).
---@return string
local function take(s, width)
    local out, w = '', 0
    for _, c in ipairs(chars(s)) do
        local cw = vim.fn.strdisplaywidth(c)
        if w + cw > width then
            break
        end
        out = out .. c
        w = w + cw
    end
    return out
end

---Truncate `s` to `width` display cells, marking the cut with `…`.
---@param s string
---@param width integer
---@return string
function M.truncate(s, width)
    if vim.fn.strdisplaywidth(s) <= width then
        return s
    end
    return take(s, math.max(0, width - 1)) .. '…'
end

---Truncate to `width`, then right-pad with spaces to exactly `width` cells.
---@param s string
---@param width integer
---@return string
function M.pad(s, width)
    s = M.truncate(s, width)
    return s .. (' '):rep(math.max(0, width - vim.fn.strdisplaywidth(s)))
end

---Word-wrap a single paragraph (no newlines) to `width`. Words longer than
---`width` are hard-broken across lines rather than truncated, so long tokens
---like URLs stay fully readable.
---@param text string
---@param width integer
---@return string[]
function M.wrap_line(text, width)
    local out, line = {}, ''
    local function flush()
        if line ~= '' then
            out[#out + 1] = line
            line = ''
        end
    end
    for word in text:gmatch('%S+') do
        while vim.fn.strdisplaywidth(word) > width do
            flush()
            local head = take(word, width)
            if head == '' then
                break -- width too small to make progress; avoid an infinite loop
            end
            out[#out + 1] = head
            word = word:sub(#head + 1)
        end
        if line == '' then
            line = word
        elseif vim.fn.strdisplaywidth(line .. ' ' .. word) <= width then
            line = line .. ' ' .. word
        else
            flush()
            line = word
        end
    end
    flush()
    if #out == 0 then
        out = { '' }
    end
    return out
end

---@class redline.WrappedLine
---@field text string
---@field kind 'prose'|'fence'|'code'

---Wrap markdown text to `width`, preserving fenced code blocks (```) verbatim
---so indentation and spacing survive; prose is word-wrapped. Fenced lines are
---truncated (not reflowed) and tagged so callers can highlight them.
---@param text string
---@param width integer
---@return redline.WrappedLine[]
function M.wrap_markdown(text, width)
    local out = {}
    local in_fence = false
    for _, raw in ipairs(vim.split((text or ''):gsub('\r', ''), '\n', { plain = true })) do
        if raw:match('^%s*```') then
            out[#out + 1] = { text = M.truncate(raw, width), kind = 'fence' }
            in_fence = not in_fence
        elseif in_fence then
            out[#out + 1] = { text = M.truncate(raw, width), kind = 'code' }
        elseif raw == '' then
            out[#out + 1] = { text = '', kind = 'prose' }
        else
            for _, wl in ipairs(M.wrap_line(raw, width)) do
                out[#out + 1] = { text = wl, kind = 'prose' }
            end
        end
    end
    return out
end

return M
