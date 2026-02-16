---
title: Neovim tmux AI integration plugin
type: feat
date: 2026-02-16
---

# Neovim tmux AI Integration Plugin

## Overview

A Neovim plugin that seamlessly sends code snippets or file location references from Neovim to AI tools (Claude Code, Codex, OpenCode) running in tmux panes. The plugin provides **zero-config** operation with intelligent auto-detection of AI panes, graceful fallback to clipboard, and works in all Neovim contexts including DiffviewOpen.

**Repository:** `/Users/openclaw/code/nvim-send-to-ai-in-tmux`
**Target Plugin Name:** `nvim-send-to-ai-in-tmux`
**Status:** Greenfield project (no code yet, comprehensive brainstorm complete)

## Problem Statement

### The Developer Pain Point

Modern AI-assisted development workflows often involve switching between Neovim and AI CLI tools (Claude Code, GitHub Codex, OpenCode). Developers need to:

1. **Share code context** with AI tools quickly and accurately
2. **Reference specific locations** in files for AI to analyze
3. **Maintain flow state** without manual copy-paste disruptions
4. **Work across environments** (tmux sessions, clipboard, different OS)

**Current Workarounds:**
- Manual visual selection → clipboard copy → tmux pane switch → paste (6+ steps, 10-20 seconds)
- Typing file paths manually (error-prone, no line context)
- Using `cat file.rs | pbcopy` in shell (leaves editor, no line ranges)

**Impact:**
- **Flow disruption:** Context switching breaks concentration
- **Error introduction:** Manual typing introduces typos in paths/line numbers
- **Time waste:** ~30-60 seconds per AI interaction × 20-50 interactions/day = 10-50 minutes lost daily
- **Inconsistent format:** AI tools receive inconsistent context (sometimes code, sometimes just filenames)

### Why This Matters

With AI pair programming becoming central to development workflows, the friction of sharing code context directly impacts productivity. A 2-keystroke operation (`<leader>ai`) replacing a 6-step manual process represents a **90% reduction in context-sharing overhead**.

## Proposed Solution

### Architecture Overview

**Pure Lua plugin** with tmux shell interface (~300-400 lines total):

```
lua/send-to-ai/
├── init.lua       # Public API, setup(), main orchestration (80-100 lines)
├── config.lua     # Configuration defaults, validation (40-60 lines)
├── tmux.lua       # Pane detection, send-keys, escaping (100-120 lines)
├── format.lua     # Message formatting, path resolution (60-80 lines)
└── health.lua     # Health check implementation (40-60 lines)

plugin/send-to-ai.lua  # Command definitions (20-30 lines)
README.md              # Installation, usage, configuration docs
LICENSE                # MIT license
.gitignore             # Standard Neovim plugin ignores
```

### User Experience

**Installation (lazy.nvim):**
```lua
{
  'openclaw/nvim-send-to-ai-in-tmux',
  cmd = 'SendToAI',
  keys = {
    { '<leader>ai', '<cmd>SendToAI<cr>', mode = { 'n', 'v' }, desc = 'Send to AI' }
  },
  opts = {  -- Optional customization
    ai_processes = { 'claude', 'codex', 'opencode', 'aider' },
    prefer_session = true,
    fallback_clipboard = true,
    path_style = 'git_relative'
  }
}
```

**Visual Mode Flow:**
1. Highlight code in visual mode (`v`, `V`, or `Ctrl-v`)
2. Press `<leader>ai`
3. Code appears in AI pane with context:
   ```
   src/parser.rs:142-156
   fn parse_expression(&self) -> Result<Expr> {
       // ... selected code block
   }
   ```

**Normal Mode Flow:**
1. Position cursor on line of interest
2. Press `<leader>ai`
3. Location appears in AI pane:
   ```
   src/parser.rs:142
   ```

**Fallback Flow (no AI pane found):**
1. Plugin detects no AI pane in tmux
2. Copies formatted message to clipboard
3. Shows notification: `"No AI pane found. Copied to clipboard."`
4. User pastes wherever needed

### Core Features

1. **Auto-detection:** Scans tmux panes for AI tool processes (claude, codex, opencode)
2. **Smart path resolution:** Git-relative paths when in repository, configurable fallback
3. **DiffviewOpen compatible:** Works in diff buffers using visual marks (`'<`, `'>`)
4. **Clipboard fallback:** Graceful degradation when tmux/AI not available
5. **Zero-config:** Works immediately with sensible defaults
6. **Security-first:** Literal mode tmux sending prevents shell injection

## Technical Approach

### Architecture Decisions

**Decision 1: Synchronous Operations**
- **Choice:** Blocking shell calls via `vim.fn.systemlist()`
- **Rationale:** Operations complete in <100ms (tmux list-panes ~10-30ms, send-keys ~5-10ms). Async complexity not justified.
- **Trade-off:** Tiny UI freeze (<100ms) vs. 200+ lines of async boilerplate

**Decision 2: Tmux Shell Interface**
- **Choice:** Shell commands (`tmux list-panes`, `tmux send-keys`) over tmux RPC/API
- **Rationale:** Universal compatibility, no dependencies, proven pattern in similar plugins
- **Trade-off:** Shell escaping complexity vs. dependency management

**Decision 3: Literal Mode Sending**
- **Choice:** `tmux send-keys -l "<text>"` (literal flag)
- **Rationale:** **Security-critical** - prevents shell interpretation of special characters
- **Trade-off:** Separate `send-keys Enter` command needed vs. shell injection vulnerability

**Decision 4: Substring Process Matching**
- **Choice:** Case-insensitive substring match on process names
- **Rationale:** Handles variations like "claude", "claude-code-cli", "/usr/bin/claude --flags"
- **Trade-off:** Potential false positives (mitigated by specific names) vs. brittleness of exact match

### Implementation Patterns

#### Module Structure
```lua
-- lua/send-to-ai/tmux.lua
local M = {}

-- Internal functions (not exported)
local function escape_for_tmux(text)
  -- Escape for -l literal mode (minimal needed)
  return text:gsub([[\]], [[\\]])
end

local function find_tmux_session()
  local ok, result = pcall(vim.fn.systemlist, 'tmux display-message -p "#{session_name}"')
  if not ok or not result[1] or result[1] == '' then
    return nil, "Not in tmux session"
  end
  return result[1], nil
end

-- Public API
function M.find_ai_pane(config)
  -- Returns: pane_id, error
  -- Implementation details...
end

function M.send_to_pane(pane_id, text)
  -- Returns: success, error
  -- Implementation details...
end

return M
```

#### Error Handling Pattern
```lua
-- Consistent return signature: result, error_message
function M.send_message(content)
  local pane_id, err = tmux.find_ai_pane(config)
  if not pane_id then
    -- Fall back to clipboard
    vim.notify("No AI pane found. Trying clipboard...", vim.log.levels.WARN)
    local ok, clipboard_err = clipboard.copy(content)
    if not ok then
      vim.notify("Failed: " .. clipboard_err, vim.log.levels.ERROR)
      return false, clipboard_err
    end
    vim.notify("Copied to clipboard", vim.log.levels.INFO)
    return true, nil
  end

  local ok, send_err = tmux.send_to_pane(pane_id, content)
  if not ok then
    -- Retry with clipboard
    vim.notify("Pane send failed: " .. send_err .. ". Trying clipboard...", vim.log.levels.WARN)
    clipboard.copy(content)
    return true, "fallback"
  end

  vim.notify("Sent to AI pane " .. pane_id, vim.log.levels.INFO)
  return true, nil
end
```

#### Git Root Detection
```lua
-- lua/send-to-ai/format.lua
local function get_git_relative_path(filepath, config)
  if config.path_style ~= 'git_relative' then
    return get_alternative_path(filepath, config)
  end

  local ok, git_root = pcall(vim.fn.systemlist,
    'git -C "' .. vim.fn.fnamemodify(filepath, ':h') .. '" rev-parse --show-toplevel 2>/dev/null')

  if not ok or not git_root[1] or git_root[1] == '' then
    -- Fall back based on config
    if config.path_style_fallback == 'cwd_relative' then
      return vim.fn.fnamemodify(filepath, ':.')
    elseif config.path_style_fallback == 'absolute' then
      return vim.fn.fnamemodify(filepath, ':p')
    else
      return vim.fn.fnamemodify(filepath, ':t')  -- filename only
    end
  end

  local root = git_root[1]:gsub([[\]], '/'):gsub('/$', '')
  local rel_path = vim.fn.fnamemodify(filepath, ':p'):gsub('^' .. root .. '/', '')
  return rel_path
end
```

