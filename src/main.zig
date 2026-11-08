//! enforcer: a small prompt gate for Claude Code. `on`/`off` manage the
//! UserPromptSubmit hook; `hook` reads the hook JSON from stdin and exits 0
//! (allow), 2 (block) or 1 (internal error).

const std = @import("std");
const enforcer = @import("enforcer");
const hook = @import("hook.zig");

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

fn toggle(init: std.process.Init, enable: bool) u8 {
    const io = init.io;
    const gpa = init.gpa;

    const home_dir = init.environ_map.get("HOME") orelse {
        printStderr(io, gpa, "enforcer: HOME is not set\n", .{});
        return 1;
    };
    const config_path = std.fs.path.join(gpa, &.{ home_dir, ".claude", "settings.json" }) catch return 1;
    defer gpa.free(config_path);

    Io.Dir.cwd().access(io, config_path, .{}) catch |err| {
        printStderr(io, gpa, "enforcer: {s}: {s}\n", .{ config_path, @errorName(err) });
        return 1;
    };
    enforcer.setHooks(.{
        .UserPromptSubmit = enable,
        .config_path = config_path,
    }) catch |err| {
        printStderr(io, gpa, "enforcer: {s}\n", .{@errorName(err)});
        return 1;
    };
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
    if (std.mem.eql(u8, verb, "on")) return toggle(init, true);
    if (std.mem.eql(u8, verb, "off")) return toggle(init, false);

    Io.File.stderr().writeStreamingAll(io, usage_text) catch {};
    return 1;
}

test {
    _ = hook;
    _ = @import("policy.zig");
}
