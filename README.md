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
fork <name> --claude    claude in the fork (forks current chat, else fresh)
fork <name> --codex     codex in the fork (forks current chat, else fresh)
fork <name> --bg        do not steal focus / do not open a Terminal window
fork ls                 list forks of the current repo
fork path <name>        print a fork's path (cd "$(fork path x)")
fork merge <name>       fetch fork/<name> branch back into the source repo
fork trash <name>       trash a fork + kill its tmux window/session
```

## Layout

Forks live beside the repo (same volume - required for clonefile):

```
~/code/app/                   source
~/code/.forks/app/parser-fix  fork
```

## Notes

- Each fork is a fully independent git repo (not a linked worktree). Merge
  back with `fork merge <name>` (local fetch) or push and PR as usual.
- `COMPOSE_PROJECT_NAME=<repo>-<name>` is exported in each fork's tmux
  window so parallel docker compose stacks don't collide. Host port
  conflicts are still on you.
- Disk is free until files diverge; `node_modules` reinstalls and build
  output are the usual divergence. `fork trash` + `fork ls` keep it tidy.
- Inspired by anomalyco/rift - same syscall, none of the dependency.