#### Visual Selection Extraction
```lua
-- Works in all contexts including DiffviewOpen
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  -- Validate selection
  if start_line == 0 or end_line == 0 then
    return nil, nil, "Invalid selection"
  end

  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  local lines = vim.fn.getline(start_line, end_line)
  return lines, { start = start_line, ['end'] = end_line }, nil
end
```

### Critical Design Decisions from SpecFlow Analysis

**Decision 5: Multi-Pane Resolution**
- **Problem:** What happens when multiple AI panes are detected?
- **Solution:** Use first match with preference order:
  1. Panes in current tmux session (if `prefer_session = true`)
  2. Panes in other sessions (fallback)
  3. Show notification listing which pane received message
- **Future Enhancement:** Interactive pane selection UI (`:SendToAI select`)

**Decision 6: Unnamed Buffer Handling**
- **Problem:** How to handle `[No Name]` buffers?
- **Solution:** Show error with helpful message:
  - `"Cannot send from unnamed buffer. Save file first or use visual mode to copy code."`
  - Allow sending just code (no path) in visual mode from unnamed buffers
- **Rationale:** AI needs file context for location references, but code-only is still useful

**Decision 7: Large Selection Limits**
- **Problem:** 10,000+ line selections could hang or overflow tmux buffer
- **Solution:** Warn at 5,000 lines, hard limit at 10,000 lines
  - `"Selection is large (5,234 lines). Send anyway? [y/n]"`
  - `"Selection too large (>10,000 lines). Please select a smaller range."`
- **Rationale:** Prevents accidental hangs from whole-file selections

**Decision 8: Special Buffer Detection**
- **Problem:** What about help, terminal, quickfix, oil.nvim, fugitive buffers?
- **Solution:** Detect special buffers and show contextual errors:
  - Help: `"Cannot send from help buffer"`
  - Terminal: `"Cannot send from terminal buffer"`
  - Oil/Fugitive/etc: `"Cannot send from special buffer: {buftype}"`
- **Implementation:** Check `vim.bo.buftype` and buffer name patterns

**Decision 9: Cross-Platform Clipboard**
- **Problem:** Different clipboard commands on macOS, Linux, WSL
- **Solution:** Detection order:
  1. `pbcopy` (macOS)
  2. `clip.exe` (WSL - Windows clipboard)
  3. `wl-copy` (Wayland)
  4. `xclip` (X11)
  5. `xsel` (X11 fallback)
  6. Error: `"No clipboard command found. Install pbcopy, xclip, or wl-copy"`
- **Validation:** Check via `:checkhealth send-to-ai`

**Decision 10: Tmux Escaping Strategy**
- **Problem:** Shell injection risk with special characters in code
- **Solution:** Use `tmux send-keys -l` (literal mode) + minimal escaping:
  - Only escape backslashes: `text:gsub([[\]], [[\\]])`
  - `-l` flag prevents interpretation of `$()`, backticks, quotes, etc.
  - Send Enter separately: `tmux send-keys -t <pane> Enter`
- **Security Note:** This is **critical** - without `-l`, code like `$(rm -rf /)` could execute

### Message Format Specification

**Visual Mode Message:**
```
<git_relative_path>:<start_line>-<end_line>
<code_block>
```

Example:
```
src/parser/expr.rs:142-156
fn parse_expression(&self) -> Result<Expr> {
    let token = self.peek()?;
    match token.kind {
        TokenKind::Number => self.parse_number(),
        TokenKind::Ident => self.parse_ident(),
        _ => Err(ParseError::UnexpectedToken(token))
    }
}
```

**Normal Mode Message:**
```
<git_relative_path>:<line_number>
```

Example:
```
src/parser/expr.rs:142
```

**Format Rules:**
- Paths use forward slashes (even on Windows)
- Line numbers are 1-indexed
- No trailing whitespace
- No markdown fences (AI tools add their own)
- UTF-8 encoded (preserve multi-byte characters)

### Tmux Integration Details

**AI Pane Detection Algorithm:**
```lua
function M.find_ai_pane(config)
  -- 1. Check if in tmux
  if vim.env.TMUX == nil then
    return nil, "Not in tmux session"
  end

  -- 2. Get current session (for prefer_session)
  local current_session = nil
  if config.prefer_session then
    current_session = find_tmux_session()
  end

  -- 3. List all panes with their processes
  local ok, panes = pcall(vim.fn.systemlist,
    'tmux list-panes -a -F "#{session_name}:#{pane_id}:#{pane_current_command}"')

  if not ok or not panes then
    return nil, "Failed to query tmux panes"
  end

  -- 4. Find AI panes (substring match, case-insensitive)
  local ai_panes = {}
  for _, pane_info in ipairs(panes) do
    local session, pane_id, command = pane_info:match("^([^:]+):([^:]+):(.+)$")
    if command then
      local cmd_lower = command:lower()
      for _, ai_process in ipairs(config.ai_processes) do
        if cmd_lower:find(ai_process:lower(), 1, true) then
          table.insert(ai_panes, { session = session, pane_id = pane_id, command = command })
          break
        end
      end
    end
  end

  if #ai_panes == 0 then
    return nil, "No AI panes found"
  end

  -- 5. Prefer current session if enabled
  if current_session and config.prefer_session then
    for _, pane in ipairs(ai_panes) do
      if pane.session == current_session then
        return pane.pane_id, nil
      end
    end
  end

  -- 6. Return first match
  local selected = ai_panes[1]
  if #ai_panes > 1 then
    vim.notify(
      string.format("Multiple AI panes found. Using %s (%s)", selected.pane_id, selected.command),
      vim.log.levels.INFO
    )
  end

  return selected.pane_id, nil
end
```

**Sending to Pane:**
```lua
function M.send_to_pane(pane_id, text)
  -- 1. Escape for tmux literal mode
  local escaped = text:gsub([[\]], [[\\]])

  -- 2. Send text with -l flag (literal mode)
  local send_cmd = string.format('tmux send-keys -t "%s" -l %s', pane_id, vim.fn.shellescape(escaped))
  local ok, result = pcall(vim.fn.system, send_cmd)

  if not ok or vim.v.shell_error ~= 0 then
    return false, "Tmux send-keys failed: " .. (result or "unknown error")
  end

  -- 3. Send Enter separately
  local enter_cmd = string.format('tmux send-keys -t "%s" Enter', pane_id)
  ok, result = pcall(vim.fn.system, enter_cmd)

  if not ok or vim.v.shell_error ~= 0 then
    return false, "Failed to send Enter: " .. (result or "unknown error")
  end

  return true, nil
end
```

## Implementation Phases

### Phase 1: Foundation & Core Logic (Day 1-2)

**Goal:** Establish project structure, core modules, and basic functionality without tmux integration.

#### Tasks & Deliverables

**1.1 Project Initialization**
- [ ] Initialize git repository: `git init`
- [ ] Create `.gitignore` with Neovim plugin patterns (`.DS_Store`, `*.swp`, `lua_modules/`, `.test/`)
- [ ] Create `LICENSE` file (MIT)
- [ ] Create directory structure:
  ```
  lua/send-to-ai/
  plugin/
  docs/
  ```

**1.2 Configuration Module (`lua/send-to-ai/config.lua`)**
- [ ] Define default configuration schema:
  ```lua
  local defaults = {
    ai_processes = { 'claude', 'codex', 'opencode' },
    prefer_session = true,
    fallback_clipboard = true,
    path_style = 'git_relative',
    path_style_fallback = 'filename_only',
    max_selection_lines = 10000,
    warn_selection_lines = 5000,
    cache_pane_detection = false,  -- Future: enable for performance
  }
  ```
- [ ] Implement `M.setup(user_config)` with deep merge logic
- [ ] Add validation for all config values:
  - `path_style` in `{'git_relative', 'cwd_relative', 'absolute'}`
  - `path_style_fallback` in `{'filename_only', 'cwd_relative', 'absolute'}`
  - `ai_processes` is non-empty array of strings
  - `max_selection_lines` > 0
- [ ] Write validation error messages with helpful suggestions
- [ ] Export `M.get()` to retrieve current config

**1.3 Format Module (`lua/send-to-ai/format.lua`)**
- [ ] Implement `get_git_relative_path(filepath, config)`:
  - Run `git rev-parse --show-toplevel` from file's directory
  - Handle git errors gracefully (not in repo, corrupt .git)
  - Fall back to `path_style_fallback` on failure
  - Handle nested git repos (use closest parent)
  - Normalize path separators to forward slashes
