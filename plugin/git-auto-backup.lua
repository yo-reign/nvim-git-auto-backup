-- Registers user commands. Does NOT call setup().

vim.api.nvim_create_user_command("GitAutoBackupStatus", function()
  local gab = require("git-auto-backup")
  local lines = gab.get_status_lines()
  for _, line in ipairs(lines) do
    print(line)
  end
end, { desc = "Show git-auto-backup status" })

vim.api.nvim_create_user_command("GitAutoBackupLog", function()
  local gab = require("git-auto-backup")
  local lines = gab.get_log_lines()

  vim.cmd("new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, "git-auto-backup://log")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "(empty)" })
  vim.bo[buf].modifiable = false
end, { desc = "Show git-auto-backup log" })

vim.api.nvim_create_user_command("GitAutoBackupNow", function()
  local gab = require("git-auto-backup")
  gab.sync_now()
  print("git-auto-backup: sync triggered")
end, { desc = "Trigger git-auto-backup sync now" })

vim.api.nvim_create_user_command("GitAutoBackupToggle", function()
  local gab = require("git-auto-backup")
  gab.toggle()
  local config = gab.get_config()
  print("git-auto-backup: " .. (config.enabled and "enabled" or "disabled"))
end, { desc = "Toggle git-auto-backup on/off" })
