# enforcer roadmap

enforcer is a small Zig binary that gates prompts before Claude Code sends them.
`enforcer on` registers it as a `UserPromptSubmit` hook in `~/.claude/settings.json`,
`enforcer off` removes it, and `enforcer hook` reads the hook's JSON from stdin and
exits 2 to block (Claude Code then drops the prompt and shows stderr). For people who
want a fast, offline speed bump against pasting secrets into an agent.

## Status (upstream main a1a4b49, checked 2026-11-08 with Zig 0.17.1)

- `zig build` and `zig build test` pass, but there are no tests (template tests were
  removed in 2850e44). `zig fmt --check` is clean.
- `build.zig.zon` asked for `0.17.0-dev.1606`; 0.17.1 is the current release
  (ziglang.org/download). `-1` pins `0.17.0` as the floor and CI on 0.17.1.
- `enforcer on` prints `success: true` and changes nothing: `setHooks` in
  `src/root.zig` only prints. Checked with `HOME=$tmp enforcer on` on `{}`.
- `enforcer hook` does not exist; `--input <text>` prints the length and exits 0.
  No stdin reading, no rule, nothing can block.
- Missing `~/.claude/settings.json` returns `error.ConfigMissing` with a stack trace;
  no args does the same before printing anything. HOME unset panicked (fixed on `-1`).
- README claims a 166 KB binary; `zig build -Doptimize=ReleaseSmall` gives 149 KB
  (x86_64-linux).
- Branch `atomic-settings` (2e9d1d0) is a WIP JSON mutator for the hook list with
  `@panic` placeholders. Its direction (lock file, symlink refusal, `hook` verb,
  snake_case fields) is kept on `-3`.
- Tan's Pi rewrite (tan-toolchains `docs-trim:enforcer/`) points Claude users here. Its
  hook contract, one-rule policy and atomic writer are the model for `-2` and `-3`.

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

Checked end to end with Claude Code 2.1.319 (`claude -p` with an empty HOME, no
login): after `enforcer on`, a `ghp_` prompt is blocked by the hook before the login
check; a clean prompt reaches "Not logged in".

## Apply a branch upstream

```bash
# in kranti-sandbox: everything after the import commit
base=$(git log -1 --format=%H --grep='^Import enforcer upstream' origin/enforcer-1)
git format-patch --relative=enforcer "$base"..origin/enforcer-1 -o /tmp/enforcer-1
# in a clean upstream clone at a1a4b49
git clone https://github.com/TanGentleman/enforcer && cd enforcer
git am /tmp/enforcer-1/*.patch
zig build test --summary all
```

For a stacked branch, use the previous branch as the base: `origin/enforcer-1..origin/enforcer-2`.

## Needs Tan

- Zig floor 0.17.0 (current 0.17.1). Fine if nobody builds on 0.16.
- Delete or rebase `atomic-settings` once `-3` lands; it is superseded.
- The rule is only case-sensitive `ghp_`. `github_pat_`, `gho_` and other secrets
  pass. Widening it is a product call, kept out of this stack.
- `hook` fails open (exit 1 lets the prompt through) on read errors or >256 KiB input.
- `on` stores the absolute binary path; moving the binary needs `enforcer on` again.
- `.enforcer.lock` stays in the Claude config dir after `on`/`off`.
- CI runs on ubuntu and macos; only Linux was run here. Windows is untested.