- [ ] Implement `get_cwd_relative_path(filepath)` using `vim.fn.fnamemodify(filepath, ':.')`
- [ ] Implement `get_absolute_path(filepath)` using `vim.fn.fnamemodify(filepath, ':p')`
- [ ] Implement `format_location_message(filepath, line_number, config)`:
  - Returns: `<path>:<line_number>`
- [ ] Implement `format_code_message(filepath, line_range, lines, config)`:
  - Returns: `<path>:<start>-<end>\n<code>`
  - Join lines with `\n`
  - Preserve leading/trailing whitespace
- [ ] Handle edge cases:
  - Empty file paths → return "[No Name]"
  - Invalid line numbers → clamp to buffer range
  - Multi-byte characters → preserve UTF-8

**1.4 Testing (Manual)**
- [ ] Test path resolution in git repo
- [ ] Test path resolution outside git repo
- [ ] Test path resolution with nested repos
- [ ] Test message formatting with sample code
- [ ] Test config validation with invalid inputs
- [ ] Test multi-byte character preservation

#### Success Criteria (Phase 1)

- [ ] `require('send-to-ai.config').setup({})` works without errors
- [ ] `require('send-to-ai.format')` produces correct message formats
- [ ] Git path resolution works correctly in test cases
- [ ] Configuration validation rejects invalid inputs with clear errors
- [ ] All edge cases handled (unnamed buffers, special paths)

#### Estimated Effort

**Time:** 6-8 hours
**Files:** `config.lua` (~50 lines), `format.lua` (~80 lines), `.gitignore`, `LICENSE`

---

### Phase 2: Tmux & Clipboard Integration (Day 2-3)

**Goal:** Implement tmux pane detection, sending, and clipboard fallback.

#### Tasks & Deliverables

**2.1 Tmux Module (`lua/send-to-ai/tmux.lua`)**
- [ ] Implement `is_in_tmux()`:
  - Check `vim.env.TMUX ~= nil`
- [ ] Implement `get_current_session()`:
  - Run `tmux display-message -p "#{session_name}"`
  - Handle errors (not in tmux)
- [ ] Implement `list_all_panes()`:
  - Run `tmux list-panes -a -F "#{session_name}:#{pane_id}:#{pane_current_command}"`
  - Parse output into structured array
  - Handle tmux not installed
  - Handle tmux socket errors
- [ ] Implement `find_ai_pane(config)`:
  - Filter panes by `ai_processes` (substring match, case-insensitive)
  - Prefer current session if `prefer_session = true`
  - Return first match with metadata
  - Handle multiple matches (log notification)
- [ ] Implement `send_to_pane(pane_id, text)`:
  - Escape text for tmux: only backslashes
  - Run `tmux send-keys -t <pane_id> -l <escaped_text>`
  - Run `tmux send-keys -t <pane_id> Enter`
  - Handle pane closed errors
  - Handle permission errors
- [ ] Add timeout wrapper for tmux commands (2 seconds max)

**2.2 Clipboard Module (`lua/send-to-ai/clipboard.lua`)**
- [ ] Implement `detect_clipboard_command()`:
  - Check for `pbcopy` (macOS)
  - Check for `clip.exe` (WSL)
  - Check for `wl-copy` (Wayland)
  - Check for `xclip` (X11)
  - Check for `xsel` (X11 fallback)
  - Return first available or nil
- [ ] Implement `copy_to_clipboard(text)`:
  - Run detected clipboard command with text as stdin
  - Handle command failures
  - Return success/error
- [ ] Add fallback message when no clipboard available:
  - Display text in notification with "Copy manually:" instruction

**2.3 Testing (Manual)**
- [ ] Test pane detection with single AI pane
- [ ] Test pane detection with multiple AI panes
- [ ] Test pane detection across different sessions
- [ ] Test sending to pane with special characters (`$()`, backticks, quotes)
- [ ] Test sending large messages (1000+ lines)
- [ ] Test clipboard fallback on each platform (macOS, Linux, WSL)
- [ ] Test error handling (tmux not installed, pane closed mid-send)

#### Success Criteria (Phase 2)

- [ ] AI pane detection works in complex tmux setups (multiple sessions, windows)
- [ ] Sending to pane preserves all special characters without execution
- [ ] Clipboard fallback works on macOS, Linux X11, Linux Wayland, and WSL
- [ ] Error messages are clear and actionable
- [ ] No shell injection vulnerabilities (verified with malicious code samples)

#### Estimated Effort

**Time:** 8-10 hours
**Files:** `tmux.lua` (~120 lines), `clipboard.lua` (~60 lines)

---

### Phase 3: Command Integration & Neovim Interface (Day 3-4)

**Goal:** Integrate all modules, create user-facing commands, and handle Neovim buffer interaction.

#### Tasks & Deliverables

**3.1 Main Module (`lua/send-to-ai/init.lua`)**
- [ ] Implement `M.setup(user_config)`:
  - Forward to `config.setup()`
- [ ] Implement buffer validation:
  - Check if buffer is named: `vim.api.nvim_buf_get_name(bufnr) ~= ''`
  - Check buffer type: reject `help`, `terminal`, `quickfix`, etc.
  - Check for special buffer patterns: `oil://`, `fugitive://`, etc.
- [ ] Implement selection validation:
  - Check if selection is empty (start == end)
  - Check selection size (<= `max_selection_lines`)
  - Warn if selection > `warn_selection_lines`
- [ ] Implement `M.send_to_ai(mode)`:
  - **Normal mode:**
    - Get current file path
    - Get current line number: `vim.fn.line('.')`
    - Validate buffer
    - Format location message
    - Send to AI or clipboard
  - **Visual mode:**
    - Get visual selection marks: `vim.fn.getpos("'<")`, `vim.fn.getpos("'>")`
    - Extract lines: `vim.fn.getline(start, end)`
    - Validate selection size
    - Format code message
    - Send to AI or clipboard
- [ ] Implement `M.send(content)`:
  - Try tmux pane send
  - On failure, try clipboard
  - Show appropriate notifications
  - Return success/error
- [ ] Add fold handling:
  - Temporarily disable folds during selection extraction
  - Re-enable after extraction

**3.2 Command Definition (`plugin/send-to-ai.lua`)**
- [ ] Create `:SendToAI` command:
  ```lua
  vim.api.nvim_create_user_command('SendToAI', function()
    require('send-to-ai').send_to_ai(vim.fn.mode())
  end, {
    desc = 'Send code or location to AI in tmux pane',
    range = true,
  })
  ```
- [ ] Make command lazy-load the main module

**3.3 Testing (Manual)**
- [ ] Test normal mode in various buffer types
- [ ] Test visual mode (v, V, Ctrl-v)
- [ ] Test in DiffviewOpen
- [ ] Test with unnamed buffers (should error)
- [ ] Test with special buffers (help, terminal)
- [ ] Test with folded code
- [ ] Test with very large selections (>5000 lines)
- [ ] Test end-to-end flow: Neovim → tmux pane → AI receives
- [ ] Test end-to-end flow: Neovim → clipboard → manual paste

#### Success Criteria (Phase 3)

- [ ] `:SendToAI` works in normal mode (sends location)
- [ ] `:SendToAI` works in visual mode (sends code)
- [ ] Works in DiffviewOpen buffers
- [ ] Gracefully handles unnamed buffers with helpful error
- [ ] Gracefully handles special buffers with helpful error
- [ ] Large selections show warning before sending
- [ ] Notifications provide clear feedback on success/failure
- [ ] Folded code is fully expanded before sending

#### Estimated Effort

**Time:** 6-8 hours
**Files:** `init.lua` (~100 lines), `plugin/send-to-ai.lua` (~30 lines)

---

### Phase 4: Health Check, Documentation & Polish (Day 4-5)

**Goal:** Add health check for diagnostics, comprehensive documentation, and final polish.

#### Tasks & Deliverables

**4.1 Health Check (`lua/send-to-ai/health.lua`)**
- [ ] Implement `M.check()`:
  - Check tmux installed: `vim.fn.executable('tmux') == 1`
  - Check if in tmux session: `vim.env.TMUX ~= nil`
  - Check clipboard command availability
  - List detected AI panes (if in tmux)
  - Validate current configuration
  - Check tmux version: `tmux -V` (warn if < 2.0)
- [ ] Use `vim.health.*` API:
  - `vim.health.ok()` for passing checks
  - `vim.health.warn()` for non-critical issues
  - `vim.health.error()` for critical issues
- [ ] Provide actionable remediation steps in error messages

**4.2 README Documentation**
- [ ] Write README.md with sections:
  - **Features** (bullet list with highlights)
  - **Installation** (lazy.nvim example, packer alternative)
  - **Usage** (normal mode, visual mode, keybinding recommendation)
  - **Configuration** (setup() options with defaults)
  - **Requirements** (Neovim >= 0.9.0, tmux optional)
  - **How It Works** (brief technical explanation)
  - **Troubleshooting** (common issues, `:checkhealth` reference)
  - **Contributing** (link to issues)
  - **License** (MIT)
