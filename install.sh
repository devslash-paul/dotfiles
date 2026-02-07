#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

echo "Installing dotfiles from $DOTFILES"

# Neovim
rm -rf ~/.config/nvim
ln -sf "$DOTFILES/nvim" ~/.config/nvim
echo "  Linked nvim config"

# tmux
ln -sf "$DOTFILES/tmux/tmux.conf" ~/.tmux.conf
echo "  Linked tmux.conf"

# zsh
ln -sf "$DOTFILES/zsh/zshrc" ~/.zshrc
echo "  Linked zshrc"

# vim -> nvim alias
mkdir -p ~/.local/bin
ln -sf "$(which nvim)" ~/.local/bin/vim
echo "  Linked vim -> nvim"

echo ""
echo "Done. Open nvim and lazy.nvim will auto-install plugins."
