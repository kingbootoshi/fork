# Prompt caching: why forks are free

The whole point of forking a chat is that the conversation is the asset.
This doc explains how provider prompt caches actually behave under forking,
the measurements behind fork's design, and why the default flow re-pays
nothing.

All numbers below were measured by reading `usage` fields out of real
session files (`input_tokens`, `cache_creation_input_tokens`,
`cache_read_input_tokens`), not inferred from docs.

## The problem

When you fork a chat, the new agent's first request replays the entire
conversation history to the provider. Without a cache hit, a 200k-token
history is 200k fresh input tokens - per branch. Branch three times and
you've paid for your conversation three more times, in dollars (API) or
rate-limit weight (subscription).

Both providers cache prompts, but they key their caches differently, and
that difference decides everything about how to fork.

## Claude: content-keyed (strict prefix)

Anthropic's cache is a strict prefix match: a request reads cache only for
the exact leading bytes it shares with a recent request. One changed byte
early in the context and everything after it misses.

Claude Code writes the working directory into the context early (the env
block). So the launch directory decides the fate of a forked chat:

| scenario | cache read | cache write | meaning |
|---|---|---|---|
| fork chat, SAME directory | 41,740 (all) | 191 | full reuse, free |
| fork chat into CLONED directory | 17,732 (system+tools only) | 24,206 | conversation re-ingested once |

The cwd string change breaks the prefix right after the static system/tools
block. Everything conversational misses and gets re-written to cache (paid
at the cache-write multiplier, once).

**TTL:** subscription auth (Pro/Max) automatically requests the 1-hour
cache TTL - no setting needed. API-key auth defaults to 5 minutes;
`ENABLE_PROMPT_CACHING_1H=1` opts into 1h there. Cache reads cost ~0.1x
input price; writes 1.25x (5m) or 2x (1h).

**Cross-machine:** the cache does NOT follow you to another machine.
Measured: warmed on machine A (cache_read=39,247), forked on machine B
minutes later - same org, same model, same Claude Code version, same
absolute path, well inside the TTL - and the conversation still re-wrote
(cache_read=17,747 was only machine B's own static prefix; two runs
produced the identical split). The early context carries machine-specific
bytes beyond the cwd. Moving machines costs one re-ingest.

## Codex: identity-keyed (thread id)

OpenAI routes its prompt cache by thread id, not content:

- `codex resume <id>` is a full cache hit even in a DIFFERENT directory
  (measured: cached=30,592 after a cwd change).
- `codex fork <id>` mints a new thread id and always starts cold -
  measured twice, including against a freshly warmed cache (cached=2,432
  both times). Nothing outside OpenAI can change this.

So codex forks re-pay once no matter what you do, but codex resumes are
free anywhere - probably including other machines.

## The design that falls out

**Branch on claude, move on codex.**

### Claude branches: launch in place, work in the clone

`fork <name>` inside a Claude Code chat (the default) does NOT launch the
forked chat in the clone. It launches it in the ORIGINAL directory - the
prefix stays byte-identical, the entire history reads from cache - and
auto-sends a kickoff prompt steering all work into the clone via absolute
paths. Appended messages never bust a prefix cache, so the steering is
free. The [fork-guard hook](fork-guard.md) makes the boundary hard rather
than advisory.

End-to-end proof on the shipped default flow - the forked chat's first
request:

```
input=290   cache_write=201   cache_read=59,868
```

Full history reused. The only new tokens were the kickoff prompt itself.
(An earlier run at larger scale: input=290, cache_read=78,515.)

`--isolated` opts out: the chat physically moves into the clone and
re-ingests its history once.

Branching N times multiplies nothing: every branch shares the same prefix,
so all of them hit the same cache entries, and any branch sending a turn
keeps the shared prefix warm for the others.

### Codex beams: resume, don't fork

`fork <name> --to <host>` is a MOVE - the laptop side stops. So beams use
`codex resume` (same thread id, fully cached) rather than `codex fork`
(cold). For claude beams the cross-machine miss applies: one re-ingest on
arrival, warm after.

## What it's worth

At Claude API prices (input $/M with cache read ~0.1x): a turn on 200k of
cached context costs ~10x less input than uncached, and every cold fork
avoided saves a one-time 200k cache write (~2x input price on the 1h
tier). On a subscription the same math applies to rate-limit weight - three
parallel branches cost barely more than one chat.
