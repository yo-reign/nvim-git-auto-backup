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

local function write_file(dir, name, content)
  local path = dir .. "/" .. name
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

local function cleanup(dir)
  vim.fn.delete(dir, "rf")
end

describe("git-auto-backup sync cycle", function()
  local repo

  before_each(function()
    package.loaded["git-auto-backup"] = nil
    gab = require("git-auto-backup")
    repo = create_test_repo()
  end)

  after_each(function()
    cleanup(repo)
  end)

  it("commits changes when files are modified", function()
    gab.setup({ dirs = { repo }, pull = false, push = false, enabled = false })
    write_file(repo, "test.md", "hello")
    gab.sync_dir_sync(repo)
    local log = vim.fn.system("git -C " .. vim.fn.shellescape(repo) .. " log --oneline")
    assert.truthy(log:match("auto%-backup:"))
  end)

  it("skips commit when no changes exist", function()
    gab.setup({ dirs = { repo }, pull = false, push = false, enabled = false })
    local before = vim.fn.system("git -C " .. vim.fn.shellescape(repo) .. " rev-parse HEAD")
    gab.sync_dir_sync(repo)
    local after = vim.fn.system("git -C " .. vim.fn.shellescape(repo) .. " rev-parse HEAD")
    assert.equals(before, after)
  end)

  it("generates ISO 8601 commit message", function()
    gab.setup({ dirs = { repo }, pull = false, push = false, enabled = false })
    write_file(repo, "test.md", "hello")
    gab.sync_dir_sync(repo)
    local log = vim.fn.system("git -C " .. vim.fn.shellescape(repo) .. " log -1 --format=%s")
    assert.truthy(log:match("^auto%-backup: %d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d[+-]%d%d%d%d"))
  end)

  it("handles custom commit prefix", function()
    gab.setup({ dirs = { repo }, pull = false, push = false, enabled = false, commit_prefix = "notes-sync" })
    write_file(repo, "test.md", "hello")
    gab.sync_dir_sync(repo)
    local log = vim.fn.system("git -C " .. vim.fn.shellescape(repo) .. " log -1 --format=%s")
    assert.truthy(log:match("^notes%-sync:"))
  end)
end)
