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

local function git_sync(dir, args)
  local full_cmd = vim.list_extend({ "git", "-C", dir }, args)
  local output = vim.fn.system(full_cmd)
  local exit_code = vim.v.shell_error
  log(dir .. " $ git " .. table.concat(args, " ") .. " -> exit " .. exit_code)
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
    local status_out, _ = git_sync(dir, {"status", "--porcelain"})
    if status_out and status_out ~= "" then
      -- Step 1: stash (including untracked files)
      local _, stash_exit = git_sync(dir, {"stash", "-u"})
      if stash_exit ~= 0 then
        notify_error("stash failed in " .. dir .. " — check :GitAutoBackupLog")
        return
      end
      did_stash = true
    end

    -- Step 2: pull
    local _, pull_exit = git_sync(dir, {"pull", "--rebase"})
    if pull_exit ~= 0 then
      notify_error("conflict in " .. dir .. " — check :GitAutoBackupLog")
      if did_stash then
        git_sync(dir, {"stash", "pop"})
      end
      return
    end

    -- Step 3: stash pop
    if did_stash then
      local _, pop_exit = git_sync(dir, {"stash", "pop"})
      if pop_exit ~= 0 then
        notify_error("stash conflict in " .. dir .. " — check :GitAutoBackupLog")
        return
      end
    end
  end

  -- Step 4: add all
  local _, add_exit = git_sync(dir, {"add", "-A"})
  if add_exit ~= 0 then
    notify_error("git add failed in " .. dir .. " — check :GitAutoBackupLog")
    return
  end

  -- Step 5: check for changes
  local post_add_status, _ = git_sync(dir, {"status", "--porcelain"})
  if not post_add_status or post_add_status == "" then
    return -- nothing to commit
  end

  -- Step 6: commit
  local commit_msg = make_commit_message()
  local _, commit_exit = git_sync(dir, {"commit", "-m", commit_msg})
  if commit_exit ~= 0 then
    notify_error("commit failed in " .. dir .. " — check :GitAutoBackupLog")
    return
  end

  -- Step 7: push
  if config.push then
    local _, push_exit = git_sync(dir, {"push"})
    if push_exit ~= 0 then
      notify_error("push failed in " .. dir .. " — check :GitAutoBackupLog")
      return
    end
  end

  state.last_sync[dir] = os.date("%Y-%m-%dT%H:%M:%S%z")
end

local function git_async(dir, args, callback)
  local full_cmd = vim.list_extend({ "git", "-C", dir }, args)
  local stdout_chunks = {}
  local stderr_chunks = {}

  vim.fn.jobstart(full_cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then table.insert(stdout_chunks, line) end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then table.insert(stderr_chunks, line) end
        end
      end
    end,
    on_exit = function(_, exit_code)
      local output = table.concat(stdout_chunks, "\n")
      local err_output = table.concat(stderr_chunks, "\n")
      log(dir .. " $ git " .. table.concat(args, " ") .. " -> exit " .. exit_code)
      if output ~= "" then log(output) end
      if err_output ~= "" then log(err_output) end
      if callback then
        callback(output, exit_code)
      end
    end,
  })
end

