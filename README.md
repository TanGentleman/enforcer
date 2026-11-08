# enforcer

A prompt gate for Claude Code in one small Zig binary. It runs as a
`UserPromptSubmit` hook and blocks a prompt before it is sent when the prompt
contains a GitHub classic token (`ghp_...`). No network, no config file.

## Install

Needs Zig 0.17 ([ziglang.org/download](https://ziglang.org/download/)).

```sh
git clone https://github.com/TanGentleman/enforcer && cd enforcer
zig build --release --prefix ~/.local && ~/.local/bin/enforcer on
```

`enforcer on` adds the hook to `~/.claude/settings.json` (or
`$CLAUDE_CONFIG_DIR/settings.json`) and keeps everything else in the file.
`enforcer off` removes it. Both are safe to run twice.

## Example

```console
$ echo '{"prompt":"deploy with ghp_abc123"}' | enforcer hook; echo "exit $?"
enforcer: prompt contains what looks like a GitHub token (ghp_...)
exit 2
$ echo '{"prompt":"deploy to staging"}' | enforcer hook; echo "exit $?"
exit 0
```

In Claude Code the first prompt is not sent and you see:

```text
UserPromptSubmit operation blocked by hook:
[/home/you/.local/bin/enforcer hook]: enforcer: prompt contains what looks like a GitHub token (ghp_...)
```

## Commands

| Command | Does | Exit codes |
| --- | --- | --- |
| `enforcer on` | add the hook | 0 done or already there, 1 error |
| `enforcer off` | remove it | 0 done or nothing to remove, 1 error |
| `enforcer hook` | read the hook JSON on stdin | 0 allow, 2 block (reason on stderr), 1 internal error (Claude Code lets the prompt through) |

`hook` reads at most 256 KiB and checks only the `prompt` field; input that is
not a JSON object with a string `prompt` is checked as raw text.

## How `on` edits settings.json

It writes `{"type": "command", "command": "<path to enforcer> hook"}` under
`hooks.UserPromptSubmit`, replacing any older enforcer entry. The write holds a
lock (`.enforcer.lock`, left in place), goes to a temp file that is fsynced and
renamed over the original, keeps the file mode, and is read back to check it.
Symlinked or invalid settings files are refused and left untouched. The config
directory must already exist; `settings.json` is created if missing.

The rule is one case-sensitive substring check in `src/policy.zig`. It is a
speed bump against pasting a token, not a secret scanner, and the blocked text
can still land in Claude Code's local transcript.

## Develop

```sh
zig build test     # unit tests and CLI tests against the built binary
zig build check    # zig fmt --check plus the tests (what CI runs)
zig build --release   # ReleaseSmall, about 200 KB
```
