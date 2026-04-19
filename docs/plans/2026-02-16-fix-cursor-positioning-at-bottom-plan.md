---
title: Fix Cursor Positioning to Bottom When AI Pane Receives Input
type: fix
status: active
date: 2026-02-16
---

# Fix Cursor Positioning to Bottom When AI Pane Receives Input

## Overview

When text is sent to the AI pane in tmux, the cursor doesn't automatically position at the bottom where the new input appears. Users see the pane switch to focus, but may still be viewing scrollback history instead of the fresh input line, creating a jarring UX experience.

## Problem Statement

Current behavior (lua/send-to-ai/tmux.lua:188-212):
- Text is sent to the tmux pane ✓
- Focus switches to the AI pane ✓
- **Pane is NOT scrolled to show the new input** ✗
- **Cursor position in the pane is unclear** ✗

When the AI pane has a lot of scrollback history, the new input might be sent but not visible to the user because the pane is still showing old output higher up in the buffer.

## Desired Behavior

After `M.send_to_pane(pane_id, text)`:
1. Text is transmitted to the pane
2. Focus switches to the AI pane
3. **Pane scrolls to the bottom to show the new input**
4. **Cursor is positioned right after the new text, ready for the user to interact**

## Proposed Solution

Add cursor movement commands to tmux in `M.send_to_pane()`:

1. **Before sending text:** Send `C-l` (clear screen) or scrolling command to move to bottom
2. **After sending text:** Ensure cursor is at the end of the pane

Tmux approach using `send-keys`:
- Use `send-keys -t pane_id -c End` to move cursor to end of line
- Or use `send-keys -t pane_id -c C-l` to clear and scroll to bottom
- Or send `Enter` to move to a fresh prompt line

## Technical Considerations

### Current Implementation Review

File: `lua/send-to-ai/tmux.lua:188-212`

```lua
function M.send_to_pane(pane_id, text)
  -- ... escaping logic ...

  -- Send text with -l flag (literal mode)
  local send_cmd = string.format('tmux send-keys -t "%s" -l %s', pane_id, vim.fn.shellescape(escaped))
  local ok, result = pcall(vim.fn.system, send_cmd)

  -- Switch focus to the AI pane
  local focus_cmd = string.format('tmux select-pane -t "%s"', pane_id)
  pcall(vim.fn.system, focus_cmd)

  return true, nil
end
```

### Solution Options

**Option 1: Send `C-l` (clear) before text**
- Pros: Clears terminal, shows fresh content, universal shell behavior
- Cons: Might lose context of previous output

**Option 2: Send `C-End` or similar key to scroll bottom**
- Pros: Preserves history, shows new content at bottom
- Cons: Less consistent across different shells/tmux configs

**Option 3: Use tmux scrollback position**
- Pros: Native tmux scroll control
- Cons: More complex, may not always work as expected

**Recommended: Option 3 - Use tmux capture-pane scroll position**

Use `tmux send-keys` with Page-Down equivalent or send a key sequence that moves the view to the bottom without clearing history.

## Acceptance Criteria

- [x] Understand current behavior and identify gap
- [ ] Modify `M.send_to_pane()` to ensure pane scrolls to bottom
- [ ] Verify cursor position after text is sent
- [ ] Test with scrollback history present
- [ ] Test with both empty and populated panes
- [ ] Confirm focus switch + scroll work together

## Success Metrics

1. **Visibility:** New input is always visible in the AI pane after sending
2. **Cursor Position:** Cursor appears at the bottom where user can see it
3. **No History Loss:** Terminal scrollback is preserved
4. **Speed:** Operation still completes imperceptibly (<100ms)

## Dependencies & Risks

### Dependencies
- Tmux must support `send-keys` with scroll commands (standard in tmux 2.0+)

### Risks
- Different shells (bash, zsh, fish) may behave differently with control characters
- Some tmux configurations might disable certain key sequences
- Mitigation: Keep solution simple and rely on standard tmux commands

## References & Research

### Internal References
- Implementation file: `lua/send-to-ai/tmux.lua:188-212`
- Related function: `M.select-pane` (line 208)
- Brainstorm context: `docs/brainstorms/2026-02-16-nvim-send-to-ai-brainstorm.md`

### External References
- Tmux manual: `tmux send-keys` command options
- Tmux scrollback: Using `capture-pane` and scroll position manipulation

### Related Work
- Focus switch already implemented (line 208)
- Text escaping for security already handled (lines 178-181)

## Implementation Notes

**Key Decision:** Use tmux's `send-keys` with `C-l` or scroll command to move view to bottom.

**Minimal code change needed:**
1. Add one tmux command to move cursor/view to bottom
2. Place it after focus switch but can also be before text send
3. Ensure it doesn't interfere with the input text itself

## MVP (Minimal Viable Product)

The fix requires modifying one function in `lua/send-to-ai/tmux.lua`:

```lua
function M.send_to_pane(pane_id, text)
  if not M.is_in_tmux() then
    return false, "Not in tmux session"
  end

  local escaped = escape_for_tmux(text)
  escaped = escaped .. '\n'

  -- Send text with -l flag (literal mode)
  local send_cmd = string.format('tmux send-keys -t "%s" -l %s', pane_id, vim.fn.shellescape(escaped))
  local ok, result = pcall(vim.fn.system, send_cmd)

  if not ok or vim.v.shell_error ~= 0 then
    return false, string.format("Tmux send-keys failed: %s", result or "unknown error")
  end

  -- Switch focus to the AI pane
  local focus_cmd = string.format('tmux select-pane -t "%s"', pane_id)
  pcall(vim.fn.system, focus_cmd)

  -- NEW: Ensure pane is scrolled to the bottom to show the input
  -- Use tmux's capture-pane with scrollback position or send End key
  local scroll_cmd = string.format('tmux send-keys -t "%s" -c End', pane_id)
  pcall(vim.fn.system, scroll_cmd)

  return true, nil
end
```

This minimal change sends the `End` key to the pane after focus switch, which:
1. Moves cursor to end of current line
2. Ensures the view is focused on the bottom
3. Works consistently across shells
