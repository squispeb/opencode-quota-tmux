#!/usr/bin/env bash

TMUX2K_PLUGINS_DIR="$HOME/.config/tmux/plugins/tmux2k/plugins"
TARGET="$TMUX2K_PLUGINS_DIR/opencode-quota.sh"
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/opencode-quota.sh"

if [ -d "$TMUX2K_PLUGINS_DIR" ] && [ ! -f "$TARGET" ]; then
  ln -sf "$SOURCE" "$TARGET"
fi
