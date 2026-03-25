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
  local expanded = vim.fn.fnamemodify(dir, ":p")
  -- fnamemodify :p appends trailing / for directories; strip it for consistency
  return (expanded:gsub("/$", ""))
end

local function validate_dirs(dirs)
  local valid = {}
  for _, dir in ipairs(dirs) do
    if vim.fn.isdirectory(dir) == 0 then
      notify_warn(dir .. " does not exist, skipping")
    else
      vim.fn.system({ "git", "-C", dir, "rev-parse", "--git-dir" })
      if vim.v.shell_error ~= 0 then
        notify_warn(dir .. " is not a git repo, skipping")
      else
        table.insert(valid, dir)
      end
    end
  end
  return valid
end

local function git_sync(dir, cmd)
  local full_cmd = "git -C " .. vim.fn.shellescape(dir) .. " " .. cmd
  local output = vim.fn.system(full_cmd)
  local exit_code = vim.v.shell_error
  log(dir .. " $ " .. cmd .. " -> exit " .. exit_code)
  if output and output ~= "" then
    log(output)
  end
  return output, exit_code
end

local function make_commit_message()
  return config.commit_prefix .. ": " .. os.date("%Y-%m-%dT%H:%M:%S%z")
end

-- Synchronous sync cycle (used by VimLeavePre and tests)
-- When include_pull is true, runs full cycle (steps 1-7)
-- When include_pull is false, runs exit cycle (steps 4-7)
function M.sync_dir_sync(dir, include_pull)
  if include_pull == nil then include_pull = false end

  local did_stash = false

  if include_pull and config.pull then
    -- Check for uncommitted changes (including untracked)
    local status_out, _ = git_sync(dir, "status --porcelain")
    if status_out and status_out ~= "" then
      -- Step 1: stash (including untracked files)
      local _, stash_exit = git_sync(dir, "stash -u")
      if stash_exit == 0 then
        did_stash = true
      end
    end

    -- Step 2: pull
    local _, pull_exit = git_sync(dir, "pull --rebase")
    if pull_exit ~= 0 then
      notify_error("conflict in " .. dir .. " — check :GitAutoBackupLog")
      if did_stash then
        git_sync(dir, "stash pop")
      end
      return
    end

    -- Step 3: stash pop
    if did_stash then
      local _, pop_exit = git_sync(dir, "stash pop")
      if pop_exit ~= 0 then
        notify_error("stash conflict in " .. dir .. " — check :GitAutoBackupLog")
        return
      end
    end
  end

  -- Step 4: add all
  git_sync(dir, "add -A")

  -- Step 5: check for changes
  local status_out, _ = git_sync(dir, "status --porcelain")
  if not status_out or status_out == "" then
    return -- nothing to commit
  end

  -- Step 6: commit
  local commit_msg = make_commit_message()
  local _, commit_exit = git_sync(dir, "commit -m " .. vim.fn.shellescape(commit_msg))
  if commit_exit ~= 0 then
    notify_error("commit failed in " .. dir .. " — check :GitAutoBackupLog")
    return
  end

  state.last_sync[dir] = os.date("%Y-%m-%dT%H:%M:%S%z")

  -- Step 7: push
  if config.push then
    local _, push_exit = git_sync(dir, "push")
    if push_exit ~= 0 then
      notify_error("push failed in " .. dir .. " — check :GitAutoBackupLog")
    end
  end
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
