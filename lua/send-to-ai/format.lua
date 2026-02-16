local M = {}

--- Get git repository root for a file
--- @param filepath string Absolute file path
--- @return string|nil Git root path or nil if not in git repo
local function get_git_root(filepath)
  -- Get the directory containing the file
  local dir = vim.fn.fnamemodify(filepath, ':h')

  -- Try to find git root
  local ok, git_root = pcall(vim.fn.systemlist,
    string.format('git -C "%s" rev-parse --show-toplevel 2>/dev/null', dir))

  if not ok or not git_root or #git_root == 0 or git_root[1] == '' then
    return nil
  end

  -- Normalize path: convert backslashes to forward slashes, remove trailing slash
  local root = git_root[1]:gsub([[\]], '/'):gsub('/$', '')
  return root
end

--- Get git-relative path for a file
--- @param filepath string Absolute file path
--- @param config table Configuration
--- @return string Git-relative path or fallback
local function get_git_relative_path(filepath, config)
  local git_root = get_git_root(filepath)

  if not git_root then
    -- Fall back based on config
    if config.path_style_fallback == 'cwd_relative' then
      return vim.fn.fnamemodify(filepath, ':.')
    elseif config.path_style_fallback == 'absolute' then
      return vim.fn.fnamemodify(filepath, ':p')
    else
      -- filename_only
      return vim.fn.fnamemodify(filepath, ':t')
    end
  end

  -- Make filepath absolute and normalized
  local abs_path = vim.fn.fnamemodify(filepath, ':p'):gsub([[\]], '/')

  -- Remove git root prefix to get relative path
  local rel_path = abs_path:gsub('^' .. vim.pesc(git_root) .. '/', '')

  return rel_path
end

--- Get current working directory relative path
--- @param filepath string Absolute file path
--- @return string CWD-relative path
local function get_cwd_relative_path(filepath)
  return vim.fn.fnamemodify(filepath, ':.')
end

--- Get absolute path
--- @param filepath string File path
--- @return string Absolute path
local function get_absolute_path(filepath)
  return vim.fn.fnamemodify(filepath, ':p')
end

--- Resolve file path based on configuration
--- @param filepath string File path
--- @param config table Configuration
--- @return string Resolved path
function M.resolve_path(filepath, config)
  -- Handle empty filepath
  if not filepath or filepath == '' then
    return '[No Name]'
  end

  -- Normalize path separators to forward slashes
  filepath = filepath:gsub([[\]], '/')

  if config.path_style == 'git_relative' then
    return get_git_relative_path(filepath, config)
  elseif config.path_style == 'cwd_relative' then
    return get_cwd_relative_path(filepath)
  elseif config.path_style == 'absolute' then
    return get_absolute_path(filepath)
  else
    -- Default to git_relative if somehow invalid
    return get_git_relative_path(filepath, config)
  end
end

--- Format location message (normal mode: file:line)
--- @param filepath string File path
--- @param line_number number Line number
--- @param config table Configuration
--- @return string Formatted message
function M.format_location_message(filepath, line_number, config)
  local path = M.resolve_path(filepath, config)
  return string.format('File: %s:%d', path, line_number)
end

--- Format code message (visual mode: file:start-end\ncode)
--- @param filepath string File path
--- @param line_range table Line range with 'start' and 'end' keys
--- @param lines table Array of code lines
--- @param config table Configuration
--- @return string Formatted message
function M.format_code_message(filepath, line_range, lines, config)
  local path = M.resolve_path(filepath, config)
  local header = string.format('File: %s:%d-%d', path, line_range.start, line_range['end'])

  -- Join lines preserving all whitespace
  local code = table.concat(lines, '\n')

  return string.format('%s\n%s', header, code)
end

return M
