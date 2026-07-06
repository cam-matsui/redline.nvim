---Review session lifecycle. One session at a time; `M.current` is the
---singleton. All UI redraws funnel through `M.redraw()` so renderers stay
---swappable.

local config = require('redline.config')

local M = {}

---@class redline.FileEntry
---@field path string repo-relative path (new path for renames)
---@field status string git status letter: A M D R (untracked files are A)
---@field old_path string|nil original path for renames
---@field additions integer
---@field deletions integer
---@field binary boolean|nil

---@class redline.PrInfo
---@field number integer
---@field title string
---@field owner string
---@field repo string
---@field base_oid string
---@field head_oid string
---@field url string
---@field author string|nil PR author's login (own PRs only allow COMMENT reviews)
---@field patches table<string, string> per-file unified diff text from the files endpoint

---@class redline.Session
---@field source redline.Source
---@field root string|nil absolute repo root; nil for a PR reviewed outside a clone
---@field files redline.FileEntry[]
---@field file_index integer 0 until the first file is shown
---@field comments redline.Comment[]
---@field next_comment_id integer
---@field layout table renderer-owned windows/buffers
---@field pr redline.PrInfo|nil set for PR sessions
---@field owned table<string, true>|nil paths the viewer owns via CODEOWNERS (nil = unknown / no CODEOWNERS)
---@field filter_owned boolean show only owned files in the panel
---@field head_snapshots table<string, string[]> RIGHT-side lines as last shown, for comment remapping

---@type redline.Session|nil
M.current = nil

local function renderer()
    return require('redline.render').get(config.get().view)
end

---True if the viewer owns at least one of the session's current files.
---@param session redline.Session
local function owns_any(session)
    if not session.owned then
        return false
    end
    for _, entry in ipairs(session.files) do
        if session.owned[entry.path] then
            return true
        end
    end
    return false
end

---(Re)compute CODEOWNERS ownership for the current file list, if the source
---supports it. Disables an owned-files filter that no longer selects anything.
---@param session redline.Session
local function compute_owned(session)
    if not session.source.owned then
        return
    end
    local paths = vim.tbl_map(function(f)
        return f.path
    end, session.files)
    session.source.owned(paths, function(owned)
        if M.current ~= session then
            return
        end
        session.owned = owned
        if session.filter_owned and not owns_any(session) then
            session.filter_owned = false
        end
        M.redraw()
    end)
end

---Count comments that would be lost if the session were discarded.
---@param session redline.Session
local function draft_count(session)
    local n = 0
    for _, c in ipairs(session.comments) do
        if c.state == 'draft' then
            n = n + 1
        end
    end
    return n
end

---Start a review session. Replaces any existing session (prompting if it has
---draft comments).
---@param source redline.Source
---@param root string
function M.start(source, root)
    if M.current then
        local drafts = draft_count(M.current)
        if drafts > 0 then
            local choice = vim.fn.confirm(
                ('Discard %d draft comment%s from the open review?'):format(drafts, drafts == 1 and '' or 's'),
                '&Discard\n&Cancel',
                2
            )
            if choice ~= 1 then
                return
            end
        end
        M.stop()
    end

    -- Fresh review: re-resolve the gh identity in case the account changed.
    require('redline.gh').reset_cache()

    ---@type redline.Session
    local session = {
        source = source,
        root = root,
        pr = source.pr,
        files = {},
        file_index = 0,
        comments = {},
        next_comment_id = 1,
        layout = {},
        owned = nil,
        filter_owned = false,
        head_snapshots = {},
    }
    M.current = session

    source.list_files(function(files)
        if M.current ~= session then
            return -- session was replaced while listing
        end
        if not files or #files == 0 then
            vim.notify('redline: nothing to review (' .. source.title .. ')', vim.log.levels.INFO)
            M.current = nil
            return
        end
        session.files = files
        renderer().open(session)
        M.goto_file(1)
        compute_owned(session)
        if source.threads then
            source.threads(function(remote_comments)
                if M.current ~= session or not remote_comments then
                    return
                end
                vim.list_extend(session.comments, remote_comments)
                M.redraw()
            end)
        end
    end)
