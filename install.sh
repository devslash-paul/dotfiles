#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

backup_path() {
  local target="$1"
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  mv "$target" "${target}.backup-${ts}"
}

safe_link() {
  local source_path="$1"
  local target_path="$2"

  mkdir -p "$(dirname "$target_path")"

  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    if [ -L "$target_path" ] && [ "$(readlink "$target_path")" = "$source_path" ]; then
      echo "  Already linked: $target_path"
      return
    fi

    backup_path "$target_path"
    echo "  Backed up: $target_path"
  fi

  ln -s "$source_path" "$target_path"
  echo "  Linked: $target_path -> $source_path"
}

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Error: need root privileges to run: $*" >&2
    return 1
  fi
}

detect_pkg_manager() {
  if command -v brew >/dev/null 2>&1; then
    echo "brew"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v apk >/dev/null 2>&1; then
    echo "apk"
  else
    echo ""
  fi
}

install_packages() {
  local pkg_manager="$1"
  shift

  case "$pkg_manager" in
    brew)
      brew install "$@"
      ;;
    apt)
      run_privileged apt-get update -y
      run_privileged apt-get install -y "$@"
      ;;
    dnf)
      run_privileged dnf install -y "$@"
      ;;
    yum)
      run_privileged yum install -y "$@"
      ;;
    pacman)
      run_privileged pacman -Sy --noconfirm "$@"
      ;;
    apk)
      run_privileged apk add --no-cache "$@"
      ;;
    *)
      echo "Error: unsupported package manager" >&2
      return 1
      ;;
  esac
}

ensure_command() {
  local command_name="$1"
  local package_name="$2"

  if command -v "$command_name" >/dev/null 2>&1; then
    return
  fi

  local pkg_manager
  pkg_manager="$(detect_pkg_manager)"
  if [ -z "$pkg_manager" ]; then
    echo "Error: could not find package manager to install '$package_name'." >&2
    exit 1
  fi

  echo "Installing missing dependency: $package_name"
  install_packages "$pkg_manager" "$package_name"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is still unavailable after install attempt." >&2
    exit 1
  fi
}

# --- Neovim version check & install ----------------------------------------
# Config requires nvim >= 0.11 (vim.lsp.enable, built-in treesitter).
# If the system nvim is missing or too old, install the official static
# binary into ~/.local so it takes precedence on PATH.

NVIM_MIN_MINOR=11

nvim_version_ok() {
  # Return 0 if the first line of `nvim --version` reports v0.{NVIM_MIN_MINOR}+
  local first_line major minor
  first_line="$(nvim --version 2>/dev/null | head -n1)"
  case "$first_line" in
    NVIM\ v[0-9]*) : ;;
    *) return 1 ;;
  esac
  major="${first_line#*v}"; major="${major%%.*}"
  minor="$(printf '%s\n' "$first_line" | sed -n 's/.*v[0-9]*\.\([0-9][0-9]*\).*/\1/p')"
  case "$major" in ''|*[!0-9]*) return 1 ;; esac
  case "$minor" in ''|*[!0-9]*) return 1 ;; esac
  if [ "$major" -gt 0 ]; then return 0; fi
  if [ "$minor" -ge "$NVIM_MIN_MINOR" ]; then return 0; fi
  return 1
}

nvim_asset_name() {
  # Echo the correct release asset name for this platform
  if [ "$(uname -s)" = "Darwin" ]; then
    case "$(uname -m)" in
      arm64)  echo "nvim-macos-arm64.tar.gz" ;;
      x86_64) echo "nvim-macos-x86_64.tar.gz" ;;
      *) return 1 ;;
    esac
  else
    case "$(uname -m)" in
      x86_64|amd64)    echo "nvim-linux-x86_64.tar.gz" ;;
      aarch64|arm64)   echo "nvim-linux-aarch64.tar.gz" ;;
      *) return 1 ;;
    esac
  fi
}

