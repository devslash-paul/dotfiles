# Dotfiles

Portable dotfiles for:
- macOS (including a new Mac setup)
- Coder workspaces via dotfiles bootstrap

Coder dotfiles support setup scripts named `install.sh`, `install`, `bootstrap.sh`, `bootstrap`, `script/bootstrap`, `setup.sh`, `setup`, or `script/setup`. This repo uses `install.sh`.

Reference: https://coder.com/docs/user-guides/workspace-dotfiles

## Install

```bash
./install.sh
```

The installer:
- Ensures `git`, `zsh`, and `tmux` are installed (via `brew`, `apt`, `dnf`, `yum`, `pacman`, or `apk`).
- Installs Oh My Zsh if missing.
- Attempts to set your default shell to `zsh` (`chsh`) and prints a manual command when not permitted.
- Creates symlinks for Neovim, tmux, and zsh config.
- Backs up existing targets before replacing them, using `*.backup-YYYYMMDD-HHMMSS`.
- Creates `~/.local/bin/vim -> nvim` only when `nvim` exists.

## Requirements

Minimum:
- `nvim` (optional for install script success, required for Neovim config)

Recommended for full Neovim behavior:
- `ripgrep` (used by Telescope `live_grep`)
- `rust-analyzer` (configured LSP server)

Optional shell tooling (auto-detected when present):
- asdf
- nvm
- bun

## Notes for new environments

- On a fresh machine/workspace, missing optional tools are skipped safely.
- On systems where `chsh` is blocked, run the printed `chsh -s ...` command manually.
- Open Neovim once after install to let lazy.nvim install plugins.
