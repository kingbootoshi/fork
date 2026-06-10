#!/usr/bin/env bash
# install fork + clonedir into ~/.local/bin
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p "$HOME/.local/bin"

clang -O2 -o "$HOME/.local/bin/clonedir" clonedir.c
echo "built  ~/.local/bin/clonedir"

install -m 755 fork "$HOME/.local/bin/fork"
echo "installed  ~/.local/bin/fork"

command -v tmux >/dev/null || echo "warning: tmux not found - brew install tmux"
echo "done. try: cd <repo> && fork test"
