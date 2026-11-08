//! enforcer: a small prompt gate for Claude Code. `on`/`off` manage the
//! UserPromptSubmit hook; `hook` reads the hook JSON from stdin and exits 0
//! (allow), 2 (block) or 1 (internal error).

const std = @import("std");
const claude = @import("claude.zig");
const hook = @import("hook.zig");
const settings = @import("settings.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const usage_text =
    \\Usage: enforcer <command>
    \\
    \\  on       register the Claude Code prompt hook
    \\  off      unregister it
    \\  hook     run as the hook: read stdin, exit 2 to block
    \\  --help   show this help
    \\
;

fn printStderr(io: Io, gpa: Allocator, comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrint(gpa, fmt, args) catch return;
    defer gpa.free(msg);
    Io.File.stderr().writeStreamingAll(io, msg) catch {};
}

fn outcomeMessage(action: settings.Action, outcome: settings.Outcome) []const u8 {
    return switch (action) {
        .install => switch (outcome) {
            .changed => "installed",
            .unchanged => "already installed",
        },
        .uninstall => switch (outcome) {
            .changed => "removed",
            .unchanged => "nothing to remove",
        },
    };
}

/// Claude Code reads `$CLAUDE_CONFIG_DIR/settings.json`, default
/// `~/.claude/settings.json`. The config directory must already exist.
fn toggle(init: std.process.Init, action: settings.Action) u8 {
    const io = init.io;
    const gpa = init.gpa;
    const env = init.environ_map;

    const config_dir_path: []const u8 = blk: {
        if (env.get("CLAUDE_CONFIG_DIR")) |path| if (path.len > 0) break :blk gpa.dupe(u8, path) catch return 1;
        const home = env.get("ENFORCER_HOME") orelse env.get("HOME") orelse {
            printStderr(io, gpa, "enforcer: HOME is not set\n", .{});
            return 1;
        };
        break :blk std.fs.path.join(gpa, &.{ home, ".claude" }) catch return 1;
    };
    defer gpa.free(config_dir_path);

    var config_dir = Io.Dir.cwd().openDir(io, config_dir_path, .{}) catch |err| {
        printStderr(io, gpa, "enforcer: no Claude Code config at {s} ({s})\n", .{ config_dir_path, @errorName(err) });
        return 1;
    };
    defer config_dir.close(io);

    var owned_self: ?[:0]u8 = null;
    defer if (owned_self) |path| gpa.free(path);
    const self_path: []const u8 = env.get("ENFORCER_SELF") orelse blk: {
        owned_self = std.process.executablePathAlloc(io, gpa) catch |err| {
            printStderr(io, gpa, "enforcer: cannot find own executable: {s}\n", .{@errorName(err)});
            return 1;
        };
        break :blk owned_self.?;
    };
    const command = claude.renderCommand(gpa, self_path) catch return 1;
    defer gpa.free(command);

    const outcome = settings.apply(io, gpa, config_dir, "settings.json", action, command) catch |err| {
        printStderr(io, gpa, "enforcer: {s}/settings.json: {s}\n", .{ config_dir_path, @errorName(err) });
        return 1;
    };
    const msg = std.fmt.allocPrint(gpa, "{s}/settings.json: {s}\n", .{ config_dir_path, outcomeMessage(action, outcome) }) catch return 0;
    defer gpa.free(msg);
    Io.File.stdout().writeStreamingAll(io, msg) catch {};
    return 0;
}

pub fn main(init: std.process.Init) u8 {
    const io = init.io;
    const gpa = init.gpa;

    const args = init.minimal.args.toSlice(gpa) catch |err| {
        printStderr(io, gpa, "enforcer: cannot read arguments: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer gpa.free(args);

    if (args.len < 2) {
        Io.File.stderr().writeStreamingAll(io, usage_text) catch {};
        return 1;
    }

    const verb = args[1];
    if (std.mem.eql(u8, verb, "--help") or std.mem.eql(u8, verb, "-h")) {
        Io.File.stdout().writeStreamingAll(io, usage_text) catch {};
        return 0;
    }
    if (std.mem.eql(u8, verb, "hook")) return hook.run(io, gpa);
    if (std.mem.eql(u8, verb, "on")) return toggle(init, .install);
    if (std.mem.eql(u8, verb, "off")) return toggle(init, .uninstall);

    Io.File.stderr().writeStreamingAll(io, usage_text) catch {};
    return 1;
}

test {
    _ = claude;
    _ = hook;
    _ = settings;
    _ = @import("policy.zig");
}
