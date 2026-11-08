//! `enforcer hook`: Claude Code's UserPromptSubmit hook. Reads the hook JSON
//! from stdin and exits 0 (allow), 2 (block, reason on stderr) or 1 (internal
//! error; Claude Code lets the prompt through). Rules live in `policy.zig`.

const std = @import("std");
const policy = @import("policy.zig");

const Io = std.Io;

pub const max_input_bytes = 256 * 1024;

pub const Exit = struct {
    code: u8,
    reason: []const u8 = "",
};

/// Testable core: no stdin and no process exit.
pub fn decide(gpa: std.mem.Allocator, input: []const u8) Exit {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const prompt = extractPrompt(arena.allocator(), input) catch return .{ .code = 1 };
    return switch (policy.evaluate(prompt)) {
        .allow => .{ .code = 0 },
        .block => |reason| .{ .code = 2, .reason = reason },
    };
}

fn extractPrompt(gpa: std.mem.Allocator, input: []const u8) ![]const u8 {
    const Parsed = struct { prompt: []const u8 = "" };
    const parsed = std.json.parseFromSliceLeaky(Parsed, gpa, input, .{ .ignore_unknown_fields = true }) catch {
        // Not an object with a string `prompt`: scan the raw bytes so a
        // malformed payload can't bypass the rule.
        return input;
    };
    return parsed.prompt;
}

pub fn run(io: Io, gpa: std.mem.Allocator) u8 {
    var buf: [4096]u8 = undefined;
    var reader = Io.File.Reader.initStreaming(Io.File.stdin(), io, &buf);
    const input = reader.interface.allocRemaining(gpa, .limited(max_input_bytes)) catch |err| {
        const msg = std.fmt.allocPrint(gpa, "enforcer: cannot read prompt: {s}\n", .{@errorName(err)}) catch return 1;
        defer gpa.free(msg);
        Io.File.stderr().writeStreamingAll(io, msg) catch {};
        return 1;
    };
    defer gpa.free(input);

    if (input.len == 0) return 0;

    const verdict = decide(gpa, input);
    if (verdict.code == 2) {
        const msg = std.fmt.allocPrint(gpa, "enforcer: {s}\n", .{verdict.reason}) catch return 2;
        defer gpa.free(msg);
        Io.File.stderr().writeStreamingAll(io, msg) catch {};
    }
    return verdict.code;
}

test "blocks a token in the Claude Code payload" {
    const payload =
        \\{"session_id":"abc","hook_event_name":"UserPromptSubmit","cwd":"/tmp","prompt":"use ghp_abc"}
    ;
    const exit = decide(std.testing.allocator, payload);
    try std.testing.expectEqual(@as(u8, 2), exit.code);
    try std.testing.expect(std.mem.indexOf(u8, exit.reason, "GitHub") != null);
}

test "allows a clean prompt" {
    try std.testing.expectEqual(@as(u8, 0), decide(std.testing.allocator, "{\"prompt\":\"hello\"}").code);
}

test "only the prompt field is checked" {
    try std.testing.expectEqual(@as(u8, 0), decide(std.testing.allocator, "{\"cwd\":\"/ghp_dir\",\"prompt\":\"hi\"}").code);
}

test "falls back to raw input" {
    try std.testing.expectEqual(@as(u8, 0), decide(std.testing.allocator, "hi").code);
    try std.testing.expectEqual(@as(u8, 2), decide(std.testing.allocator, "raw ghp_abc").code);
}

test "empty and malformed input never blocks" {
    try std.testing.expectEqual(@as(u8, 0), decide(std.testing.allocator, "").code);
    try std.testing.expectEqual(@as(u8, 0), decide(std.testing.allocator, "{}").code);
    try std.testing.expectEqual(@as(u8, 0), decide(std.testing.allocator, "\xff\x00garbage").code);
}
