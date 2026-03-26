# git-auto-backup

Neovim plugin that automatically commits and pushes changes in configured directories on a timer. Built for notes repos (zettelkasten, flashcards) where you want hands-free backup without thinking about git.

## Features

- Timer-based auto-commit and push (default every 15 min)
- Auto-pull with rebase on open and on timer (keeps machines in sync)
- Stashes local changes before pull, restores after
- Merge conflict detection with error notification
- ISO 8601 timestamps in commit messages
- Credential scrubbing in log output

## Install

lazy.nvim:

```lua
{
  "reign/git-auto-backup",
  opts = {
    dirs = {
      "~/notes/zettelkasten",
      "~/notes/flashcards",
    },
    interval = 15,
  },
}
```

## Config

```lua
require("git-auto-backup").setup({
  dirs = {},                          -- directories to watch (must be git repos)
  interval = 15,                     -- sync interval in minutes (min 1)
  commit_prefix = "auto-backup",     -- prefix for commit messages
  push = true,                       -- push after each commit
  pull = true,                       -- pull before commit cycle
  pull_on_open = true,               -- pull when nvim starts
  enabled = true,                    -- start timer automatically
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:GitAutoBackupStatus` | Show enabled state, dirs, last sync times |
| `:GitAutoBackupLog` | Open buffer with recent git operation output |
| `:GitAutoBackupNow` | Trigger sync immediately |
| `:GitAutoBackupToggle` | Enable/disable the timer |

## How it works

1. **On open** -- pulls remote changes, commits and pushes any local changes
2. **Every N minutes** -- pull, commit, push (skipped if nothing changed)
3. **On close** -- commits and pushes any remaining changes (synchronous)

Conflicts are detected and surfaced via `vim.notify` -- check `:GitAutoBackupLog` for details and resolve manually.
