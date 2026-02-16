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

  -- Determine mode: if called with range in visual mode, use visual; otherwise normal
  local mode = vim.fn.mode()

  -- Call main function
  send_to_ai.send_to_ai(mode)
end, {
  desc = 'Send code or location to AI in tmux pane',
  range = true,  -- Allow visual mode usage
})
