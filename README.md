# enforcer

A Claude Code prompt hook: one static Zig binary that blocks a prompt containing
`ghp_` before Claude Code sends it. No network.

```sh
git clone https://github.com/TanGentleman/enforcer && cd enforcer
zig build --release --prefix ~/.local
~/.local/bin/enforcer on
```

Needs Zig 0.17.0 or newer and an existing Claude Code config directory
(`~/.claude`). Details: [IMPLEMENTATION.md](IMPLEMENTATION.md),
[ROADMAP.md](ROADMAP.md).
