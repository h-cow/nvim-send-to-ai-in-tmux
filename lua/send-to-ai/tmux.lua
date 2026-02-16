local M = {}

--- Check if running inside tmux
--- @return boolean True if in tmux session
function M.is_in_tmux()
  return vim.env.TMUX ~= nil
end

--- Get current tmux session name
--- @return string|nil Session name or nil if not in tmux
--- @return string|nil Error message
local function get_current_session()
  if not M.is_in_tmux() then
    return nil, "Not in tmux session"
  end

  local ok, result = pcall(vim.fn.systemlist, 'tmux display-message -p "#{session_name}"')
  if not ok or not result or #result == 0 or result[1] == '' then
    return nil, "Failed to get tmux session name"
  end

  return result[1], nil
end

--- List all tmux panes with their process information
--- @return table|nil Array of pane info {session, pane_id, command}
--- @return string|nil Error message
local function list_all_panes()
  if not M.is_in_tmux() then
    return nil, "Not in tmux session"
  end

  local ok, panes = pcall(vim.fn.systemlist,
    'tmux list-panes -a -F "#{session_name}:#{pane_id}:#{pane_current_command}"')

  if not ok or not panes or #panes == 0 then
    return nil, "Failed to query tmux panes"
  end

  -- Parse pane information
  local pane_list = {}
  for _, pane_info in ipairs(panes) do
    -- Format: session_name:pane_id:command
    local session, pane_id, command = pane_info:match("^([^:]+):([^:]+):(.+)$")
    if session and pane_id and command then
      table.insert(pane_list, {
        session = session,
        pane_id = pane_id,
        command = command,
      })
    end
  end

  return pane_list, nil
end

--- Find AI pane based on process names in config
--- @param config table Configuration with ai_processes list
--- @return string|nil Pane ID or nil if not found
--- @return string|nil Error message
function M.find_ai_pane(config)
  if not M.is_in_tmux() then
    return nil, "Not in tmux session"
  end

  -- Get current session if prefer_session is enabled
  local current_session = nil
  if config.prefer_session then
    current_session, _ = get_current_session()
  end

  -- List all panes
  local panes, err = list_all_panes()
  if not panes then
    return nil, err or "Failed to list tmux panes"
  end

  -- Find AI panes (substring match, case-insensitive)
  local ai_panes = {}
  for _, pane in ipairs(panes) do
    local cmd_lower = pane.command:lower()
    for _, ai_process in ipairs(config.ai_processes) do
      if cmd_lower:find(ai_process:lower(), 1, true) then
        table.insert(ai_panes, pane)
        break
      end
    end
  end

  if #ai_panes == 0 then
    return nil, "No AI panes found"
  end

  -- Prefer current session if enabled
  if current_session and config.prefer_session then
    for _, pane in ipairs(ai_panes) do
      if pane.session == current_session then
        return pane.pane_id, nil
      end
    end
  end

  -- Return first match
  local selected = ai_panes[1]

  -- Notify if multiple panes found
  if #ai_panes > 1 then
    vim.notify(
      string.format("Multiple AI panes found. Using %s (%s)", selected.pane_id, selected.command),
      vim.log.levels.INFO
    )
  end

  return selected.pane_id, nil
end

--- Escape text for tmux literal mode
--- @param text string Text to escape
--- @return string Escaped text
local function escape_for_tmux(text)
  -- In literal mode (-l), only backslashes need escaping
  return text:gsub([[\]], [[\\]])
end

--- Send text to tmux pane with literal mode (secure against shell injection)
--- @param pane_id string Tmux pane ID (e.g., "%2")
--- @param text string Text to send
--- @return boolean success
--- @return string|nil error Error message if failed
function M.send_to_pane(pane_id, text)
  if not M.is_in_tmux() then
    return false, "Not in tmux session"
  end

  -- Escape text for tmux literal mode
  local escaped = escape_for_tmux(text)

  -- Send text with -l flag (literal mode - prevents shell interpretation)
  local send_cmd = string.format('tmux send-keys -t "%s" -l %s', pane_id, vim.fn.shellescape(escaped))
  local ok, result = pcall(vim.fn.system, send_cmd)

  if not ok or vim.v.shell_error ~= 0 then
    return false, string.format("Tmux send-keys failed: %s", result or "unknown error")
  end

  -- Send Enter separately (cannot use -l with Enter key)
  local enter_cmd = string.format('tmux send-keys -t "%s" Enter', pane_id)
  ok, result = pcall(vim.fn.system, enter_cmd)

  if not ok or vim.v.shell_error ~= 0 then
    return false, string.format("Failed to send Enter: %s", result or "unknown error")
  end

  return true, nil
end

return M
