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

describe("git-auto-backup pull cycle", function()
  local origin, local_repo

  before_each(function()
    package.loaded["git-auto-backup"] = nil
    gab = require("git-auto-backup")

    -- Create a bare origin repo
    origin = vim.fn.tempname()
    vim.fn.mkdir(origin, "p")
    vim.fn.system("git -C " .. vim.fn.shellescape(origin) .. " init --bare")

    -- Clone it to get a working repo
    local_repo = vim.fn.tempname()
    vim.fn.system("git clone " .. vim.fn.shellescape(origin) .. " " .. vim.fn.shellescape(local_repo))
    vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " config user.email 'test@test.com'")
    vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " config user.name 'Test'")
    vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " commit --allow-empty -m 'init'")
    vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " push")
  end)

  after_each(function()
    vim.fn.delete(origin, "rf")
    vim.fn.delete(local_repo, "rf")
  end)

  it("pull + commit + push works end-to-end", function()
    gab.setup({ dirs = { local_repo }, pull = true, push = true, enabled = false })
    write_file(local_repo, "note.md", "my note")

    gab.sync_dir_sync(local_repo, true)

    -- Verify pushed to origin
    local log = vim.fn.system("git -C " .. vim.fn.shellescape(origin) .. " log --oneline")
    assert.truthy(log:match("auto%-backup:"))
  end)

  it("stashes local changes during pull", function()
    gab.setup({ dirs = { local_repo }, pull = true, push = true, enabled = false })

    -- Create a committed file, then modify it (uncommitted change)
    write_file(local_repo, "existing.md", "original")
    vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " add -A")
    vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " commit -m 'add existing'")
    vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " push")
    write_file(local_repo, "existing.md", "modified locally")

    gab.sync_dir_sync(local_repo, true)

    -- The modified content should be committed
    local content = vim.fn.system("git -C " .. vim.fn.shellescape(local_repo) .. " show HEAD:existing.md")
    assert.equals("modified locally", content)
  end)
end)