local function sync_dir_async(dir, on_complete)
  if state.should_abort then
    if on_complete then on_complete() end
    return
  end

  local did_stash = false

  local function step_push()
    if state.should_abort then if on_complete then on_complete() end return end
    if not config.push then
      if on_complete then on_complete() end
      return
    end
    git_async(dir, {"push"}, function(_, exit_code)
      if exit_code ~= 0 then
        notify_error("push failed in " .. dir .. " — check :GitAutoBackupLog")
        if on_complete then on_complete() end
        return
      end
      state.last_sync[dir] = os.date("%Y-%m-%dT%H:%M:%S%z")
      if on_complete then on_complete() end
    end)
  end

  local function step_commit()
    if state.should_abort then if on_complete then on_complete() end return end
    local commit_msg = make_commit_message()
    git_async(dir, {"commit", "-m", commit_msg}, function(_, exit_code)
      if exit_code ~= 0 then
        notify_error("commit failed in " .. dir .. " — check :GitAutoBackupLog")
        if on_complete then on_complete() end
        return
      end
      if not config.push then
        state.last_sync[dir] = os.date("%Y-%m-%dT%H:%M:%S%z")
      end
      step_push()
    end)
  end

  local function step_check_and_commit()
    if state.should_abort then if on_complete then on_complete() end return end
    git_async(dir, {"add", "-A"}, function(_, add_exit)
      if add_exit ~= 0 then
        notify_error("git add failed in " .. dir .. " — check :GitAutoBackupLog")
        if on_complete then on_complete() end
        return
      end
      git_async(dir, {"status", "--porcelain"}, function(output, _)
        if not output or output == "" then
          if on_complete then on_complete() end
          return
        end
        step_commit()
      end)
    end)
  end

  local function step_stash_pop()
    if state.should_abort then
      state.did_stash[dir] = did_stash
      if on_complete then on_complete() end
      return
    end
    if not did_stash then
      step_check_and_commit()
      return
    end
    git_async(dir, {"stash", "pop"}, function(_, exit_code)
      did_stash = false
      state.did_stash[dir] = false
      if exit_code ~= 0 then
        notify_error("stash conflict in " .. dir .. " — check :GitAutoBackupLog")
        if on_complete then on_complete() end
        return
      end
      step_check_and_commit()
    end)
  end

  local function step_pull()
    if state.should_abort then
      state.did_stash[dir] = did_stash
      if on_complete then on_complete() end
      return
    end
    git_async(dir, {"pull", "--rebase"}, function(_, exit_code)
      if exit_code ~= 0 then
        notify_error("conflict in " .. dir .. " — check :GitAutoBackupLog")
        if did_stash then
          git_async(dir, {"stash", "pop"}, function() end)
        end
        if on_complete then on_complete() end
        return
      end
      step_stash_pop()
    end)
  end

  local function step_stash()
    if state.should_abort then if on_complete then on_complete() end return end
    git_async(dir, {"status", "--porcelain"}, function(output, _)
      if not output or output == "" then
        step_pull()
        return
      end
      git_async(dir, {"stash", "-u"}, function(_, exit_code)
        if exit_code ~= 0 then
          notify_error("stash failed in " .. dir .. " — check :GitAutoBackupLog")
          if on_complete then on_complete() end
          return
        end
        did_stash = true
        step_pull()
      end)
    end)
  end

  -- Entry point: decide whether to include pull steps
  if config.pull then
    step_stash()
  else
    step_check_and_commit()
  end
end

function M.run_cycle_async()
  if state.is_running then return end
  if #config.dirs == 0 then return end
  state.is_running = true
  state.should_abort = false

  local idx = 0
  local function next_dir()
    idx = idx + 1
    if idx > #config.dirs or state.should_abort then
      state.is_running = false
      return
    end
    sync_dir_async(config.dirs[idx], next_dir)
  end
  next_dir()
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

  -- Stop existing timer if re-calling setup
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  -- Start timer
  if config.enabled and #config.dirs > 0 then
    state.timer = vim.uv.new_timer()
    local interval_ms = config.interval * 60 * 1000
    -- Initial delay = interval (avoids double-sync with VimEnter pull)
    state.timer:start(interval_ms, interval_ms, vim.schedule_wrap(function()
      M.run_cycle_async()
    end))
  end

  -- Create augroup, clearing any previous autocmds
  local augroup = vim.api.nvim_create_augroup("GitAutoBackup", { clear = true })

  -- VimEnter: sync on open
  vim.api.nvim_create_autocmd("VimEnter", {
    group = augroup,
    callback = function()
      vim.schedule(function()
        if config.pull and config.pull_on_open then
          -- Full cycle with pull
          M.run_cycle_async()
        elseif #config.dirs > 0 then
          -- pull disabled or pull_on_open disabled: just commit/push
          M.run_cycle_async()
        end
      end)
    end,
  })

  -- VimLeavePre: synchronous exit cycle
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      -- Abort any in-flight async cycle
      if state.is_running then
        state.should_abort = true
      end

      -- Pop any dangling stash from aborted async cycle
      for _, dir in ipairs(config.dirs) do
        if state.did_stash[dir] then
          vim.fn.system({ "git", "-C", dir, "stash", "pop" })
          state.did_stash[dir] = false
        end
      end

      -- Run synchronous exit cycle (steps 4-7, no pull) for all dirs
      for _, dir in ipairs(config.dirs) do
        M.sync_dir_sync(dir, false)
      end

      -- Stop timer
      if state.timer then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
      end
    end,
  })

  state.setup_done = true
end

function M.get_config()
  return vim.deepcopy(config)
end

function M.get_state()
  return vim.deepcopy(state)
end

return M
