# enforcer roadmap

enforcer is a small Zig binary that gates prompts before Claude Code sends them.
`enforcer on` registers it as a `UserPromptSubmit` hook in `~/.claude/settings.json`,
`enforcer off` removes it, and `enforcer hook` reads the hook's JSON from stdin and
exits 2 to block (Claude Code then drops the prompt and shows stderr). For people who
want a fast, offline speed bump against pasting secrets into an agent.

## Status (upstream main a1a4b49, checked 2026-11-08 with Zig 0.17.1)

- Upstream main builds, but `enforcer on` only prints `success: true`, there is no
  `hook` verb, nothing can block, and there are no tests. A missing settings.json or
  no args gives a stack trace; HOME unset panicked.
- After the stack: `zig build check` (fmt, unit and CLI tests) and
  `test/claude-code.sh` against Claude Code 2.1.319 pass on Zig 0.17.1 (official
  tarball, minisign checked); `zig build test` also passes on Zig 0.17.0.
- Branch `atomic-settings` (2e9d1d0) is a WIP JSON mutator with `@panic`
  placeholders; `-3` keeps its direction (lock file, symlink refusal, `hook` verb).
- The Pi rewrite in tan-toolchains `enforcer/` points Claude users here; its README
  is the doc model for this one.

## Signal vs noise

Keep: the three verbs (`on`, `off`, `hook`), a single policy function, one atomic
settings writer. Cut: the `zig init` comments, the `ValidInput` and `--input` stub,
the debug prints in `on`/`off`, the fixed 4 KB arena that limits argv.

## Stack

- `enforcer-1`: import, Zig 0.17 pin, HOME fix, CI, this file.
- `enforcer-2`: `enforcer hook`: stdin JSON -> `policy.evaluate` -> exit 0/2/1, with
  unit and CLI tests.
- `enforcer-3`: `on`/`off` edit the `UserPromptSubmit` hook list in settings.json:
  idempotent, keeps other hooks, atomic write under a lock, tested on temp dirs.
- `enforcer-4`: README with install and a working example, `zig build --release`
  gives ReleaseSmall (213 KB), `zig build check` (fmt + tests) used by CI.
- `enforcer-5`: on a block, print Claude Code's JSON decision with
  `suppressOriginalPrompt` so the token is not echoed; `test/claude-code.sh` runs a
  real, logged-out Claude Code CLI against the binary, in CI.
- `enforcer-6`: no behavior change. CI actions pinned by SHA (checkout v7.0.1,
  setup-zig v2.2.1, setup-node v7.1.0 with Node 24.22.2), runners pinned to
  ubuntu-24.04 and macos-15; table test for hook payloads; settings tests for
  oversized files, directories and the lock; README rewritten.
- `enforcer-7`: README cut to 22 words; details moved to IMPLEMENTATION.md.

Checked end to end with Claude Code 2.1.319 (`claude -p` with an empty HOME, no
login): after `enforcer on`, a `ghp_` prompt is blocked by the hook before the login
check; a clean prompt reaches "Not logged in".

## Needs Tan

- None of the CI changes has run on GitHub; the macOS job is the real check (only
  Linux was run here).
- Delete `atomic-settings` and `enforcer-x-token-formats` once the stack lands; both
  are superseded.
- The rule is only case-sensitive `ghp_`. Widening it is a product call, kept out of
  this stack.
- `hook` fails open (exit 1 lets the prompt through) on read errors or >256 KiB input.
