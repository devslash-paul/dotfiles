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
install_oh_my_zsh
ensure_default_shell_is_zsh

safe_link "$DOTFILES/nvim" "$HOME/.config/nvim"
safe_link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"
safe_link "$DOTFILES/zsh/zshrc" "$HOME/.zshrc"

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
