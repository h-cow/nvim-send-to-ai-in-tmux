# Neovim Send-to-AI Plugin Brainstorm

**Date:** 2026-02-16
**Status:** Approved for planning

## What We're Building-16-nvim-send-to-ai-brainstorm.md

A Neovim plugin that sends code snippets or file locations from Neovim to AI tools (Claude Code, Codex, OpenCode) running in tmux panes. The plugin:

- **Sends highlighted code** with file path and line range context
- **Sends current line** location when nothing is highlighted
- **Auto-detects AI panes** by looking for specific process names in tmux
- **Falls back to clipboard** if no AI pane is found
- **Works in DiffviewOpen** and all Neovim contexts
- **Zero-config** with sensible defaults, extensible via lazy.nvim

### User Experience

```lua
-- In lazy.nvim config
{
  'openclaw/nvim-send-to-ai-in-tmux',
  cmd = 'SendToAI',
  keys = {
    { '<leader>ai', '<cmd>SendToAI<cr>', mode = { 'n', 'v' }, desc = 'Send to AI' }
  }
}
```

**In normal mode:** `<leader>ai` sends `src/main.lua:42` to AI pane
**In visual mode:** `<leader>ai` sends:
```
src/main.lua:42-45
function hello()
  print("world")
end
```

## Why This Approach

### Approach: Pure Lua with Tmux Shell Interface

We chose a **balanced architecture** that uses clean Lua modules for logic while delegating tmux interaction to shell commands.

**Key benefits:**
- **Testable:** Logic separated from I/O operations
- **Simple:** No async complexity for operations that complete in <100ms
- **Maintainable:** Clear module boundaries for future enhancements
- **Proven pattern:** Follows Neovim plugin best practices

**Structure:**
```
lua/send-to-ai/
├── init.lua       # Public API and setup()
├── config.lua     # Configuration defaults
├── tmux.lua       # Tmux pane detection and sending
└── format.lua     # Message formatting logic

plugin/send-to-ai.lua  # Command definitions
```

### Alternative Approaches Considered

**Shell-Heavy (~150 lines):** Too brittle for production use. String escaping and error handling difficult with inline shell commands.

**Async Job-Based (~500+ lines):** Overkill for this use case. The operations are fast enough that blocking is imperceptible, and the added complexity isn't justified.

## Key Decisions

### 1. AI Pane Detection Strategy

**Decision:** Scan tmux pane processes for specific names.

**How it works:**
1. Run `tmux list-panes -a -F "#{pane_id}:#{pane_current_command}"`
2. Search output for processes matching: `claude`, `codex`, `opencode`
3. Prefer panes in current session, then fall back to other sessions
4. Cache the found pane ID (until tmux session changes)

**Why:** Automatic detection provides zero-config experience. Process name matching is reliable since AI CLI tools have distinct names.

### 2. Message Format

**Decision:** Send plain text in format: `path/to/file:line-range\n<code>`

**Examples:**
- Highlighted code: `src/main.lua:42-45\n<code block>`
- Single line: `src/main.lua:42`

**Why:** Simple format that AI tools can naturally interpret. No special commands needed - just paste context directly into the REPL.

### 3. Path Resolution

**Decision:** Use path relative to git root when in a repository.

**Implementation:**
1. Find nearest `.git` directory walking up from current file
2. Make path relative to that directory
3. Fall back to filename only if not in git repo

**Why:** Git-relative paths help AI understand project structure. Most codebases are in git, and AI tools work best with project-relative paths.

### 4. Fallback Strategy

**Decision:** Copy to system clipboard if no AI pane found.

**Implementation:**
- Check for `pbcopy` (macOS), `xclip` (Linux), `clip.exe` (WSL)
- Show notification: "No AI pane found. Copied to clipboard."
- User can manually paste wherever needed

**Why:** Graceful degradation. Plugin remains useful even when tmux/AI setup isn't available.

### 5. Keybinding Strategy

**Decision:** Provide `:SendToAI` command, let user set keybinding via lazy.nvim.

**Rationale:**
- Avoids keybinding conflicts
- Follows Neovim convention (plugins provide commands, users set keys)
- README shows recommended binding: `<leader>ai`

**Why:** Respects user's keybinding preferences while providing clear guidance.

### 6. DiffviewOpen Compatibility

**Decision:** Use visual selection marks (`'<` and `'>`) instead of visual mode API.

**Implementation:**
```lua
local start_line = vim.fn.getpos("'<")[2]
local end_line = vim.fn.getpos("'>")[2]
```