install_nvim_binary() {
  local asset version url dest tmp
  asset="$(nvim_asset_name)" || {
    echo "Error: unsupported platform ($(uname -s)/$(uname -m)) for nvim binary install." >&2
    return 1
  }

  # Prefer latest stable from GitHub API; fall back to a known-good tag
  version="$(curl -fsSL --max-time 15 \
    https://api.github.com/repos/neovim/neovim/releases/latest 2>/dev/null \
    | sed -n 's/.*"tag_name": *"\(v[0-9][^"]*\)".*/\1/p' | head -n1)" || version=""
  [ -n "$version" ] || version="v0.12.4"

  url="https://github.com/neovim/neovim/releases/download/${version}/${asset}"
  dest="$HOME/.local"
  tmp="$(mktemp -d)"

  echo "Installing nvim ${version} (${asset}) to ${dest}"
  if ! curl -fsSL --max-time 120 -o "$tmp/nvim.tar.gz" "$url"; then
    echo "Error: failed to download nvim from $url" >&2
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$dest"
  rm -rf "$dest/nvim"
  tar -xzf "$tmp/nvim.tar.gz" -C "$dest"
  # Archive extracts to nvim-linux-x86_64 / nvim-macos-arm64 / etc.
  local extracted
  extracted="$(ls "$dest" | grep -E '^nvim-(linux|macos)' | head -n1)"
  [ -n "$extracted" ] || { echo "Error: unexpected archive contents" >&2; rm -rf "$tmp"; return 1; }
  mv "$dest/$extracted" "$dest/nvim"
  rm -rf "$tmp"

  mkdir -p "$HOME/.local/bin"
  ln -sf "$dest/nvim/bin/nvim" "$HOME/.local/bin/nvim"
  echo "  Installed nvim ${version} at $dest/nvim (linked to $HOME/.local/bin/nvim)"
}

ensure_nvim() {
  if ! command -v nvim >/dev/null 2>&1; then
    echo "nvim not found — installing official binary"
    install_nvim_binary
  elif ! nvim_version_ok; then
    local current
    current="$(nvim --version 2>/dev/null | head -n1)"
    echo "nvim found but too old (${current}) — config requires v0.${NVIM_MIN_MINOR}+"
    install_nvim_binary
  else
    local current
    current="$(nvim --version 2>/dev/null | head -n1)"
    echo "  nvim OK: ${current}"
  fi

  # Ensure ~/.local/bin is on PATH for this shell (and future shells)
    case ":$PATH:" in
      *":$HOME/.local/bin:"*) ;;
      *)
        export PATH="$HOME/.local/bin:$PATH"
        echo "  Added $HOME/.local/bin to PATH for this session"
        # Persist to zshrc if not already there
        if ! grep -q '\.local/bin' "$HOME/.zshrc" 2>/dev/null; then
          echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
          echo "  Added $HOME/.local/bin to \$HOME/.zshrc"
        fi
        ;;
    esac
}

install_oh_my_zsh() {
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "  Found existing Oh My Zsh at $HOME/.oh-my-zsh"
    return
  fi

  echo "Installing Oh My Zsh"
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
}

ensure_default_shell_is_zsh() {
  local zsh_path
  local current_user
  zsh_path="$(command -v zsh)"
  current_user="$(id -un)"

  if [ "${SHELL:-}" = "$zsh_path" ]; then
    echo "  Default shell already set to zsh ($zsh_path)"
    return
  fi

  if ! command -v chsh >/dev/null 2>&1; then
    echo "Warning: chsh is unavailable; set your shell manually: chsh -s $zsh_path" >&2
    return
  fi

  if grep -q "^$zsh_path$" /etc/shells 2>/dev/null; then
    if chsh -s "$zsh_path" "$current_user"; then
      echo "  Updated default shell to zsh: $zsh_path"
    else
      echo "Warning: failed to change default shell automatically. Run: chsh -s $zsh_path" >&2
    fi
  else
    echo "Warning: $zsh_path is not listed in /etc/shells. Add it and run: chsh -s $zsh_path" >&2
  fi
}

echo "Installing dotfiles from $DOTFILES"

ensure_command git git
ensure_command zsh zsh
ensure_command tmux tmux
ensure_nvim
install_oh_my_zsh
ensure_default_shell_is_zsh

safe_link "$DOTFILES/nvim" "$HOME/.config/nvim"
safe_link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
safe_link "$DOTFILES/zsh/zshrc" "$HOME/.zshrc"

if [ "$(uname -s)" = "Darwin" ]; then
  safe_link "$DOTFILES/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
else
  safe_link "$DOTFILES/ghostty/config" "$HOME/.config/ghostty/config"
fi

mkdir -p "$HOME/.local/bin"
if command -v nvim >/dev/null 2>&1; then
  ln -sfn "$(command -v nvim)" "$HOME/.local/bin/vim"
  echo "  Linked: $HOME/.local/bin/vim -> $(command -v nvim)"
else
  echo "  Skipped vim alias (nvim not found in PATH)"
fi

echo
echo "Done."
echo "Open nvim once to install plugins via lazy.nvim."
