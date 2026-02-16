# nvim-send-to-ai-in-tmux

[![Neovim](https://img.shields.io/badge/Neovim-0.9+-green.svg)](https://neovim.io)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> Send code snippets and file locations from Neovim to AI tools in tmux panes with a single keystroke. Zero-config with intelligent auto-detection and clipboard fallback.

## Features

- 🎯 **Auto-detect AI panes** - Finds Claude Code, Codex, OpenCode automatically
- 📍 **Smart context sharing** - Send location references in normal mode, code in visual mode
- 📋 **Clipboard fallback** - Works without tmux, gracefully falls back to system clipboard
- 🔒 **Secure** - No shell injection vulnerabilities (uses tmux literal mode)
- ⚡ **Fast** - Operations complete in <100ms
- 🌍 **Cross-platform** - macOS, Linux (X11/Wayland), WSL
- 🎨 **Zero-config** - Works immediately with sensible defaults
- 🔧 **DiffviewOpen compatible** - Works in diff buffers using visual marks

## Installation

### lazy.nvim (recommended)

```lua
{
  'openclaw/nvim-send-to-ai-in-tmux',
  cmd = 'SendToAI',
  keys = {
    { '<leader>ai', '<cmd>SendToAI<cr>', mode = { 'n', 'v' }, desc = 'Send to AI' }
  },
  opts = {}  -- Optional: customize configuration here
}
```

### packer.nvim

```lua
use 'openclaw/nvim-send-to-ai-in-tmux'

-- Optional keybinding
vim.keymap.set({ 'n', 'v' }, '<leader>ai', '<cmd>SendToAI<cr>', { desc = 'Send to AI' })
```

### Manual

```bash
git clone https://github.com/openclaw/nvim-send-to-ai-in-tmux ~/.local/share/nvim/site/pack/plugins/start/nvim-send-to-ai-in-tmux
```

## Usage

### Basic Usage

**Visual mode** - Send code with file context:
1. Select code with `v`, `V`, or `Ctrl-v`
2. Press `<leader>ai` (or run `:SendToAI`)
3. Code appears in AI pane with location:

```
src/parser.rs:142-156
fn parse_expression(&self) -> Result<Expr> {
    // ... selected code block
}
```

**Normal mode** - Send file location reference:
1. Position cursor on line of interest
2. Press `<leader>ai` (or run `:SendToAI`)
3. Location appears in AI pane:

```
src/parser.rs:142
```

### Workflow Example

```lua
-- In tmux session:
-- Pane 1: nvim (editing code)
-- Pane 2: claude (AI assistant running)

-- 1. In Neovim, highlight a function
-- 2. Press <leader>ai
-- 3. Function code instantly appears in Claude pane
-- 4. Ask Claude about it without leaving Neovim
```

## Configuration

### Defaults (zero-config)

The plugin works immediately without any configuration. These are the defaults:

```lua
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

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ai_processes` | `string[]` | `{'claude', 'codex', 'opencode'}` | AI tool process names to detect |
| `prefer_session` | `boolean` | `true` | Prefer panes in current tmux session |
| `fallback_clipboard` | `boolean` | `true` | Use clipboard when no AI pane found |
| `path_style` | `string` | `'git_relative'` | Path style: `'git_relative'`, `'cwd_relative'`, `'absolute'` |
| `path_style_fallback` | `string` | `'filename_only'` | Fallback when git unavailable: `'filename_only'`, `'cwd_relative'`, `'absolute'` |
| `max_selection_lines` | `number` | `10000` | Hard limit for selection size |
| `warn_selection_lines` | `number` | `5000` | Warn before sending large selections |

### Customization Examples

**Add a new AI tool (e.g., Aider):**

```lua
require('send-to-ai').setup({
  ai_processes = { 'claude', 'codex', 'opencode', 'aider' }
})
```

**Use absolute paths:**

```lua
require('send-to-ai').setup({
  path_style = 'absolute'
})
```

**Disable clipboard fallback (tmux-only mode):**

```lua
require('send-to-ai').setup({
  fallback_clipboard = false
})
```

## Requirements

### Required

- **Neovim** >= 0.9.0

### Optional (for full functionality)

- **tmux** >= 2.0 (for AI pane detection and sending)
- **git** >= 2.0 (for git-relative paths)
- **Clipboard command** (for fallback when tmux unavailable):
  - macOS: `pbcopy` (built-in)
  - Linux X11: `xclip` or `xsel`
  - Linux Wayland: `wl-copy` (install: `sudo apt install wl-clipboard`)
  - WSL: `clip.exe` (built-in)

### AI Tool Setup

Start one of these AI tools in a tmux pane:

- [Claude Code CLI](https://docs.anthropic.com/claude-code)
- [GitHub Codex](https://github.com/features/copilot)
- [OpenCode](https://github.com/opencode)
- Custom AI tools (add to `ai_processes` config)

## How It Works

1. **Detects AI panes** by scanning tmux for processes named `claude`, `codex`, `opencode`, etc.
2. **Formats message** with file path (git-relative by default) and line range
3. **Sends securely** using `tmux send-keys -l` (literal mode prevents shell injection)
4. **Falls back gracefully** to clipboard if no AI pane is found or tmux is unavailable

### Message Format

**Visual mode message:**
```
<git_relative_path>:<start_line>-<end_line>
<code_block>
```

**Normal mode message:**
```
<git_relative_path>:<line_number>
```

## Troubleshooting

### Run Health Check

The health check diagnoses common issues:

```vim
:checkhealth send-to-ai
```

### Common Issues

**"No AI pane found"**
- ✅ Start an AI tool (claude, codex, opencode) in a tmux pane
- ✅ Run `:checkhealth send-to-ai` to verify detection
- ✅ Check if your AI tool process name matches `ai_processes` config
- ✅ Customize `ai_processes` if needed

**"No clipboard command found"**
- ✅ macOS: `pbcopy` is built-in
- ✅ Linux X11: Install `xclip` with `sudo apt install xclip`
- ✅ Linux Wayland: Install `wl-copy` with `sudo apt install wl-clipboard`
- ✅ WSL: `clip.exe` is built-in

**"Cannot send from unnamed buffer"**
- ✅ Save the file first: `:w filename.ext`
- ✅ Or use visual mode to copy code only (without file reference)

**"Selection too large"**
- ✅ Select a smaller range (plugin limits selections to 10,000 lines)
- ✅ Increase limit in config: `max_selection_lines = 20000`

## FAQ

### What if I have multiple AI panes?

The plugin uses the first match. If `prefer_session = true` (default), it prefers panes in your current tmux session over other sessions.

A notification shows which pane was selected:
```
Multiple AI panes found. Using %2 (claude)
```

Future versions may add an interactive picker (`:SendToAI select`).

### Can I use this without tmux?

Yes! The plugin automatically falls back to clipboard mode:
1. Code is copied to system clipboard
2. Notification shows: `"No AI pane found. Copied to clipboard."`
3. Paste into your AI tool manually

### Does this work on Windows?

Yes, in **WSL** (Windows Subsystem for Linux) with tmux installed. Native Windows is not supported (no tmux).

### How do I add a new AI tool?

Add its process name to `ai_processes` in your config:

```lua
require('send-to-ai').setup({
  ai_processes = { 'claude', 'codex', 'opencode', 'aider', 'your-ai-tool' }
})
```

The plugin uses substring matching, so `'claude'` matches processes like:
- `claude`
- `claude-code-cli`
- `/usr/bin/claude --flags`

### Can I customize the message format?

Currently, the format is fixed (`file:line` or `file:start-end\ncode`). Custom templates may be added in future versions based on user feedback.

### Does this work in DiffviewOpen?

Yes! The plugin uses visual marks (`'<`, `'>`) which work correctly in diff buffers.

## Security

### Shell Injection Protection

The plugin uses `tmux send-keys -l` (literal mode) to prevent shell interpretation of special characters. Code containing backticks, `$()`, quotes, etc. is sent safely without execution.

**Example:** This code is sent as text, not executed:
```python
password = "$(cat /etc/passwd)"  # Safe: sent as literal string
data = `curl evil.com`           # Safe: backticks not interpreted
```

### Clipboard Considerations

When clipboard fallback is used, code is copied to system clipboard. Be aware:
- ⚠️ Clipboard history/managers may store sensitive code
- ⚠️ Cloud sync services may sync clipboard contents
- ℹ️ A notification always appears when clipboard is used

To disable clipboard fallback:
```lua
require('send-to-ai').setup({
  fallback_clipboard = false
})
```

## Contributing

Contributions are welcome! Please:

- Open [issues](https://github.com/openclaw/nvim-send-to-ai-in-tmux/issues) for bugs or feature requests
- Submit pull requests with clear descriptions
- Follow existing code style and patterns
- Add tests when applicable

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Made with ❤️ for AI-assisted development workflows**
