# enforcer: implementation

## Requirements

- Zig 0.17.0 or newer (CI uses 0.17.1, from
  [ziglang.org/download](https://ziglang.org/download/)).
- An existing Claude Code config directory (`~/.claude`, or `CLAUDE_CONFIG_DIR`).
- The binary makes no network requests and reads no credentials.
  `test/claude-code.sh` needs npm to install the Claude Code CLI, but no account
  or API key.

## Usage

```sh
enforcer on       # add the hook to settings.json
enforcer off      # remove it
enforcer hook     # run as the hook: read stdin, exit 2 to block
enforcer --help
```

`enforcer on` adds a `UserPromptSubmit` hook to Claude Code's `settings.json`.
Claude Code runs `enforcer hook` on each submitted prompt. A blocking verdict
exits 2, Claude Code shows the reason, and the prompt is not sent:

```sh
echo '{"prompt":"deploy with ghp_abc123"}' | ~/.local/bin/enforcer hook >/dev/null; echo "exit $?"
```

prints the reason on stderr and `exit 2`. In Claude Code you see:

```text
UserPromptSubmit operation blocked by hook:
enforcer: prompt contains what looks like a GitHub token (ghp_...)
```

`on` stores the absolute path of the binary, so run `enforcer on` again after
moving it.

Exit codes:

| Code | `on` / `off` | `hook` |
| --- | --- | --- |
| 0 | done or already in that state | allow |
| 1 | bad usage, IO error, no config dir | internal error or input over 256 KiB; Claude Code sends the prompt |
| 2 | - | blocked |

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_CONFIG_DIR` | `$HOME/.claude` | Claude Code config directory |
| `HOME` | - | Used when `CLAUDE_CONFIG_DIR` is unset; `on`/`off` exit 1 without either |
| `ENFORCER_SELF` | the running binary | Path written into the hook command |

## How it works

Policy (`src/policy.zig`): one case-sensitive check for the GitHub classic-token
prefix `ghp_`. A prompt containing it is blocked; `GHP_` and `github_pat_` are not
matched. The rule is a speed bump against pasting a token, not a secret scanner.

Hook (`src/hook.zig`): reads at most 256 KiB from stdin and checks the `prompt`
field of Claude Code's hook JSON; input that is not a JSON object with a string
`prompt` is checked as raw text. On a block it writes the reason to stderr and
`{"decision":"block",...,"suppressOriginalPrompt":true}` to stdout, so Claude
Code does not echo the prompt (and the token) back.

Settings (`src/claude.zig`, `src/settings.zig`): `enforcer on` adds
`{"type": "command", "command": "<path to enforcer> hook"}` under
`hooks.UserPromptSubmit` in `$CLAUDE_CONFIG_DIR/settings.json`, replaces an older
enforcer entry, and keeps every other key and hook. It creates `settings.json` if
missing but never the config directory. `off` removes every enforcer entry and the
containers it emptied.

- One write path: a lock file, an atomic temp file, fsync, rename, then a
  re-read check.
- The lock (`.enforcer.lock` in the config directory) stays behind by design.
- The file mode survives the rewrite. A symlinked, non-regular, invalid or
  over-1 MiB `settings.json` is refused and left untouched.
- A no-op does not touch the file.

## Tests

CI (`.github/workflows/ci.yml`), on ubuntu-24.04 and macos-15 with Zig 0.17.1:

```sh
zig build check --summary all   # zig fmt --check, unit tests, CLI tests against the built binary
zig build --release             # ReleaseSmall, zig-out/bin/enforcer
```

and on ubuntu-24.04 with Node 24.22.2:

```sh
npm install -g @anthropic-ai/claude-code@2.1.319
zig build --release
test/claude-code.sh zig-out/bin/enforcer
```

`test/claude-code.sh` runs `enforcer on` in a temporary `HOME`, then runs the
real `claude -p` with an empty environment and no login. Claude Code runs the
hook before its login check, so the script asserts that a `ghp_` prompt is
blocked without echoing the token, that a clean prompt is not blocked, and that
`enforcer off` removes the block.

## Limits

- Only Claude Code is supported. The Pi version lives in
  [tan-toolchains](https://github.com/TanGentleman/tan-toolchains) `enforcer/`.
- Checked on Linux x86_64 only. macOS is in the CI matrix but has not run on
  these changes; Windows is untested.
