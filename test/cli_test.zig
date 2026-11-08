//! Runs the built binary as a child process.

const std = @import("std");

const Io = std.Io;
const gpa = std.testing.allocator;
const io = std.testing.io;
const exe_path = @import("build_options").exe_path;

const Result = struct {
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,

    fn deinit(self: *Result) void {
        gpa.free(self.stdout);
        gpa.free(self.stderr);
    }
};

fn writeFile(dir: Io.Dir, name: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(io, name, .{});
    defer file.close(io);
    var buf: [4096]u8 = undefined;
    var writer = file.writer(io, &buf);
    try writer.interface.writeAll(bytes);
    try writer.flush();
}

fn readFile(dir: Io.Dir, name: []const u8) ![]u8 {
    return dir.readFileAlloc(io, name, gpa, .limited(1024 * 1024));
}

/// stdin, stdout and stderr go through files in `dir` so large output can't
/// deadlock a pipe.
fn run(dir: Io.Dir, argv: []const []const u8, stdin_bytes: []const u8, env: ?*const std.process.Environ.Map) !Result {
    try writeFile(dir, "stdin", stdin_bytes);
    const stdin_file = try dir.openFile(io, "stdin", .{});
    defer stdin_file.close(io);
    const stdout_file = try dir.createFile(io, "stdout", .{});
    defer stdout_file.close(io);
    const stderr_file = try dir.createFile(io, "stderr", .{});
    defer stderr_file.close(io);

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .{ .file = stdin_file },
        .stdout = .{ .file = stdout_file },
        .stderr = .{ .file = stderr_file },
        .environ_map = env,
    });
    const term = try child.wait(io);

    return .{
        .term = term,
        .stdout = try readFile(dir, "stdout"),
        .stderr = try readFile(dir, "stderr"),
    };
}

fn expectCode(result: Result, code: u8) !void {
    switch (result.term) {
        .exited => |got| try std.testing.expectEqual(code, got),
        else => return error.TestUnexpectedResult,
    }
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, needle) != null);
}

test "hook blocks a token with exit 2 and a reason on stderr" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var result = try run(tmp.dir, &.{ exe_path, "hook" }, "{\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"use ghp_abc\"}", null);
    defer result.deinit();
    try expectCode(result, 2);
    try std.testing.expectEqualStrings("", result.stdout);
    try expectContains(result.stderr, "GitHub");
}

test "hook allows a clean prompt silently" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var result = try run(tmp.dir, &.{ exe_path, "hook" }, "{\"prompt\":\"hello\"}", null);
    defer result.deinit();
    try expectCode(result, 0);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
}

test "hook does not need HOME or settings.json" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var result = try run(tmp.dir, &.{ exe_path, "hook" }, "{\"prompt\":\"ghp_x\"}", &env);
    defer result.deinit();
    try expectCode(result, 2);
}

test "hook fails open on input over the limit" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const big = try gpa.alloc(u8, 256 * 1024 + 1);
    defer gpa.free(big);
    @memset(big, 'a');

    var result = try run(tmp.dir, &.{ exe_path, "hook" }, big, null);
    defer result.deinit();
    try expectCode(result, 1);
    try expectContains(result.stderr, "cannot read prompt");
}

test "no args prints usage to stderr and exits 1" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var result = try run(tmp.dir, &.{exe_path}, "", null);
    defer result.deinit();
    try expectCode(result, 1);
    try expectContains(result.stderr, "Usage: enforcer");
    try std.testing.expectEqualStrings("", result.stdout);
}

test "--help prints usage to stdout and exits 0" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var result = try run(tmp.dir, &.{ exe_path, "--help" }, "", null);
    defer result.deinit();
    try expectCode(result, 0);
    try expectContains(result.stdout, "Usage: enforcer");
}

test "unknown verb exits 1" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var result = try run(tmp.dir, &.{ exe_path, "--input", "x" }, "", null);
    defer result.deinit();
    try expectCode(result, 1);
}

test "on with HOME unset exits 1 without panicking" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var result = try run(tmp.dir, &.{ exe_path, "on" }, "", &env);
    defer result.deinit();
    try expectCode(result, 1);
    try expectContains(result.stderr, "HOME is not set");
}
