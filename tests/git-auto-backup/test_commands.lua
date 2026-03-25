local gab

local function create_test_repo()
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  vim.fn.system("git -C " .. vim.fn.shellescape(tmpdir) .. " init")
  vim.fn.system("git -C " .. vim.fn.shellescape(tmpdir) .. " config user.email 'test@test.com'")
  vim.fn.system("git -C " .. vim.fn.shellescape(tmpdir) .. " config user.name 'Test'")
  vim.fn.system("git -C " .. vim.fn.shellescape(tmpdir) .. " commit --allow-empty -m 'init'")
  return tmpdir
end

local function cleanup(dir)
  vim.fn.delete(dir, "rf")
end

describe("git-auto-backup commands", function()
  local repo

  before_each(function()
    package.loaded["git-auto-backup"] = nil
    gab = require("git-auto-backup")
    repo = create_test_repo()
    gab.setup({ dirs = { repo }, enabled = false, push = false, pull = false })
  end)

  after_each(function()
    cleanup(repo)
  end)

  it("get_status_lines returns status info", function()
    local lines = gab.get_status_lines()
    assert.truthy(#lines > 0)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:match("disabled") or joined:match("enabled"))
  end)

  it("get_log_lines returns log buffer contents", function()
    local f = assert(io.open(repo .. "/test.md", "w"))
    f:write("hello")
    f:close()
    gab.sync_dir_sync(repo)

    local lines = gab.get_log_lines()
    assert.truthy(#lines > 0)
  end)

  it("toggle flips enabled state", function()
    gab.toggle()
    local config = gab.get_config()
    assert.is_true(config.enabled)

    gab.toggle()
    config = gab.get_config()
    assert.is_false(config.enabled)
  end)
end)