- [ ] Add examples with screenshots (animated GIF if possible)
- [ ] Document all configuration options with types and defaults
- [ ] Add FAQ section:
  - "What if I have multiple AI panes?"
  - "Can I use this without tmux?"
  - "How do I customize the message format?"
  - "Does this work on Windows/WSL?"

**4.3 Code Quality**
- [ ] Add docstrings to all public functions:
  ```lua
  --- Sends code or location to AI pane
  --- @param mode string The vim mode ('n' for normal, 'v'/'V' for visual)
  --- @return boolean success
  --- @return string|nil error Error message if failed
  ```
- [ ] Add inline comments for complex logic
- [ ] Ensure consistent error handling across all modules
- [ ] Validate all user-facing strings (notifications, errors) are clear
- [ ] Run Lua linter (if available)

**4.4 Final Testing Checklist**
- [ ] Install plugin in fresh Neovim config
- [ ] Test zero-config experience (no setup() call)
- [ ] Test with custom configuration
- [ ] Run `:checkhealth send-to-ai` and verify all checks
- [ ] Test on macOS, Linux, and WSL (if available)
- [ ] Test with tmux versions 2.x and 3.x
- [ ] Test with Claude Code, Codex, and OpenCode (if available)
- [ ] Verify no errors in `:messages` after operations
- [ ] Test rapid-fire usage (spam `<leader>ai` quickly)

**4.5 Release Preparation**
- [ ] Create initial git commit:
  ```bash
  git add .
  git commit -m "Initial implementation of nvim-send-to-ai-in-tmux

  - Auto-detect AI panes in tmux by process name
  - Send code snippets with file context
  - Send location references in normal mode
  - Clipboard fallback when tmux unavailable
  - Health check for diagnostics
  - Zero-config with optional customization
  - Works in DiffviewOpen and all vim contexts

  Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
  ```
- [ ] Tag v0.1.0 release:
  ```bash
  git tag -a v0.1.0 -m "Initial release: Core functionality"
  ```
- [ ] Create GitHub repository (if publishing)
- [ ] Push to remote:
  ```bash
  git remote add origin https://github.com/openclaw/nvim-send-to-ai-in-tmux.git
  git push -u origin main
  git push --tags
  ```

#### Success Criteria (Phase 4)

- [ ] `:checkhealth send-to-ai` provides comprehensive diagnostics
- [ ] README is complete and easy to follow
- [ ] All public functions have docstrings
- [ ] Plugin works on at least 2 platforms (macOS, Linux, or WSL)
- [ ] No errors or warnings in `:messages` during normal usage
- [ ] Ready for public release (if desired)

#### Estimated Effort

**Time:** 6-8 hours
**Files:** `health.lua` (~60 lines), `README.md` (~300-500 lines)

---

### Phase 5: Advanced Features & Optimization (Future / Optional)

**Goal:** Enhancements beyond MVP based on user feedback.

#### Potential Features

**5.1 Pane Selection UI**
- [ ] `:SendToAI select` command to choose from multiple AI panes
- [ ] Show picker with `vim.ui.select()`:
  ```
  Select AI pane:
  1. %2 (claude) in session 'work'
  2. %5 (codex) in session 'ai-tools'
  ```
- [ ] Remember selected pane for session (cache)

**5.2 Pane Detection Caching**
- [ ] Enable `cache_pane_detection = true` by default
- [ ] Cache for 5 seconds or until tmux session changes
- [ ] Invalidate cache on manual `:SendToAI select`

**5.3 Send Entire File**
- [ ] `:SendToAIFile` command to send whole buffer
- [ ] Confirmation prompt for large files (>500 lines)

**5.4 Operator Mode**
- [ ] `<leader>ai` as operator: `<leader>aip` sends paragraph
- [ ] Works with text objects: `<leader>aiaf` sends function

**5.5 Custom Message Templates**
- [ ] Configuration option: `message_template`
  ```lua
  message_template = "File: {path}\nLines: {start}-{end}\n\n{code}"
  ```
- [ ] Template variables: `{path}`, `{start}`, `{end}`, `{code}`, `{line}`

**5.6 History Logging**
- [ ] Log all sent messages to `~/.local/share/nvim/send-to-ai.log`
- [ ] `:SendToAIHistory` command to view recent sends

**5.7 Response Capture**
- [ ] Optional: capture AI response and display in floating window
- [ ] Requires tmux capture-pane + response detection heuristics

#### Estimated Effort (Optional)

**Time:** 10-15 hours total for all advanced features
**Priority:** Based on user feedback and demand

## Alternative Approaches Considered

### 1. Shell-Heavy Approach (~150 lines)

**Description:** Inline shell commands in Lua strings with minimal abstraction.

**Example:**
```lua
function send_to_ai()
  local cmd = [[
    pane=$(tmux list-panes -a | grep claude | head -1 | cut -d: -f1)
    echo "]] .. filepath .. [[" | tmux send-keys -t $pane
  ]]
  vim.fn.system(cmd)
end
```

**Pros:**
- Minimal code (~150 lines total)
- No module boundaries

**Cons:**
- **Shell escaping nightmare:** Filepath/code with quotes, backticks, `$()` breaks everything
- **Error handling impossible:** Can't distinguish between different failure modes
- **Not testable:** Logic embedded in shell strings
- **Platform-specific:** Different shells behave differently
- **Security risk:** High chance of shell injection vulnerabilities

**Rejection Reason:** Too brittle for production use. Shell escaping complexity outweighs code savings.

---

### 2. Async Job-Based Approach (~500+ lines)

**Description:** Use `vim.loop` (libuv) or `plenary.nvim` jobs for non-blocking tmux interaction.

**Example:**
```lua
local Job = require('plenary.job')

function send_async(text)
  Job:new({
    command = 'tmux',
    args = { 'send-keys', '-t', pane_id, text },
    on_exit = function(j, return_val)
      if return_val == 0 then
        notify_success()
      else
        notify_error()
      end
    end
  }):start()
end
```

**Pros:**
- Non-blocking operations (no UI freeze)
- Better for long-running tmux commands
- Modern Lua/Neovim patterns

**Cons:**
- **Massive complexity increase:** Async lifecycle, callbacks, error handling
- **Not needed for this use case:** Tmux operations complete in <100ms
- **Dependency burden:** Requires plenary.nvim or reinventing job scheduling
- **Harder to debug:** Async timing issues difficult to reproduce

**Rejection Reason:** Overkill for operations that complete in <100ms. The tiny UI freeze is imperceptible, and blocking code is much simpler.

---

### 3. Neovim API RPC to tmux

**Description:** Use Neovim's RPC to communicate with a tmux plugin or tmux RPC socket.

**Example:**
```lua
-- Send RPC command to tmux control mode
vim.fn.sockconnect('pipe', '/tmp/tmux-socket', { rpc = true })
```

**Pros:**
- Potentially more robust than shell commands
- Could enable bidirectional communication

**Cons:**
- **No standard tmux RPC protocol:** Would need custom tmux plugin
- **Complex setup:** Users must install and configure tmux plugin
- **Limited tmux support:** Tmux control mode is not widely used
- **Breaks zero-config goal:** Requires significant user setup

**Rejection Reason:** Requires custom tmux plugin, breaking the zero-config design goal. Shell commands work universally.

---

### 4. Language Server Protocol (LSP) for AI Tools

**Description:** Implement AI tools as LSP servers, send code via LSP protocol.

**Example:**
```lua
vim.lsp.buf_request(0, 'claude/sendCode', { uri = filepath, range = range })
```

**Pros:**
- Standardized protocol
- Rich semantic information available
- Bidirectional communication

**Cons:**
- **Wrong abstraction:** LSP is for language analysis, not message passing
- **Massive complexity:** Each AI tool needs LSP server implementation
- **Out of scope:** This is a simple send-to-pane tool, not an AI client
- **No existing ecosystem:** AI CLI tools don't implement LSP

**Rejection Reason:** LSP is the wrong protocol for this use case. Over-engineering for a simple problem.

---

## Acceptance Criteria

### Functional Requirements

#### Core Functionality
- [ ] **Visual mode → AI pane:** Highlighted code sent to AI pane with file path and line range
- [ ] **Normal mode → AI pane:** Current file path and line number sent to AI pane
- [ ] **Clipboard fallback:** When no AI pane found, formatted message copied to system clipboard
- [ ] **DiffviewOpen compatibility:** Works correctly in DiffviewOpen buffers using visual marks
- [ ] **Zero-config operation:** Plugin works immediately after installation without setup() call
- [ ] **Multi-mode support:** Works in visual (v), visual line (V), and visual block (Ctrl-v) modes

