#!/bin/bash
# fork-guard - Claude Code PreToolUse hook enforcing fork worktree boundaries.
#
# Cached forks (`fork <name>`, the default) launch the forked chat in the
# ORIGINAL repo directory to keep the prompt-cache prefix byte-identical,
# then steer all work into the clone via a kickoff prompt. The kickoff is
# instructions; this hook is enforcement. fork exports FORK_WORKTREE (the
# clone) and FORK_PROTECT (the original root) into the forked agent's env -
# when they're absent (every normal session) this hook is a no-op.
#
# Contract: exit 0 allows the tool call, exit 2 blocks it and feeds stderr
# back to the model so it self-corrects to an absolute worktree path.

[ -z "${FORK_WORKTREE:-}" ] && exit 0
[ "${FORK_GUARD:-on}" = "off" ] && exit 0

input=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
tool=$(jq -r '.tool_name // empty' <<<"$input")

block() {
    echo "fork-guard: $1 This chat is a forked timeline whose worktree is $FORK_WORKTREE - do all writes there via absolute paths. The original tree at ${FORK_PROTECT:-the source repo} belongs to another timeline." >&2
    exit 2
}

case "$tool" in
    Edit|Write|NotebookEdit)
        fp=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
        [ -z "$fp" ] && exit 0
        case "$fp" in
            /*) abs=$fp ;;
            *)  cwd=$(jq -r '.cwd // empty' <<<"$input"); abs="${cwd:-$PWD}/$fp" ;;
        esac
        case "$abs" in
            "$FORK_WORKTREE"|"$FORK_WORKTREE"/*) exit 0 ;;
        esac
        if [ -n "${FORK_PROTECT:-}" ]; then
            case "$abs" in
                "$FORK_PROTECT"|"$FORK_PROTECT"/*) block "write to $abs blocked." ;;
            esac
        fi
        ;;
    Bash)
        [ -z "${FORK_PROTECT:-}" ] && exit 0
        cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
        case "$cmd" in *"$FORK_PROTECT"*) ;; *) exit 0 ;; esac
        # Mentions the protected root: block if it looks like a mutation
        # (redirection into it, file-mutating commands, git state changes).
        if grep -Eq '(^|[;&|[:space:]])(rm|mv|cp|touch|tee|mkdir|ln|chmod|chown|truncate)[[:space:]]|sed[[:space:]]+-i|>[>]?[[:space:]]*"?'"$FORK_PROTECT"'|git[[:space:]]+(-C[[:space:]]+\S+[[:space:]]+)?(add|commit|checkout|switch|restore|reset|clean|stash|merge|rebase|push|rm|mv|am|cherry-pick)\b' <<<"$cmd"; then
            block "bash command touching the original tree blocked."
        fi
        ;;
esac
exit 0