end

---End the session and tear down its UI. Safe to call twice (window/tab
---close autocmds re-enter here).
function M.stop()
    local session = M.current
    if not session then
        return
    end
    M.current = nil
    renderer().close(session)
end

---Show files[i] in the diff view. Wraps around at both ends.
---@param i integer
---@param cb? fun() called once the file is on screen
function M.goto_file(i, cb)
    local session = M.current
    if not session or #session.files == 0 then
        return
    end
    i = ((i - 1) % #session.files) + 1
    session.file_index = i
    local entry = session.files[i]
    session.source.get_content(entry, function(base, head)
        if M.current ~= session or session.file_index ~= i then
            return -- user moved on while content was loading
        end
        session.head_snapshots[entry.path] = head and vim.deepcopy(head) or nil
        renderer().show_file(session, entry, base, head)
        M.redraw()
        if cb then
            cb()
        end
    end)
end

---Absolute indices into `session.files` currently shown in the panel. When
---the owned-files filter is on, only files the viewer owns are visible (but if
---that would hide everything, the filter is treated as inactive so the panel
---is never empty).
---@param session redline.Session
---@return integer[]
local function visible_list(session)
    local out = {}
    local filtering = session.filter_owned and session.owned ~= nil
    for i, entry in ipairs(session.files) do
        if not filtering or session.owned[entry.path] then
            table.insert(out, i)
        end
    end
    if #out == 0 then
        -- Never present an empty panel; fall back to showing everything.
        for i = 1, #session.files do
            out[i] = i
        end
    end
    return out
end
M.visible_indices = visible_list

---Move to the next/prev file within the currently visible (filtered) set.
---@param delta 1|-1
local function step_file(delta)
    local session = M.current
    if not session then
        return
    end
    local vis = visible_list(session)
    local pos = 1
    for k, idx in ipairs(vis) do
        if idx == session.file_index then
            pos = k
            break
        end
    end
    local next_pos = ((pos - 1 + delta) % #vis) + 1
    M.goto_file(vis[next_pos])
end

function M.next_file()
    step_file(1)
end

function M.prev_file()
    step_file(-1)
end

---Turn the owned-files filter on/off (`nil` toggles). Jumps to the first
---visible file if the current one is filtered out.
---@param on boolean|nil
function M.set_filter_owned(on)
    local session = M.current
    if not session then
        return
    end
    if session.owned == nil then
        vim.notify('redline: no CODEOWNERS ownership info for this review', vim.log.levels.INFO)
        return
    end
    if on == nil then
        on = not session.filter_owned
    end
    if on and not owns_any(session) then
        vim.notify('redline: you own none of these files', vim.log.levels.INFO)
        return
    end
    session.filter_owned = on
    local vis = visible_list(session)
    if not vim.list_contains(vis, session.file_index) then
        M.goto_file(vis[1])
    else
        M.redraw()
    end
end

---Re-read the source: file list, current file content, and comment anchors
---(comments whose lines changed underneath them are remapped or flagged
---outdated). Use after the working tree changed mid-review.
function M.refresh()
    local session = M.current
    if not session then
        return
    end
    session.source.list_files(function(files)
        if M.current ~= session then
            return
        end
        if not files or #files == 0 then
            vim.notify('redline: nothing left to review', vim.log.levels.INFO)
            M.stop()
            return
        end
        local current_path = session.files[session.file_index] and session.files[session.file_index].path
        session.files = files
        compute_owned(session) -- file set may have changed; refresh ownership
        require('redline.comments').remap(session, function()
            if M.current ~= session then
                return
            end
            local index = 1
            for idx, entry in ipairs(files) do
                if entry.path == current_path then
                    index = idx
                    break
                end
            end
            M.goto_file(index)
        end)
    end)
end

---Redraw everything derived from session state (panel, comment marks,
---threads) without re-reading file contents.
function M.redraw()
    local session = M.current
    if not session then
        return
    end
    require('redline.ui.panel').render(session)
    require('redline.comments').decorate(session)
end

return M
