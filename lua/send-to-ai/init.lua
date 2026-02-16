local M = {}

local config = require('send-to-ai.config')
local format = require('send-to-ai.format')
local tmux = require('send-to-ai.tmux')
local clipboard = require('send-to-ai.clipboard')

--- Setup plugin with user configuration
--- @param user_config table|nil User configuration
function M.setup(user_config)
  config.setup(user_config)
end

--- Check if buffer is valid for sending
--- @param bufnr number Buffer number
--- @return boolean valid
--- @return string|nil error Error message if invalid
local function validate_buffer(bufnr)
  -- Check if buffer is named
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if not bufname or bufname == '' then
    return false, "Cannot send from unnamed buffer. Save file first or use visual mode to copy code."
  end

  -- Check buffer type (reject special buffers)
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= '' then
    if buftype == 'help' then
      return false, "Cannot send from help buffer"
    elseif buftype == 'terminal' then
      return false, "Cannot send from terminal buffer"
    elseif buftype == 'quickfix' then
      return false, "Cannot send from quickfix buffer"
    else
      return false, string.format("Cannot send from special buffer: %s", buftype)
    end
  end

  -- Check for special buffer patterns (oil.nvim, fugitive, etc.)
  if bufname:match('^oil://') then
    return false, "Cannot send from oil.nvim buffer"
  elseif bufname:match('^fugitive://') then
    return false, "Cannot send from fugitive buffer"
  elseif bufname:match('^term://') then
    return false, "Cannot send from terminal buffer"
  end

  return true, nil
end

--- Get visual selection with line range
--- @return table|nil lines Array of selected lines
--- @return table|nil range {start, end} line numbers
--- @return string|nil error Error message if failed
local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  -- Validate selection
  if start_line == 0 or end_line == 0 then
    return nil, nil, "Invalid selection"
  end

  -- Ensure start is before end
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end

  -- Get lines from buffer
  local lines = vim.fn.getline(start_line, end_line)

  return lines, { start = start_line, ['end'] = end_line }, nil
end

--- Validate selection size
--- @param line_count number Number of lines in selection
--- @param cfg table Configuration
--- @return boolean valid
--- @return string|nil error Error message or warning
local function validate_selection_size(line_count, cfg)
  -- Hard limit
  if line_count > cfg.max_selection_lines then
    return false, string.format(
      "Selection too large (%d lines). Maximum is %d lines. Please select a smaller range.",
      line_count,
      cfg.max_selection_lines
    )
  end

  -- Warning threshold
  if line_count > cfg.warn_selection_lines then
    -- For now, just warn but allow (could add confirmation in future)
    vim.notify(
      string.format("Selection is large (%d lines). Sending...", line_count),
      vim.log.levels.WARN
    )
  end

  return true, nil
end

--- Send content to AI pane or clipboard
--- @param content string Content to send
--- @return boolean success
--- @return string|nil error Error type: nil (success), "fallback" (used clipboard), or error message
local function send(content)
  local cfg = config.get()

  -- Try tmux first
  local pane_id, err = tmux.find_ai_pane(cfg)

  if not pane_id then
    -- No AI pane found, try clipboard fallback
    if not cfg.fallback_clipboard then
      return false, "No AI pane found and clipboard fallback is disabled"
    end

    vim.notify("No AI pane found. Trying clipboard...", vim.log.levels.WARN)

    local ok, clip_err = clipboard.copy_to_clipboard(content)
    if not ok then
      vim.notify(string.format("Failed: %s", clip_err), vim.log.levels.ERROR)
      return false, clip_err
    end

    vim.notify("Copied to clipboard", vim.log.levels.INFO)
    return true, "fallback"
  end

  -- Send to tmux pane
  local ok, send_err = tmux.send_to_pane(pane_id, content)

  if not ok then
    -- Tmux send failed, retry with clipboard if enabled
    if cfg.fallback_clipboard then
      vim.notify(
        string.format("Pane send failed: %s. Trying clipboard...", send_err),
        vim.log.levels.WARN
      )

      local clip_ok, clip_err = clipboard.copy_to_clipboard(content)
      if clip_ok then
        vim.notify("Copied to clipboard", vim.log.levels.INFO)
        return true, "fallback"
      else
        vim.notify(string.format("Failed: %s", clip_err), vim.log.levels.ERROR)
        return false, clip_err
      end
    end

    vim.notify(string.format("Failed: %s", send_err), vim.log.levels.ERROR)
    return false, send_err
  end

  vim.notify(string.format("Sent to AI pane %s", pane_id), vim.log.levels.INFO)
  return true, nil
end

--- Main entry point: Send code or location to AI
--- @param mode string|nil Vim mode ('n' for normal, 'v'/'V' for visual), defaults to current mode
function M.send_to_ai(mode)
  mode = mode or vim.fn.mode()
  local cfg = config.get()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Validate buffer
  local valid, err = validate_buffer(bufnr)
  if not valid then
    vim.notify(string.format("[send-to-ai] %s", err), vim.log.levels.ERROR)
    return
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Handle based on mode
  if mode == 'n' then
    -- Normal mode: send location (file:line)
    local line_number = vim.fn.line('.')
    local message = format.format_location_message(filepath, line_number, cfg)
    send(message)
  else
    -- Visual mode: send code with context
    local lines, range, selection_err = get_visual_selection()

    if not lines then
      vim.notify(
        string.format("[send-to-ai] %s", selection_err or "Failed to get selection"),
        vim.log.levels.ERROR
      )
      return
    end

    -- Validate selection size
    local line_count = range['end'] - range.start + 1
    local size_valid, size_err = validate_selection_size(line_count, cfg)

    if not size_valid then
      vim.notify(string.format("[send-to-ai] %s", size_err), vim.log.levels.ERROR)
      return
    end

    -- Format and send code message
    local message = format.format_code_message(filepath, range, lines, cfg)
    send(message)
  end
end

return M
