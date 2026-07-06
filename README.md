# redline.nvim

[![CI](https://github.com/cam-matsui/redline.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/cam-matsui/redline.nvim/actions/workflows/ci.yml)
[![Neovim](https://img.shields.io/badge/Neovim-0.11%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Code review inside Neovim — for agent diffs and GitHub PRs, with one comment
model.

Two workflows share the same review surface:

1. **Local review** — open the working tree (or a branch) as a review: `:Review`
   shows every changed file as a side-by-side native diff. Add inline comments
   and suggested changes, then `:Review export` renders them as GitHub-style
   markdown you can hand straight to Claude Code (or any coding agent) to act on.
2. **GitHub PR review** — `:Review pr 123` browses a PR's diffs with existing
   review threads inline. Comment, suggest, reply, then `:Review submit` to
   approve / request changes / comment — all through the `gh` CLI.

Comments use GitHub's review-comment schema natively (`path`, `line`, `side`,
`start_line`, `body` with ` ```suggestion ` fences), so a local export and a PR
submission are literally the same data.

**Why not an existing plugin?** [octo.nvim](https://github.com/pwntester/octo.nvim)
and friends are full GitHub clients; [diffview.nvim](https://github.com/sindrets/diffview.nvim)
views diffs but has no comment layer; agent-integration plugins gate edits at
proposal time without comments. redline is the minimal review loop across both:
diff → annotate → export or submit.

## Requirements

- Neovim **0.11+**
- `git`
- [`gh` CLI](https://cli.github.com), authenticated (`gh auth login`) — PR review only
- No plugin dependencies

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return { 'cam-matsui/redline.nvim', opts = {} }
```

Developing locally:

```lua
return { 'cam-matsui/redline.nvim', dir = '~/dev/redline.nvim', opts = {} }
```

`setup()`/`opts` is optional — `:Review` works with defaults.

## Quickstart

```
:Review              " review working tree vs HEAD (what did the agent change?)
:Review branch main  " review everything this branch changes vs merge-base(main)
:Review pr           " pick an open PR to review (or :Review pr 123)
:Review pr https://github.com/owner/repo/pull/123   " any PR, from anywhere
:Review requests     " pick from PRs across GitHub that await your review
```

In the review tab: `cc` comments on the cursor line or visual selection,
`cs` turns a visual selection into a suggested change, `X` exports the review,
`S` submits it (PR reviews). `q` closes.

## Reviewing an agent's changes

redline's local review is built for the Claude Code / OpenCode loop: the agent
edits files and leaves them **uncommitted**, and `:Review` (working tree vs
HEAD) is exactly "what did the agent just change".

The tightest loop, configured once:

```lua
opts = {
  export = { destination = '.redline/review.md', preamble = true },
  auto_refresh = true,
}
```

Then per review:

1. The agent makes changes and leaves them uncommitted.
2. `:Review` — side-by-side diff of everything that changed, with a file panel.
3. Comment (`cc`), suggest exact replacements (`cs` on a visual selection),
   move around (`]f`/`[f` files, `]C`/`[C` comments).
4. `:Review export` writes `.redline/review.md` (repo-root-relative, and
   gitignored — see below). With `preamble = true` the file opens with a short
   instruction block, so it's self-contained.
5. Tell the agent: *"apply the review in `.redline/review.md`"*. Each
   ` ```suggestion ` block is an exact replacement for the referenced lines.
6. The agent edits again. When you switch back to Neovim, `auto_refresh` re-reads
   the working tree — the diff updates and your still-open draft comments
   re-anchor to lines that moved. Back to step 3.

Keep review files out of git globally by adding `.redline/` to
`~/.config/git/ignore` (git's default global ignore file), so it applies in
every repo you review in without touching each project's `.gitignore`.

## Commands

All functionality is under one command, `:Review [subcommand]`:

| Subcommand | Action |
|---|---|
| *(none)* | review working tree vs HEAD |
| `branch [ref]` | review vs merge-base with `ref` (default: `default_base` or origin's default branch) |
| `pr [n \| url]` | review a GitHub PR: a number/picker for the repo you're in, or any PR by URL from anywhere |
| `requests` | pick from all open PRs (any repo) that request you as a reviewer |
| `comment` | comment at cursor (or on a `:'<,'>` range) |
| `suggest` | suggested change from a visual range |
| `edit` / `delete` | edit / delete the draft comment under the cursor |
| `reply` | reply to the PR thread under the cursor |
| `next` / `prev` | jump between comments (crosses files) |
| `list` | pick from all draft comments |
| `export [path]` | export review as markdown (buffer by default) |
| `submit` | submit the PR review (approve / request changes / comment) |
| `refresh` | re-read the source; comment anchors follow moved lines |
| `overview` | PR summary: state, description, CI checks, commits, conversation (PR reviews) |
| `files` | focus the file panel |
| `mine` | toggle a filter to only the files you own via CODEOWNERS (PR reviews) |
| `toggle-threads` | collapse/expand inline comment display |
| `close` | end the review |

## Default keymaps

Buffer-local, only inside review buffers. Disable with
`keymaps = { enabled = false }` and map the `<Plug>(Review*)` targets yourself.

| Keys | Action |
|---|---|
| `cc` | comment (line or visual range) |
| `cs` | suggest change (visual range) |
| `ce` / `cd` / `cr` | edit / delete / reply to comment under cursor |
| `]C` / `[C` | next / previous comment |
| `]f` / `[f` | next / previous file |
| `]c` / `[c` | next / previous diff hunk (built-in diff mode) |
| `go` | open the real file at the cursor line |
| `X` | export review |
| `S` | submit PR review |
| `R` | refresh |
| `O` | toggle "files owned by me" filter (PR reviews) |
| `P` | open the PR overview screen (PR reviews) |
| `q` | close review |
| `<CR>` (panel) | open file under cursor |

In the comment input float: `<C-s>` (or `<CR>` in normal mode) confirms,
`q` or `<Esc><Esc>` cancels. A single `<Esc>` only leaves insert mode, so it
never discards what you were writing.

**Editing and replying.** Put the cursor on a commented line (the `┃` sign):
`ce` reopens your draft in the input float, `cd` deletes it, and in PR reviews
`cr` replies to the GitHub thread under the cursor. `:Review list` picks any
draft to jump back to.

**Seeing the whole file.** The diff buffers always contain the full file —
Neovim's diff mode just folds unchanged regions. Standard fold keys apply:
`zo`/`zc` open/close a fold, `zR` opens all (whole file visible), `zM` refolds.
More context around changes: `:set diffopt+=context:12` (default 6).

## Configuration

Defaults shown:

```lua
require('redline').setup({
    view = 'split',            -- side-by-side native diff (only renderer today)
    default_base = nil,        -- base ref for :Review branch; nil auto-detects origin/HEAD
    panel = { position = 'left', width = 35 },
    keymaps = {
        enabled = true,        -- false: no default maps, use <Plug>(Review*) targets
        comment = 'cc', suggest = 'cs', edit = 'ce', delete = 'cd', reply = 'cr',
        next_comment = ']C', prev_comment = '[C',
        next_file = ']f', prev_file = '[f',
        open_file = 'go', export = 'X', submit = 'S', refresh = 'R',
        filter_owned = 'O', overview = 'P', close = 'q',
    },
    export = {
        destination = 'buffer',  -- 'buffer' | 'register' | a file path
                                 -- (a relative path resolves against the repo root)
        preamble = true,         -- prepend agent-facing instructions to the export
    },
    auto_refresh = false,        -- re-read the working tree when nvim regains focus
    gh = { cmd = 'gh' },
    signs = { comment = '┃' },
})
```

Tip: `:set diffopt+=linematch:60` markedly improves diff alignment; redline
never mutates your `diffopt`.

## Export format

`:Review export` emits deterministic markdown that mirrors GitHub's
review-comment fields — stable, so agents and tools can rely on it:

````markdown
# Code review: worktree vs HEAD — 2026-07-05

## `lua/foo/bar.lua`

### `lua/foo/bar.lua:42` (RIGHT)

This helper duplicates `util.trim`; reuse it.

### `lua/foo/bar.lua:10-14` (RIGHT)

```suggestion
local ok, err = pcall(load_config)
if not ok then
    return nil, err
end
```
````

- One `##` section per file, in review order; one `###` per comment.
- The heading is `path:line` (or `path:start-end` for ranges) plus the diff
  side: `RIGHT` = new code, `LEFT` = base/deleted code.
- Suggestion bodies keep their ` ```suggestion ` fence — GitHub's own format
  for proposed replacements of exactly the referenced lines.
- Comments whose code changed underneath them are marked with a
  `> outdated` blockquote.

A typical agent loop: review Claude Code's changes, `:Review export`, and tell
Claude to *"apply the review in the export buffer"*.

## Health

`:checkhealth redline` verifies the Neovim version, git, gh, and auth status.

## License

MIT
