# fork-guard: hard worktree boundaries

Cached claude forks launch in the ORIGINAL repo directory (that is what
keeps the prompt-cache prefix byte-identical - see [caching.md](caching.md))
and steer all work into the clone via a kickoff prompt. A prompt is
advisory. `fork-guard.sh` is enforcement.

## What it does

A Claude Code PreToolUse hook, installed to `~/.claude/hooks/fork-guard.sh`
and registered in `~/.claude/settings.json` by `install.sh`:

- **Edit / Write / NotebookEdit** targeting the original tree -> blocked.
- **Bash** commands that mutate the original tree (rm/mv/cp/tee/sed -i,
  redirections into it, git state changes like add/commit/checkout/reset) ->
  blocked.
- Everything inside the fork's worktree -> allowed, untouched.

Blocking uses the hook contract: exit 2 with the reason on stderr, which
Claude Code feeds back to the model. In practice the agent reads the error
and self-corrects to the absolute worktree path on its next attempt - the
boundary teaches instead of just failing.

## When it's active

Only inside forked sessions. The hook exits immediately unless
`FORK_WORKTREE` is set, and only `fork` exports that (along with
`FORK_PROTECT`, the original root) into the forked agent's environment.
Your normal Claude Code sessions never run a single line of it. Set
`FORK_GUARD=off` to disable it inside a fork.

## Proof

Dogfooded on the shipped default flow: a forked agent was given explicit
in-chat permission - "I authorize you to write into the original tree" -
and told to try. The Write was blocked at the tool layer, the file was
never created, and the agent self-corrected into its worktree. The same
session's first request read its full history from cache (input=290,
cache_read=59,868): the guard and zero-repay caching coexist.

## The trust gate (read this if you write hooks)

While testing, the hook silently did nothing in real forked sessions while
passing every unit test and every fresh-session test. The cause is worth
knowing for any Claude Code hook author:

**Claude Code loads NO hooks - including user-level hooks from
`~/.claude/settings.json` - in a directory whose trust dialog was never
accepted.** And `--dangerously-skip-permissions` / bypass-permissions mode
skips that dialog entirely, so the flag never flips. A freshly cloned fork
path has never been trusted, which meant forked agents ran with zero hooks:
not fork-guard, and not any personal guardrail hooks the user had either.
No warning is shown anywhere.

This was A/B-verified: an identical tmux-launched TUI in the same directory
runs zero hooks with `hasTrustDialogAccepted: false` in `~/.claude.json`
and runs all hooks with `true` - flipping that one flag is the entire
difference.

The fix shipped in `fork`: before launching claude it upserts
`projects.<realpath>.hasTrustDialogAccepted = true` into `~/.claude.json` -
the exact flag accepting the dialog sets - for the launch directory. Local
forks, cached forks, and beams (remote `~/.claude.json` over ssh) all get
this. Forks therefore run with the user's full hook stack, guard included.
