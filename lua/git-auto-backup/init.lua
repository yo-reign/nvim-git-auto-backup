local M = {}

local defaults = {
  dirs = {},
  interval = 15,
  commit_prefix = "auto-backup",
  push = true,
  pull = true,
  pull_on_open = true,
  enabled = true,
}

local config = {}
local state = {
  is_running = false,
  should_abort = false,
  did_stash = {},
  last_sync = {},
  log_buffer = {},
  timer = nil,
  setup_done = false,
}

local LOG_MAX = 200

local function log(msg)
  table.insert(state.log_buffer, os.date("%H:%M:%S") .. " " .. msg)
  if #state.log_buffer > LOG_MAX then
    table.remove(state.log_buffer, 1)
  end
end

local function notify_error(msg)
  vim.schedule(function()
    vim.notify("git-auto-backup: " .. msg, vim.log.levels.ERROR)
  end)
  log("ERROR: " .. msg)
end

local function notify_warn(msg)
  vim.schedule(function()
    vim.notify("git-auto-backup: " .. msg, vim.log.levels.WARN)
  end)
  log("WARN: " .. msg)
end

local function expand_dir(dir)
  return vim.fn.expand(dir)
end

local function validate_dirs(dirs)
  local valid = {}
  for _, dir in ipairs(dirs) do
    if vim.fn.isdirectory(dir) == 0 then
      notify_warn(dir .. " does not exist, skipping")
    else
      local result = vim.fn.system("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --git-dir 2>/dev/null")
      if vim.v.shell_error ~= 0 then
        notify_warn(dir .. " is not a git repo, skipping")
      else
        table.insert(valid, dir)
      end
    end
  end
  return valid
end

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend("force", {}, defaults, opts)

  local raw_dirs = config.dirs
  config.dirs = {}
  for _, dir in ipairs(raw_dirs) do
    table.insert(config.dirs, expand_dir(dir))
  end
  config.dirs = validate_dirs(config.dirs)

  state.setup_done = true
end

function M.get_config()
  return vim.deepcopy(config)
end

function M.get_state()
  return vim.deepcopy(state)
end

return M