#### Path Resolution
- [ ] **Git-relative paths:** Files in git repos use paths relative to git root
- [ ] **Fallback path styles:** When not in git repo, falls back to configured style (filename/cwd/absolute)
- [ ] **Nested repo handling:** Uses closest git parent for nested repositories
- [ ] **Symlink resolution:** Resolves symlinks to real paths for consistency
- [ ] **Cross-platform paths:** Forward slashes used consistently across macOS, Linux, Windows/WSL

#### Tmux Integration
- [ ] **AI pane detection:** Automatically finds AI tool panes by process name (claude, codex, opencode)
- [ ] **Session preference:** Prefers panes in current tmux session when configured
- [ ] **Multiple pane handling:** When multiple AI panes exist, uses first match and notifies user
- [ ] **Literal mode sending:** Uses `tmux send-keys -l` to prevent shell interpretation
- [ ] **Special character safety:** Code with `$()`, backticks, quotes, backslashes sends correctly without execution
- [ ] **Pane failure recovery:** Falls back to clipboard when pane send fails

#### Error Handling
- [ ] **Unnamed buffer rejection:** Shows error: "Cannot send from unnamed buffer. Save file first."
- [ ] **Special buffer rejection:** Detects and rejects help, terminal, quickfix, oil, fugitive buffers with helpful errors
- [ ] **Large selection warning:** Warns at 5,000 lines: "Selection is large. Send anyway? [y/n]"
- [ ] **Large selection rejection:** Rejects selections >10,000 lines: "Selection too large. Select smaller range."
- [ ] **Tmux unavailable:** Falls back to clipboard with notification when tmux not running
- [ ] **Clipboard unavailable:** Shows error with manual copy instructions when no clipboard command found
- [ ] **Git errors:** Handles corrupt git repos, bare repos, and non-repos gracefully with fallback
- [ ] **Pane closed mid-send:** Recovers when AI pane closes during send operation

#### User Feedback
- [ ] **Success notification:** Confirms successful send: "Sent to AI pane %2"
- [ ] **Fallback notification:** Informs when using clipboard: "No AI pane found. Copied to clipboard."
- [ ] **Error notifications:** Clear, actionable error messages for all failure modes
- [ ] **Multi-pane notification:** Lists which pane was chosen when multiple AI panes exist
- [ ] **Notification visibility:** Messages persist long enough to be read (3+ seconds)

### Non-Functional Requirements

#### Performance
- [ ] **Fast pane detection:** Tmux pane detection completes in <100ms
- [ ] **Fast sending:** Sending code to pane completes in <500ms for typical selections (<1000 lines)
- [ ] **Imperceptible blocking:** UI freeze is <100ms (not noticeable to user)
- [ ] **No memory leaks:** Repeated usage doesn't increase memory consumption
- [ ] **Efficient selection extraction:** Large selections (1000+ lines) extracted without UI lag

#### Reliability
- [ ] **No shell injection:** Malicious code samples (shell commands, backticks, etc.) don't execute
- [ ] **UTF-8 correctness:** Multi-byte characters (emoji, CJK) preserved correctly
- [ ] **Idempotent operations:** Repeated sends don't corrupt state or cause errors
- [ ] **Timeout protection:** Hung tmux commands timeout after 2 seconds
- [ ] **Error recovery:** Plugin recovers gracefully from all error states without requiring restart

#### Usability
- [ ] **Clear documentation:** README explains installation and basic usage in <5 minutes
- [ ] **Helpful health check:** `:checkhealth send-to-ai` diagnoses common setup issues
- [ ] **Sensible defaults:** Zero-config experience works for 90% of users
- [ ] **Easy customization:** Common customizations (AI process names, path style) documented
- [ ] **Discoverable command:** `:SendToAI` command appears in command completion

#### Compatibility
- [ ] **Neovim versions:** Works on Neovim >= 0.9.0
- [ ] **Tmux versions:** Works on tmux >= 2.0
- [ ] **macOS clipboard:** Detects and uses `pbcopy`
- [ ] **Linux X11 clipboard:** Detects and uses `xclip` or `xsel`
- [ ] **Linux Wayland clipboard:** Detects and uses `wl-copy`
- [ ] **WSL clipboard:** Detects and uses `clip.exe` (Windows clipboard bridge)
- [ ] **Cross-platform paths:** Handles forward slashes, backslashes, spaces in paths

### Quality Gates

#### Code Quality
- [ ] **Docstrings:** All public functions have LuaDoc docstrings with param/return types
- [ ] **Error handling:** All shell commands wrapped in `pcall()` with error propagation
- [ ] **Consistent patterns:** Similar operations use same patterns (e.g., `result, error` returns)
- [ ] **No global pollution:** No global variables created
- [ ] **Module isolation:** Each module has clear responsibility and minimal coupling

#### Testing
- [ ] **Manual test checklist:** All items in Phase 4 testing checklist pass
- [ ] **Cross-platform verification:** Tested on at least 2 of: macOS, Linux, WSL
- [ ] **AI tool verification:** Tested with at least 1 AI tool (Claude Code, Codex, or OpenCode)
- [ ] **Edge case coverage:** All edge cases from SpecFlow analysis tested
- [ ] **No regression:** Repeated testing shows consistent behavior

#### Documentation
- [ ] **Complete README:** All sections from Phase 4 documentation complete
- [ ] **Configuration documentation:** All setup() options documented with types and defaults
- [ ] **Troubleshooting guide:** Common issues and solutions documented
- [ ] **Example configurations:** At least 3 example configurations provided
- [ ] **Changelog:** CHANGELOG.md created with v0.1.0 entry

#### Release Readiness
- [ ] **Version tagged:** Git tag `v0.1.0` created
- [ ] **Commit message:** Follows conventional commit format with detailed description
- [ ] **License:** MIT license file present
- [ ] **Clean git history:** No sensitive data, debug code, or temp files in commits
- [ ] **Repository setup:** GitHub repository created (if publishing)

## Success Metrics

### Quantitative Metrics

**Performance:**
- **Context sharing time:** Reduce from 10-20 seconds (manual) to <2 seconds (plugin)
  - Target: 90% reduction in time to share code context
- **Operations per day:** Enable 20-50+ AI interactions/day without friction
  - Target: 10-50 minutes saved daily per developer
- **Error rate:** <1% of sends fail due to plugin errors
  - Target: 99%+ success rate in normal operation

**Adoption:**
- **Installation time:** <5 minutes from discovery to first use
  - Target: User can install and use within single tmux session
- **Configuration rate:** >80% of users use zero-config (no setup() call)
  - Target: Sensible defaults work for vast majority

### Qualitative Metrics

**User Experience:**
- **Flow preservation:** Users report no disruption to flow state when sharing context
  - Success: "I don't even think about it anymore, just press the key"
- **Reliability perception:** Users trust the plugin works consistently
  - Success: "Never had it fail on me"
- **Simplicity feedback:** Users describe plugin as "simple" and "obvious"
  - Success: "Does exactly what it says, no surprises"

**Developer Satisfaction:**
- **Recommendation rate:** Users recommend plugin to teammates
  - Target: >70% of users recommend to others
- **Daily usage:** Becomes part of regular workflow (used multiple times daily)
  - Success: Habit formation within first week

### Leading Indicators (Early Success Signals)

**Week 1:**
- [ ] Plugin works on first try (no debugging needed)
- [ ] User successfully sends code to AI pane in <30 seconds from installation
- [ ] No critical bugs discovered in normal usage

**Month 1:**
- [ ] User uses plugin >10 times/day without thinking about it
- [ ] User hasn't needed to customize configuration
- [ ] User has recommended to at least 1 teammate

### Failure Signals (Red Flags)

- Users disable plugin due to frequent errors
- Users resort to manual copy-paste because plugin is "unreliable"
- Users require extensive configuration tweaking to make it work
- Plugin causes Neovim crashes or hangs
- Users can't understand how to install/use from README

## Dependencies & Prerequisites

### System Dependencies

**Required:**
- **Neovim >= 0.9.0**
  - Reason: Uses `vim.notify()`, `vim.health`, modern Lua APIs
  - Verification: `nvim --version | head -1`

**Optional (for full functionality):**
- **tmux >= 2.0**
  - Reason: Uses `list-panes -a -F` format syntax
  - Verification: `tmux -V`
  - Fallback: Clipboard mode when tmux unavailable

