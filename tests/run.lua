-- Minimal test harness, run with `nvim -l tests/run.lua` from the repo root.
-- Provides globals describe/it/eq; exits non-zero on any failure.

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local failures = {}
local total = 0
local current_group = ''

function describe(name, fn)
    current_group = name
    fn()
end

function it(name, fn)
    total = total + 1
    local label = current_group .. ' :: ' .. name
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        io.write('  ok  ', label, '\n')
    else
        io.write('FAIL  ', label, '\n', tostring(err), '\n')
        table.insert(failures, label)
    end
end

---Assert deep equality with a readable diff on failure.
function eq(expected, actual, msg)
    if not vim.deep_equal(expected, actual) then
        error(
            ('%sexpected:\n%s\nactual:\n%s'):format(
                msg and (msg .. '\n') or '',
                vim.inspect(expected),
                vim.inspect(actual)
            ),
            2
        )
    end
end

-- Resolve to absolute paths up front: tests may change the working directory.
local files = vim.tbl_map(function(f)
    return vim.fn.fnamemodify(f, ':p')
end, vim.fn.glob('tests/test_*.lua', false, true))
table.sort(files)
for _, file in ipairs(files) do
    dofile(file)
end

io.write(('\n%d tests, %d failures\n'):format(total, #failures))
os.exit(#failures == 0 and 0 or 1)
