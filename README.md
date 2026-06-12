# fork

![fork - one timeline becomes two](images/fork_timeline_split.jpeg)

Instant copy-on-write repo forks with forked agent chats.

Type `fork <name>` inside Claude Code or Codex shell mode (`!`) and get a new
tmux window holding a fork of BOTH the repo and the chat you typed it from -
sitting in the clone, on its own branch, ~1 second later.

```
you, inside claude code or codex, mid-conversation:
  ! fork parser-fix

what happens:
  1. APFS clonefile(2) snapshots the whole repo        ~1s, zero disk cost
     (.git state, .env files, node_modules, docker configs - everything)
  2. clone gets its own branch: fork/parser-fix
  3. your CURRENT chat is forked
       claude -> claude --resume <id> --fork-session   (session file copied
                 into the clone's project dir first)
       codex  -> codex fork $CODEX_THREAD_ID --cd <clone>
  4. a tmux window opens in the clone running the forked chat
       inside tmux  -> new window (a tab; detach-friendly over ssh)
       outside tmux -> detached session + new Terminal.app window attached
```

## Why

The most valuable moments in agent-assisted work happen mid-conversation.
You've been deep in discussion for an hour, the agent holds the entire
picture in context, and the thread arrives at a natural split: three
features, independent, all buildable right now.

The old move was opening fresh chats and re-explaining everything from
zero, once per feature. That throws away the most expensive artifact you
own - a primed conversation. Re-explaining costs time, money, and fidelity:
the fresh chat never knows quite what the old one knew, and the old one was
cached.

`fork` treats the conversation as the asset:

- **Fork at the moment of divergence.** When the discussion splits, the
  chat splits with it. Each timeline carries the full shared history -
  primed, cached, nothing re-explained.
- **Isolation without setup.** Parallel agents need isolated worktrees with
  the SAME local files - env, deps, build state - not a fresh checkout.
  Copy-on-write cloning hands each timeline a 1:1 copy of the working
  directory in about a second, for near-zero disk. A 10GB folder forks for
  megabytes.
- **Parallel by default.** Run 3-4 big features at once, each agent in its
  own timeline and its own worktree, each committing PRs to main.
- **Merge as a job.** When the parallel work lands, one fresh agent at the
  repo root merges everything and resolves conflicts. Strong tests and
  guardrails make the landing smooth.

The bottleneck stops being setup and context-rebuilding. It becomes how
many timelines you can read.

## Install

```bash
./install.sh        # builds clonedir (clang) + installs both to ~/.local/bin
```

macOS / APFS only for now. Requires tmux.

Works from a raw repo root too - no agent running yet: `fork <name>` clones,
branches, and opens a FRESH claude chat in the fork (set `FORK_AGENT=codex`
or pass `--codex` for codex). Inside an agent it forks the current chat;
outside one it starts a new chat. Same command, both directions.

## Commands

```
fork <name>             clone + branch + chat in tmux:
                          inside an agent -> forks the current chat
                          raw terminal    -> fresh claude (FORK_AGENT=codex flips)
fork <name> --no-agent  clone + branch + plain shell
fork <name> --cached    zero-repay claude fork: chat stays in the original
                        dir (byte-identical prefix = full prompt-cache hit),
                        an auto-sent kickoff steers all work into the clone
fork <name> --claude    claude in the fork (forks current chat, else fresh)
fork <name> --codex     codex in the fork (forks current chat, else fresh)
fork <name> --to <host> BEAM: move the work to another machine (see below)
fork <name> --bg        do not steal focus / do not open a Terminal window
fork ls                 list forks of the current repo
fork path <name>        print a fork's path (cd "$(fork path x)")
fork merge <name>       fetch fork/<name> branch back into the source repo
fork trash <name>       trash a fork + kill its tmux window/session
```

## Beam: move the work to another machine

`fork <name> --to <ssh-host>` is "move to cloud" for your own hardware.
Leaving the house mid-build? Beam the work to an always-on box and the
agent keeps going without you:

1. rsync ships the EXACT working state - dirty tree, staged index, .env
   files, node_modules - to `~/Dev/.forks/<repo>/<name>` on the remote
2. your current chat is forked onto the remote machine (same session-file
   trick, shipped over ssh)
3. the agent resumes inside a remote tmux session
4. a local window auto-attaches via `ssh -t <host> tmux attach`

Close the laptop whenever - the agent lives on the remote now. Reattach
from anywhere with the printed attach command. Requires: ssh key auth to
the host, tmux + the agent CLI installed there. `FORK_REMOTE_BASE`
overrides the remote directory (default `Dev/.forks`).

## Layout

Forks live beside the repo (same volume - required for clonefile):

```
~/code/app/                   source
~/code/.forks/app/parser-fix  fork
```

## Prompt-cache economics

Forked chats reuse the provider's prompt cache - that's half the point. The
two agents cache differently, so the free paths differ (all verified by
reading usage numbers out of real session files):

- **Claude caches by content prefix.** A fork in the SAME directory is a
  full cache hit. Moving directories rewrites the cwd into the early
  context and re-ingests the conversation once. `--cached` dodges this
  entirely: the chat launches in the original directory (identical bytes,
  full hit) and works in the clone via absolute paths.
- **Codex caches by thread id.** `resume` is a full hit even in a different
  directory or (likely) another machine. A true `fork` is a new thread and
  always starts cold - one-time re-ingest, then warm. Beams therefore use
  `codex resume`: a beam is a move, not a branch.

Rule of thumb: **branch on claude (`--cached`), move on codex (beam).**

## Notes

- Each fork is a fully independent git repo (not a linked worktree). Merge
  back with `fork merge <name>` (local fetch) or push and PR as usual.
- `COMPOSE_PROJECT_NAME=<repo>-<name>` is exported in each fork's tmux
  window so parallel docker compose stacks don't collide. Host port
  conflicts are still on you.
- Disk is free until files diverge; `node_modules` reinstalls and build
  output are the usual divergence. `fork trash` + `fork ls` keep it tidy.
- Inspired by anomalyco/rift - same syscall, none of the dependency.
