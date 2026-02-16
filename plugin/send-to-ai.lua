-- Prevent loading plugin twice
if vim.g.loaded_send_to_ai then
  return
end
vim.g.loaded_send_to_ai = 1

-- Create :SendToAI command
vim.api.nvim_create_user_command('SendToAI', function(opts)
  -- Lazy-load the main module
  local ok, send_to_ai = pcall(require, 'send-to-ai')

  if not ok then
    vim.notify('[send-to-ai] Failed to load plugin: ' .. send_to_ai, vim.log.levels.ERROR)
    return
  end

  -- Determine mode: check if called from visual mode
  -- vim.fn.mode() returns 'v', 'V', or '\22' (ctrl-v) in visual mode,
  -- and 'n' in normal mode. With <cmd> mappings, visual mode is preserved.
  -- Also check opts.range as fallback for : command-line invocation.
  local mode = vim.fn.mode()
  if mode == 'n' and opts.range > 0 then
    mode = 'v'
  end

  -- Call main function
  send_to_ai.send_to_ai(mode)
end, {
  desc = 'Send code or location to AI in tmux pane',
  range = true,  -- Allow visual mode usage
})
