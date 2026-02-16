local M = {}

-- Cache for clipboard command to avoid repeated detection
local clipboard_cmd_cache = nil

--- Detect available clipboard command
--- @return string|nil Clipboard command or nil if none found
function M.detect_clipboard_command()
  -- Return cached result if available
  if clipboard_cmd_cache then
    return clipboard_cmd_cache
  end

  -- Try commands in order of preference
  local commands = {
    'pbcopy',      -- macOS
    'clip.exe',    -- WSL (Windows clipboard bridge)
    'wl-copy',     -- Wayland (Linux)
    'xclip',       -- X11 (Linux)
    'xsel',        -- X11 fallback (Linux)
  }

  for _, cmd in ipairs(commands) do
    if vim.fn.executable(cmd) == 1 then
      clipboard_cmd_cache = cmd
      return cmd
    end
  end

  return nil
end

--- Copy text to system clipboard
--- @param text string Text to copy
--- @return boolean success
--- @return string|nil error Error message if failed
function M.copy_to_clipboard(text)
  local cmd = M.detect_clipboard_command()

  if not cmd then
    return false, "No clipboard command found. Install pbcopy (macOS), xclip, or wl-copy (Linux)."
  end

  -- Different commands have different input methods
  local shell_cmd
  if cmd == 'xclip' then
    -- xclip needs -selection clipboard flag
    shell_cmd = string.format('echo %s | xclip -selection clipboard', vim.fn.shellescape(text))
  elseif cmd == 'xsel' then
    -- xsel needs -b flag for clipboard
    shell_cmd = string.format('echo %s | xsel -b', vim.fn.shellescape(text))
  else
    -- pbcopy, wl-copy, clip.exe all read from stdin
    shell_cmd = string.format('echo %s | %s', vim.fn.shellescape(text), cmd)
  end

  local ok, result = pcall(vim.fn.system, shell_cmd)

  if not ok or vim.v.shell_error ~= 0 then
    return false, string.format("Clipboard copy failed: %s", result or "unknown error")
  end

  return true, nil
end

return M