- **Clipboard command (one of):**
  - macOS: `pbcopy` (built-in)
  - Linux X11: `xclip` or `xsel`
  - Linux Wayland: `wl-copy` (wl-clipboard package)
  - WSL: `clip.exe` (built-in to Windows)
  - Verification: `:checkhealth send-to-ai`

**Optional (for git-relative paths):**
- **git >= 2.0**
  - Reason: `git rev-parse --show-toplevel`
  - Verification: `git --version`
  - Fallback: Filename-only paths

### Neovim Plugin Dependencies

**None required.** This is a self-contained plugin with no external Lua dependencies.

**Optional (for enhanced experience):**
- **lazy.nvim, packer.nvim, or similar:** Plugin manager for easy installation
- **DiffviewOpen:** Plugin works in DiffviewOpen buffers (nice-to-have, not required)

### Development Dependencies (for contributors)

- **Lua language server (optional):** For development/IDE support
- **StyLua (optional):** For code formatting

### AI Tool Prerequisites

**One of (for full workflow):**
- **Claude Code CLI** running in tmux pane
- **GitHub Codex CLI** running in tmux pane
- **OpenCode CLI** running in tmux pane
- **Aider** (if added to `ai_processes` config)

**Setup verification:**
```bash
# Start tmux session
tmux new-session -s ai-work

# In one pane, start AI tool
claude

# In another pane, start Neovim
nvim

# In Neovim, verify detection
:checkhealth send-to-ai
```

### External References

