---Renderer registry. A renderer owns the session's windows/buffers and
---implements:
---
---  open(session)                        create the tab/window layout
---  show_file(session, entry, base, head) populate the view for one file
---  close(session)                       tear the layout down
---  target_buf(session, side)            buffer comments anchor to per side
---
---Only 'split' (side-by-side native diff) ships today; 'unified' is reserved.

local M = {}

M.renderers = {
    split = 'redline.render.split',
}

---@param name string
function M.get(name)
    local mod = M.renderers[name]
    if not mod then
        error(('redline: unknown renderer %q'):format(name))
    end
    return require(mod)
end

return M