**Why:** Works in any buffer type, including Diffview buffers. More robust than checking visual mode state.

### 7. Configuration Approach

**Decision:** Zero-config with optional `setup()` for customization.

**Default behavior:**
- Auto-detect AI panes (claude, codex, opencode)
- Use clipboard fallback
- Git-relative paths
- No default keybindings

**Customizable options:**
```lua
require('send-to-ai').setup({
  ai_processes = { 'claude', 'codex', 'opencode', 'aider' },
  prefer_session = true,  -- Prefer current tmux session
  fallback_clipboard = true,
  path_style = 'git_relative'  -- or 'cwd_relative', 'absolute'
})
```

**Why:** Works immediately for common case, extensible for power users.

## Out of Scope

These features are **explicitly not included** in the initial version:

### Not Doing Now

- **Custom message templates:** Just using simple `path:lines\n<code>` format
- **Per-AI-tool formatting:** All tools receive the same format
- **Async/non-blocking I/O:** Operations are fast enough (<100ms)
- **Tmux event watching:** Not monitoring pane lifecycle
- **Multi-pane sending:** Only sends to one AI pane at a time
- **History/logging:** Not tracking what was sent
- **Response capture:** One-way communication only

### Might Add Later

- **Target pane selection UI:** If auto-detection isn't sufficient
- **Health check command:** `:checkhealth send-to-ai`
- **More AI tool names:** User-configurable process list
- **Send entire file:** Command to send whole buffer
- **Send motion/text-object:** Operator mode like `<leader>aip` (send paragraph)

### Won't Do

- **Two-way communication:** This is a one-way sender, not an AI client
- **Inline AI responses:** Use proper AI tool integration for that
- **Start AI tools automatically:** User manages their own tmux setup

## Technical Details

### Tmux Commands Used

**List panes with processes:**
```bash
tmux list-panes -a -F "#{pane_id}:#{pane_current_command}"
# Output: %0:zsh %1:nvim %2:claude
```

**Send text to pane:**
```bash
tmux send-keys -t %2 -l "<text>"
tmux send-keys -t %2 Enter
```

**Current session check:**
```bash
tmux display-message -p "#{session_name}"
```

### Neovim APIs Used

**Get visual selection:**
```lua
local start_pos = vim.fn.getpos("'<")
local end_pos = vim.fn.getpos("'>")
local lines = vim.fn.getline(start_pos[2], end_pos[2])
```

**Get current file and line:**
```lua
local bufnr = vim.api.nvim_get_current_buf()
local filepath = vim.api.nvim_buf_get_name(bufnr)
local line = vim.fn.line('.')
```

**Find git root:**
```lua
local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
local rel_path = vim.fn.fnamemodify(filepath, ':.' .. git_root)
```

### Character Escaping

**For tmux send-keys:**
- Use `-l` flag for literal mode (no key name interpretation)
- Escape shell special characters: `\`, `"`, `$`, `'`
- Use separate `send-keys Enter` for newline

## Open Questions

### Resolved ✓

All questions were resolved during brainstorming.

### New Questions for Implementation

1. **Caching strategy:** How long should we cache the detected AI pane ID?
   → *Suggestion: Cache until tmux session changes (detect via session ID)*

2. **Error notification style:** Use `vim.notify()` or `echo`?
   → *Suggestion: `vim.notify()` for better UI integration*

3. **Process name matching:** Exact match or substring?
   → *Suggestion: Substring match for flexibility (e.g., "claude-code-cli")*

4. **Multiple AI panes:** What if multiple are found?
   → *Suggestion: Use first found, add config option for priority order*

## Success Criteria

The plugin will be successful when:

1. **It just works:** Install with lazy.nvim, add keybinding, start using
2. **Reliable detection:** Finds AI panes correctly 95%+ of the time
3. **Fast:** Operations complete in <100ms (imperceptible delay)
4. **DiffviewOpen compatible:** Works in all vim contexts, including diff views
5. **Graceful fallback:** Clipboard fallback works when no pane found
6. **Clear documentation:** README explains installation and usage in <5 minutes

## Next Steps

Ready for planning phase:

1. Create file structure (`init.lua`, `config.lua`, `tmux.lua`, `format.lua`)
2. Implement tmux pane detection logic
3. Implement message formatting with git-relative paths
4. Add clipboard fallback
5. Create `:SendToAI` command with mode detection
6. Write README with lazy.nvim installation example
7. Test in normal buffers and during `:DiffviewOpen`

---

**Ready to proceed:** Run `/workflows:plan` to create implementation plan.
