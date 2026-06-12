#!/usr/bin/env bash
# install fork + clonedir into ~/.local/bin
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p "$HOME/.local/bin"

clang -O2 -o "$HOME/.local/bin/clonedir" clonedir.c
echo "built  ~/.local/bin/clonedir"

install -m 755 fork "$HOME/.local/bin/fork"
echo "installed  ~/.local/bin/fork"

# fork-guard: PreToolUse hook that stops a forked claude chat from writing
# into the original tree (cached forks launch there for the prompt-cache hit).
# Inert outside forks - it exits instantly unless FORK_WORKTREE is set.
mkdir -p "$HOME/.claude/hooks"
install -m 755 fork-guard.sh "$HOME/.claude/hooks/fork-guard.sh"
echo "installed  ~/.claude/hooks/fork-guard.sh"

# Register the hook in ~/.claude/settings.json (idempotent merge).
python3 - <<'PY'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
hook_cmd = os.path.expanduser("~/.claude/hooks/fork-guard.sh")
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
pre = data.setdefault("hooks", {}).setdefault("PreToolUse", [])
if not any(h.get("command") == hook_cmd
           for e in pre for h in e.get("hooks", [])):
    pre.insert(0, {"matcher": "Edit|Write|NotebookEdit|Bash",
                   "hooks": [{"type": "command", "command": hook_cmd}]})
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)
    print("registered fork-guard in ~/.claude/settings.json")
else:
    print("fork-guard already registered in ~/.claude/settings.json")
PY

command -v tmux >/dev/null || echo "warning: tmux not found - brew install tmux"
command -v jq   >/dev/null || echo "warning: jq not found - brew install jq (fork-guard needs it)"
echo "done. try: cd <repo> && fork test"
