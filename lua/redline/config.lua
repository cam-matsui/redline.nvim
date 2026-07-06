---Plugin configuration: defaults, validation, and access.

local M = {}

---@class redline.KeymapConfig
---@field enabled boolean set to false to define all mappings yourself via <Plug>
---@field comment string
---@field suggest string
---@field edit string
---@field delete string
---@field reply string
---@field next_comment string
---@field prev_comment string
---@field next_file string
---@field prev_file string
---@field open_file string
---@field export string
---@field submit string
---@field refresh string
---@field filter_owned string toggle the "files owned by me" filter (PR reviews)
---@field overview string open the PR overview screen (PR reviews)
---@field close string

---@class redline.Config
---@field view 'split' renderer to use ('unified' is reserved for a future release)
---@field default_base string|nil base ref for `:Review branch`; nil auto-detects origin/HEAD
---@field panel { position: 'left'|'right', width: integer }
---@field keymaps redline.KeymapConfig buffer-local mappings, only set in review buffers
---@field export { destination: 'buffer'|'register'|string, preamble: boolean } where `:Review export` writes (a relative file path resolves against the repo root); `preamble` prepends agent-facing instructions
---@field auto_refresh boolean re-read the working tree when Neovim regains focus (agent-review loop)
---@field gh { cmd: string } gh CLI executable
---@field signs { comment: string } sign-column marker for commented lines

---@type redline.Config
local defaults = {
    view = 'split',
    default_base = nil,
    panel = { position = 'left', width = 35 },
    keymaps = {
        enabled = true,
        comment = 'cc',
        suggest = 'cs',
        edit = 'ce',
        delete = 'cd',
        reply = 'cr',
        next_comment = ']C',
        prev_comment = '[C',
        next_file = ']f',
        prev_file = '[f',
        open_file = 'go',
        export = 'X',
        submit = 'S',
        refresh = 'R',
        filter_owned = 'O',
        overview = 'P',
        close = 'q',
    },
    export = { destination = 'buffer', preamble = true },
    auto_refresh = false,
    gh = { cmd = 'gh' },
    signs = { comment = '┃' },
}

---@type redline.Config
local options = vim.deepcopy(defaults)

---Warn about keys the user set that redline doesn't recognize, at every level
---that has a fixed schema — so a typo like `keymap`/`export.destinaton` is
---surfaced instead of silently ignored. Tables without a fixed schema (none
---here) would be skipped by passing a nil reference.
---@param user table
---@param reference table the corresponding defaults subtree
---@param prefix string dotted path for messages
local function warn_unknown(user, reference, prefix)
    if type(user) ~= 'table' then
        return
    end
    for key, value in pairs(user) do
        if reference[key] == nil then
            vim.notify(
                ('redline: unknown config option %q — ignored (typo?)'):format(prefix .. key),
                vim.log.levels.WARN
            )
        elseif type(value) == 'table' and type(reference[key]) == 'table' then
            warn_unknown(value, reference[key], prefix .. key .. '.')
        end
    end
end

---Merge user options over defaults. Safe to call more than once.
---@param opts? table
function M.setup(opts)
    warn_unknown(opts or {}, defaults, '')
    options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
    vim.validate('view', options.view, function(v)
        return require('redline.render').renderers[v] ~= nil
    end, "a registered renderer ('split')")
    vim.validate('panel.width', options.panel.width, 'number')
    vim.validate('export.destination', options.export.destination, 'string')
    vim.validate('export.preamble', options.export.preamble, 'boolean')
    vim.validate('auto_refresh', options.auto_refresh, 'boolean')
    vim.validate('keymaps.enabled', options.keymaps.enabled, 'boolean')
    vim.validate('gh.cmd', options.gh.cmd, 'string')
end

---@return redline.Config
function M.get()
    return options
end

return M
