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
- Checks the `nvim` version: if it's missing or below v0.11, installs the official static binary from GitHub releases into `~/.local` (Linux x86_64/aarch64, macOS x86_64/arm64), and links it into `~/.local/bin`.
- Ensures `~/.local/bin` is on `PATH` (persists to `~/.zshrc` if needed).
- Installs Oh My Zsh if missing.
- Attempts to set your default shell to `zsh` (`chsh`) and prints a manual command when not permitted.
- Creates symlinks for Neovim, tmux, zsh, and Ghostty config (Ghostty's macOS path is `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`, elsewhere `~/.config/ghostty/config`).
- Backs up existing targets before replacing them, using `*.backup-YYYYMMDD-HHMMSS`.
- Creates `~/.local/bin/vim -> nvim` pointing at the verified binary.

## Requirements

Minimum:
- `nvim` v0.11+ (the installer installs it automatically if missing or too old)

Recommended for full Neovim behavior:
- `ripgrep` (used by Telescope `live_grep`)
- `rust-analyzer` (configured LSP server)

Optional shell tooling (auto-detected when present):
- asdf
- nvm
- bun

## Notes for new environments

- Per-machine zsh settings (env vars, PATH, aliases) go in `~/.local_zshrc`. It's sourced last from the tracked `zshrc` and is optional, so it's skipped if missing.
- On a fresh machine/workspace, missing optional tools are skipped safely.
- On systems where `chsh` is blocked, run the printed `chsh -s ...` command manually.
- Open Neovim once after install to let lazy.nvim install plugins.