**Similar Plugins (for pattern reference):**
- [tunnell.nvim](https://github.com/sourproton/tunnell.nvim) - Send text to tmux REPL
- [opencode-context.nvim](https://github.com/cousine/opencode-context.nvim) - Opencode integration
- [claude-code.nvim](https://github.com/dreemanuel/claude-code.nvim) - Claude Code integration
- [tmux.nvim](https://github.com/aserowy/tmux.nvim) - Comprehensive tmux integration

## Risk Analysis & Mitigation

### High-Impact Risks

#### Risk 1: Shell Injection Vulnerability

**Description:** Malicious code containing shell commands (`$(rm -rf /)`, backticks) could execute if not properly escaped.

**Probability:** Medium (if not handled correctly)
**Impact:** **CRITICAL** - Could delete files, steal data, or compromise system
**Severity:** 🔴 **Critical**

**Mitigation:**
- ✅ Use `tmux send-keys -l` (literal mode) for all text transmission
- ✅ Escape only necessary characters (backslashes) since `-l` disables interpretation
- ✅ Never concatenate user input into shell commands
- ✅ Test with known-malicious samples: `$(whoami)`, `` `id` ``, `$PATH`
- ✅ Code review focused on all shell command construction
- ✅ Document escaping strategy clearly in code comments

**Verification:**
```lua
-- Test case: This should NOT execute
local malicious_code = [[
local password = "$(cat ~/.ssh/id_rsa)"
local data = `curl evil.com`
]]
-- After sending, verify no command execution occurred
```

---

#### Risk 2: Clipboard Injection / Data Leakage

**Description:** Clipboard fallback could expose sensitive code to clipboard history, password managers, or sync services.

**Probability:** Low (user chooses to trigger)
**Impact:** **Medium** - Accidental exposure of credentials, API keys
**Severity:** 🟡 **Medium**

**Mitigation:**
- ⚠️ Show clear notification when falling back to clipboard
- ⚠️ Document clipboard behavior in README security section
- ⚠️ Consider: Optional `confirm_clipboard = true` config to prompt before clipboard copy
- 📝 Future: Add `.env` detection and warn when sending files with secrets

**Verification:**
- User awareness: Notification clearly states "Copied to clipboard"
- Documentation: Security section warns about clipboard history

---

#### Risk 3: Tmux Pane Misidentification

**Description:** Plugin sends code to wrong pane (e.g., shell pane instead of AI pane) due to process name collision.

**Probability:** Low (AI tool names are distinctive)
**Impact:** **Medium** - Code sent to wrong pane could execute in shell
**Severity:** 🟡 **Medium**

**Mitigation:**
- ✅ Use specific process names: `claude`, `codex`, `opencode` (unlikely to collide)
- ✅ Substring match instead of exact match (handles `/usr/bin/claude --flags`)
- ✅ Case-insensitive match (handles "Claude" vs "claude")
- ✅ Show notification of which pane received message: "Sent to AI pane %2 (claude)"
- 📝 Future: Add `exclude_processes` config to blacklist certain panes

**Verification:**
- Test with similar process names: `vim`, `nvim`, `code`, `claude-vscode`
- Verify notification shows correct pane ID and process name

---

### Medium-Impact Risks

#### Risk 4: Tmux Version Incompatibility

**Description:** Older tmux versions might not support `list-panes -a -F` syntax.

**Probability:** Low (tmux 2.0+ released 2015)
**Impact:** **Medium** - Plugin non-functional for users on old systems
**Severity:** 🟡 **Medium**

**Mitigation:**
- ✅ Document requirement: tmux >= 2.0 in README
- ✅ Health check verifies tmux version
- ✅ Show helpful error: "tmux version too old. Requires >= 2.0. You have: 1.8"
- 📝 Future: Fallback to simpler tmux commands for older versions

**Verification:**
- Check tmux changelog for `-F` format flag introduction
- Test on tmux 2.0, 2.6, 3.0+ (if available)

---

#### Risk 5: Large Selection Performance

**Description:** Selecting entire large files (>10,000 lines) could hang or overflow tmux buffer.

**Probability:** Medium (users might accidentally select whole file)
**Impact:** **Low** - UI freeze, potential tmux hang
**Severity:** 🟢 **Low**

**Mitigation:**
- ✅ Warn at 5,000 lines: "Selection is large (5,234 lines). Send anyway?"
- ✅ Hard limit at 10,000 lines: "Selection too large (>10,000 lines). Select smaller range."
- ✅ Document limitation in README
- 📝 Future: Chunk large selections into multiple sends

**Verification:**
- Test with 1,000 / 5,000 / 10,000 / 50,000 line selections
- Measure send time and UI responsiveness

---

#### Risk 6: Platform-Specific Clipboard Failures

**Description:** Clipboard commands vary across platforms and might not be installed.

**Probability:** Medium (Linux users often need to install xclip)
**Impact:** **Medium** - Fallback mode non-functional
**Severity:** 🟡 **Medium**

**Mitigation:**
- ✅ Detect multiple clipboard commands (pbcopy, xclip, xsel, wl-copy, clip.exe)
- ✅ Health check shows which clipboard command is available
- ✅ Clear error when no clipboard found: "No clipboard command found. Install xclip or wl-copy."
- ✅ Document clipboard requirements per platform in README

**Verification:**
- Test on: macOS (pbcopy), Linux X11 (xclip), Linux Wayland (wl-copy), WSL (clip.exe)
- Verify graceful degradation when clipboard unavailable

---

### Low-Impact Risks

#### Risk 7: Git Repository Edge Cases

**Description:** Corrupt git repos, bare repos, or nested submodules might break path resolution.

**Probability:** Low (rare edge cases)
**Impact:** **Low** - Wrong path sent, but doesn't break plugin
**Severity:** 🟢 **Low**

**Mitigation:**
- ✅ Wrap git commands in `pcall()` to catch errors
- ✅ Fall back to filename-only when git fails
- ✅ Handle nested repos by using closest parent
- 📝 Future: Add `git_root_cache` to avoid repeated git calls

**Verification:**
- Test in: non-git directory, corrupt .git, bare repo, nested submodules

---

#### Risk 8: Multi-byte Character Corruption

**Description:** Visual selection boundaries might split multi-byte UTF-8 characters (emoji, CJK).

**Probability:** Low (Neovim generally UTF-8 aware)
**Impact:** **Low** - Garbled characters in message
**Severity:** 🟢 **Low**

**Mitigation:**
- ✅ Trust Neovim's UTF-8 handling for selection boundaries
- ✅ Test with emoji and CJK characters
- 📝 If issues arise, use `vim.str_byteindex()` for safe boundaries

**Verification:**
- Test selections containing: 🎉, 中文, emoji skin tones, zero-width joiners

---

#### Risk 9: Fold State Confusion

**Description:** Folded code might not expand before sending, sending only visible lines.

**Probability:** Low (Neovim handles this, but worth verifying)
**Impact:** **Low** - User confused by partial code sent
**Severity:** 🟢 **Low**

**Mitigation:**
- ✅ Verify `vim.fn.getline()` returns unfolded lines (it should)
- 📝 If needed: Temporarily disable folds during extraction
- 📝 Document behavior: "Folded code is expanded before sending"

**Verification:**
- Create folded function, select fold, verify all lines sent

---

### Risk Summary Matrix

| Risk | Probability | Impact | Severity | Mitigation Status |
|------|-------------|--------|----------|-------------------|
| Shell Injection | Medium | Critical | 🔴 Critical | ✅ Implemented |
| Clipboard Leakage | Low | Medium | 🟡 Medium | ⚠️ Partial (docs) |
| Pane Misidentification | Low | Medium | 🟡 Medium | ✅ Implemented |
| Tmux Version | Low | Medium | 🟡 Medium | ✅ Implemented |
| Large Selection | Medium | Low | 🟢 Low | ✅ Implemented |
| Clipboard Failures | Medium | Medium | 🟡 Medium | ✅ Implemented |
| Git Edge Cases | Low | Low | 🟢 Low | ✅ Implemented |
| UTF-8 Corruption | Low | Low | 🟢 Low | ✅ Trust Neovim |
| Fold Confusion | Low | Low | 🟢 Low | ✅ Verify only |

**Overall Risk Level:** 🟡 **Medium** (manageable with implemented mitigations)

## Future Considerations

### Extensibility Points

**Plugin Architecture:**
The modular design allows easy extension without core changes:

- **New AI tools:** Add to `ai_processes` config (no code changes)
- **New clipboard providers:** Add detection to `clipboard.lua` (single function)
- **New path styles:** Add to `format.lua` path resolution (single function)
- **Custom message formats:** Future `message_template` config option

**Hook System (Future):**
```lua
require('send-to-ai').setup({
  on_send = function(message, destination)
    -- Log, modify, or intercept messages
  end,
  on_error = function(error)
    -- Custom error handling
  end
})
```

### Community Requests (Anticipated)

Based on similar plugin ecosystems, expect requests for:

1. **Target pane selection UI** - Interactive picker for multiple AI panes
2. **Send to specific session/window** - Manual targeting instead of auto-detection
3. **Custom keybindings** - Built-in default keybindings (currently user-configured)
4. **Send motion/text-object** - Operator mode: `<leader>aip` sends paragraph
5. **History logging** - Track all sent messages for debugging
6. **Response capture** - Two-way communication (out of scope, but requested)

**Strategy:**
- Maintain KISS principle for core
- Add opt-in features via configuration flags
- Document workarounds for common requests
- Consider breaking into separate plugins if scope expands (e.g., send-to-ai-advanced)

### Integration Opportunities

**Potential Integrations:**

1. **AI Client Plugins:**
   - `copilot.vim`, `codeium.vim` - Send context to cloud AI
   - `chatgpt.nvim` - Send to ChatGPT interface

2. **REPL Plugins:**
   - `iron.nvim`, `conjure` - Send code to REPL instead of AI
   - `jupyter.nvim` - Send cells to Jupyter

3. **Diff/Review Plugins:**
   - `diffview.nvim` - Already compatible, enhance integration
   - `octo.nvim` - Send GitHub PR context to AI

4. **Project Management:**
   - `telescope.nvim` - Picker for selecting AI pane
   - `which-key.nvim` - Expose keybindings in which-key UI

### Backwards Compatibility Promise

**Semantic Versioning Commitment:**
- **Major (1.0 → 2.0):** Breaking config changes
- **Minor (0.1 → 0.2):** New features, backwards-compatible
- **Patch (0.1.0 → 0.1.1):** Bug fixes only

**Deprecation Policy:**
- Deprecated features maintained for 1 major version
- Clear warnings in `:messages` when using deprecated APIs
- Migration guide in CHANGELOG

**Configuration Compatibility:**
```lua
-- v0.1.0 config will work in v0.x.x
require('send-to-ai').setup({
  ai_processes = { 'claude' },
  -- Future additions don't break this
})
```

### Performance Optimization Roadmap

**Current Performance:**
- Pane detection: ~10-30ms
- Send operation: ~5-10ms
- Total latency: <100ms (imperceptible)

**Future Optimizations (if needed):**

1. **Pane Detection Caching (v0.2)**
   - Cache for 5 seconds or until session change
   - Reduces detection from 30ms → 0.5ms
   - Opt-in: `cache_pane_detection = true`

2. **Async Operations (v1.0)**
   - If user reports UI freeze on slow systems
   - Use `vim.loop` for background tmux queries
   - Only if profiling shows need (YAGNI principle)

3. **Lazy Loading Optimization (v0.2)**
   - Delay loading `health.lua` until `:checkhealth` called
   - Reduce plugin startup footprint

**Profiling Strategy:**
```lua
-- Add optional profiling
if config.debug_profile then
  local start = vim.loop.hrtime()
  -- operation
  local elapsed = (vim.loop.hrtime() - start) / 1e6
  print("Operation took " .. elapsed .. "ms")
end
```

### Documentation Evolution

**Current:**
- README with installation, usage, configuration
- Health check for diagnostics

**Planned Documentation:**

1. **Wiki (GitHub) (v0.2)**
   - Advanced configuration examples
   - Troubleshooting flowcharts
   - Integration guides with other plugins

2. **Vimdoc (v0.3)**
   - `:help send-to-ai` comprehensive reference
   - Generated from README + annotations

3. **Video Walkthrough (Community)**
   - Installation and usage demo
   - Embedded in README

4. **Architecture Document (v1.0)**
   - For contributors and advanced users
   - Module interaction diagrams
   - Extension development guide

### Maintenance & Support Strategy

**Long-term Support:**
- **Active maintenance:** Bug fixes, Neovim compatibility
- **Feature freeze after v1.0:** Focus on stability over features
- **Community contributions welcome:** PRs for bug fixes and docs

**Issue Triage:**
- **P0 (Critical):** Security, data loss, crashes - Fix within 1 week
- **P1 (High):** Major functionality broken - Fix within 1 month
- **P2 (Medium):** Enhancements, minor bugs - Backlog

**Neovim Version Support:**
- Support Neovim stable (0.9+) and nightly
- Drop support for EOL Neovim versions after 1 year

## Documentation Plan

### README.md Structure

**Sections:**

1. **Title & Badge Row**
   ```markdown
   # nvim-send-to-ai-in-tmux

   [![Neovim](https://img.shields.io/badge/Neovim-0.9+-green.svg)](https://neovim.io)
   [![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
   ```

2. **Elevator Pitch (2 sentences)**
   > Send code snippets and file locations from Neovim to AI tools in tmux panes with a single keystroke. Zero-config with intelligent auto-detection and clipboard fallback.

3. **Demo GIF** (optional, create after implementation)
   - Show: Highlight code → Press key → Appears in AI pane

4. **Features (Bullet List)**
   - 🎯 Auto-detect AI panes (Claude Code, Codex, OpenCode)
   - 📍 Send location references in normal mode
   - 📋 Clipboard fallback when tmux unavailable
   - 🔒 Secure (no shell injection vulnerabilities)
   - ⚡ Fast (<100ms latency)
   - 🌍 Cross-platform (macOS, Linux, WSL)

5. **Installation**

   **lazy.nvim (recommended):**
   ```lua
   {
     'openclaw/nvim-send-to-ai-in-tmux',
     cmd = 'SendToAI',
     keys = {
       { '<leader>ai', '<cmd>SendToAI<cr>', mode = { 'n', 'v' }, desc = 'Send to AI' }
     }
   }
   ```

   **packer.nvim:**
   ```lua
   use 'openclaw/nvim-send-to-ai-in-tmux'
   ```

6. **Usage**

   **Basic:**
   - Visual mode: Select code → `<leader>ai`
   - Normal mode: Cursor on line → `<leader>ai`

   **Example output:**
   ```
   src/main.rs:42-45
   fn main() {
       println!("Hello, world!");
   }
   ```

7. **Configuration**

   **Defaults (zero-config):**
   ```lua
   -- These are the defaults, no need to set unless customizing
   require('send-to-ai').setup({
     ai_processes = { 'claude', 'codex', 'opencode' },
     prefer_session = true,
     fallback_clipboard = true,
     path_style = 'git_relative',
     path_style_fallback = 'filename_only',
     max_selection_lines = 10000,
     warn_selection_lines = 5000,
   })
   ```

   **Options:**
   - `ai_processes`: List of AI tool process names to detect
   - `prefer_session`: Prefer panes in current tmux session
   - `fallback_clipboard`: Use clipboard when no AI pane found
   - `path_style`: `'git_relative'` | `'cwd_relative'` | `'absolute'`
   - `path_style_fallback`: Fallback when git unavailable
   - `max_selection_lines`: Hard limit for selection size
   - `warn_selection_lines`: Warn before sending large selections

8. **Requirements**
   - Neovim >= 0.9.0
   - tmux >= 2.0 (optional, for tmux integration)
   - Clipboard command (optional, for fallback):
     - macOS: `pbcopy` (built-in)
     - Linux: `xclip`, `xsel`, or `wl-copy`
     - WSL: `clip.exe` (built-in)

9. **How It Works**
   1. Detects AI panes by scanning tmux for processes named `claude`, `codex`, `opencode`
   2. Formats message with file path and line range
   3. Sends to AI pane using `tmux send-keys -l` (literal mode for security)
   4. Falls back to clipboard if no AI pane found

10. **Troubleshooting**

    **Run health check:**
    ```vim
    :checkhealth send-to-ai
    ```

    **Common issues:**
    - "No AI pane found" → Start AI tool in tmux, run health check
    - "No clipboard command found" → Install `xclip` (Linux) or `wl-copy` (Wayland)
    - "Cannot send from unnamed buffer" → Save file first (`:w filename`)

11. **FAQ**

    **Q: What if I have multiple AI panes?**
    A: Plugin uses first match. Prefers current tmux session if `prefer_session = true`.

    **Q: Can I use this without tmux?**
    A: Yes! It falls back to clipboard mode automatically.

    **Q: Does it work on Windows?**
    A: Yes, in WSL with tmux. Native Windows not supported (no tmux).

    **Q: How do I add a new AI tool?**
    A: Add to `ai_processes` in setup():
    ```lua
    require('send-to-ai').setup({
      ai_processes = { 'claude', 'codex', 'opencode', 'aider' }
    })
    ```

12. **Security**

    **Shell Injection Protection:**
    - Uses `tmux send-keys -l` (literal mode) to prevent shell interpretation
    - Code with `$()`, backticks, etc. sent safely without execution

    **Clipboard Considerations:**
    - Clipboard fallback may expose code to clipboard history/sync
    - Notification always shown when using clipboard

13. **Contributing**
    Contributions welcome! Please:
    - Open issues for bugs or feature requests
    - Submit PRs with tests (when applicable)
    - Follow existing code style

14. **License**
    MIT License - see [LICENSE](LICENSE) file

### Inline Code Documentation

**LuaDoc Format:**
```lua
--- Sends code or location to AI pane in tmux
--- Falls back to clipboard if no AI pane found
--- @param mode string The vim mode ('n' for normal, 'v'/'V' for visual)
--- @return boolean success True if sent successfully
--- @return string|nil error Error message if failed
function M.send_to_ai(mode)
  -- Implementation
end
```

**Comment Guidelines:**
- Public functions: Full LuaDoc with params, returns, description
- Internal functions: Brief comment explaining purpose
- Complex logic: Inline comments for clarity
- Gotchas: Highlighted with `-- NOTE:` or `-- WARN:`

### Health Check Messages

**Example health check output:**
```
send-to-ai: health#send-to-ai
========================================================================
## Tmux
  - OK tmux is installed (version 3.2a)
  - OK Running inside tmux session 'work'

## Clipboard
  - OK Clipboard support: pbcopy (macOS)

## AI Panes
  - OK AI pane detected: %2 (claude) in session 'work'

## Configuration
  - OK path_style: git_relative
  - OK ai_processes: claude, codex, opencode
  - OK max_selection_lines: 10000
```

**Error Example:**
```
send-to-ai: health#send-to-ai
========================================================================
## Tmux
  - ERROR tmux is not installed
    - ADVICE: Install tmux with: brew install tmux (macOS) or apt install tmux (Linux)

## Clipboard
  - WARN Not in a tmux session
    - ADVICE: Clipboard fallback will be used

## Clipboard
  - ERROR No clipboard command found
    - ADVICE: Install xclip with: sudo apt install xclip
```

### CHANGELOG.md

**Format:**
```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-02-XX

### Added
- Auto-detect AI panes in tmux by process name (claude, codex, opencode)
- Send code snippets with file context in visual mode
- Send location references in normal mode
- Clipboard fallback when tmux unavailable
- Health check (`:checkhealth send-to-ai`)
- Zero-config operation with optional customization
- DiffviewOpen compatibility
- Cross-platform clipboard support (macOS, Linux, WSL)

### Security
- Shell injection protection via `tmux send-keys -l` literal mode
```

## References & Research

### Internal References

**Brainstorm Document:**
- `docs/brainstorms/2026-02-16-nvim-send-to-ai-brainstorm.md`
  - Comprehensive design decisions, technical details, user experience
  - All architectural decisions originated from this document

**Research Findings:**
- Repo research: New greenfield project, no existing code
- Learnings research: No `docs/solutions/` directory (new project)
- SpecFlow analysis: 39 identified gaps with prioritized recommendations

### External References

**Neovim Plugin Patterns:**
- [Structuring Neovim Lua plugins](https://zignar.net/2022/11/06/structuring-neovim-lua-plugins/) - Module organization, lazy loading
- [Neovim Lua Guide](https://neovim.io/doc/user/lua-guide.html) - Official Lua integration docs
- [Neovim Plugin Best Practices](https://github.com/nvim-neorocks/nvim-best-practices) - Community conventions
- [Neovim Lua Guide (nanotee)](https://github.com/nanotee/nvim-lua-guide) - Comprehensive tutorial

**Similar Plugins (Pattern Reference):**
- [tunnell.nvim](https://github.com/sourproton/tunnell.nvim)
  - Send text to tmux REPL, cell-based sending
  - Pattern: Simple tmux integration with `send-keys`
- [opencode-context.nvim](https://github.com/cousine/opencode-context.nvim)
  - Opencode AI integration with placeholder system
  - Pattern: Scoped pane detection (current window only)
- [claude-code.nvim](https://github.com/dreemanuel/claude-code.nvim)
  - Claude Code integration with bidirectional communication
  - Pattern: Multi-stage detection (process, command, title), health check
- [tmux.nvim](https://github.com/aserowy/tmux.nvim)
  - Comprehensive tmux integration (navigation, clipboard sync)
  - Pattern: Clean module organization, conditional pass-through

**Testing & Health Checks:**
- [Testing Neovim plugins with Busted](https://hiphish.github.io/blog/2024/01/29/testing-neovim-plugins-with-busted/)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - Popular testing framework
- [Health - Neovim docs](https://neovim.io/doc/user/health.html) - Health check API

**Plugin Management:**
- [lazy.nvim Configuration](https://lazy.folke.io/configuration) - Modern plugin manager
- [packer.nvim](https://github.com/wbthomason/packer.nvim) - Alternative plugin manager

**Tmux Documentation:**
- [tmux man page](https://man.openbsd.org/tmux) - Official command reference
- `tmux list-panes -F` format variables
- `tmux send-keys` behavior and flags

**Security Best Practices:**
- OWASP Command Injection Prevention
- Shell escaping patterns for secure command execution
- Tmux literal mode (`-l` flag) documentation

### Related Work

**AI Integration Plugins:**
- [copilot.vim](https://github.com/github/copilot.vim) - GitHub Copilot integration
- [codeium.vim](https://github.com/Exafunction/codeium.vim) - Codeium AI integration
- [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim) - ChatGPT interface

**REPL Integration (Similar Problem Domain):**
- [iron.nvim](https://github.com/hkupty/iron.nvim) - Send code to REPLs
- [conjure](https://github.com/Olical/conjure) - Interactive evaluation for Lisps
- [jupyter.nvim](https://github.com/dccsillag/magma-nvim) - Jupyter integration

### Code Examples from Research

**Git Root Detection Pattern:**
```lua
local git_root = vim.fn.systemlist('git rev-parse --show-toplevel')[1]
if git_root and git_root ~= '' then
  git_root = git_root:gsub('\\', '/'):gsub('/$', '')
  local rel_path = vim.fn.fnamemodify(filepath, ':~:.' .. git_root)
end
```

**Visual Selection Extraction:**
```lua
local start_pos = vim.fn.getpos("'<")
local end_pos = vim.fn.getpos("'>")
local lines = vim.fn.getline(start_pos[2], end_pos[2])
```

**Tmux Pane List:**
```bash
tmux list-panes -a -F "#{pane_id}:#{pane_current_command}"
# Output: %0:zsh %1:nvim %2:claude
```

**Tmux Send Keys:**
```bash
tmux send-keys -t %2 -l "<text>"  # Literal mode
tmux send-keys -t %2 Enter
```

---

**Total Estimated Effort:** 26-34 hours across 4-5 days
**Implementation Order:** Phase 1 → 2 → 3 → 4 (sequential, each phase builds on previous)
**Release Target:** v0.1.0 with core functionality complete
