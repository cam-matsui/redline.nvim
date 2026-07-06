---Unified-diff patch parsing. GitHub only accepts review comments on lines
---inside a diff hunk (context lines included), so before submitting we check
---every draft against the ranges declared by the @@ headers.

local M = {}

---@class redline.HunkRanges
---@field left { [1]: integer, [2]: integer }[] closed [start, end] line ranges on the old side
---@field right { [1]: integer, [2]: integer }[] closed [start, end] line ranges on the new side

---Parse the `patch` text from GitHub's PR files endpoint.
---@param patch string
---@return redline.HunkRanges
function M.ranges(patch)
    local result = { left = {}, right = {} }
    for header in patch:gmatch('@@[^@\n]*@@') do
        local a, b, c, d = header:match('@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@')
        if a then
            local astart, acount = tonumber(a), tonumber(b) or 1
            local cstart, ccount = tonumber(c), tonumber(d) or 1
            if acount > 0 then
                table.insert(result.left, { astart, astart + acount - 1 })
            end
            if ccount > 0 then
                table.insert(result.right, { cstart, cstart + ccount - 1 })
            end
        end
    end
    return result
end

---@param ranges { [1]: integer, [2]: integer }[]
---@param line integer
---@return boolean
function M.contains(ranges, line)
    for _, r in ipairs(ranges) do
        if line >= r[1] and line <= r[2] then
            return true
        end
    end
    return false
end

---Validate a comment against a file's hunk ranges.
---@param comment redline.Comment
---@param hunk_ranges redline.HunkRanges
---@return boolean ok
function M.comment_in_hunks(comment, hunk_ranges)
    local ranges = comment.side == 'LEFT' and hunk_ranges.left or hunk_ranges.right
    if not M.contains(ranges, comment.line) then
        return false
    end
    if comment.start_line then
        local start_ranges = (comment.start_side or comment.side) == 'LEFT' and hunk_ranges.left or hunk_ranges.right
        return M.contains(start_ranges, comment.start_line)
    end
    return true
end

return M
