//! The one write path for settings.json: a lock held across read, write and
//! verify; an atomic temp file, fsync and rename; the old mode kept; symlinks
//! refused. A no-op leaves the file untouched.

const std = @import("std");
const claude = @import("claude.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const max_file_bytes = 1024 * 1024;
pub const lock_name = ".enforcer.lock";

pub const Action = enum { install, uninstall };
pub const Outcome = enum { changed, unchanged };

fn statExisting(io: Io, dir: Io.Dir, name: []const u8) !?Io.File.Stat {
    return dir.statFile(io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
}

fn readExisting(io: Io, gpa: Allocator, dir: Io.Dir, name: []const u8) !?[]u8 {
    const stat = try statExisting(io, dir, name) orelse return null;
    switch (stat.kind) {
        .sym_link => return error.SettingsIsSymlink,
        .file => {},
        else => return error.SettingsNotRegularFile,
    }
    if (stat.size > max_file_bytes) return error.SettingsTooLarge;
    return try dir.readFileAlloc(io, name, gpa, .limited(max_file_bytes + 1));
}

/// Applies `action` to `name` in `dir` (normally `~/.claude/settings.json`).
/// A missing file counts as `{}`; `uninstall` never creates it.
pub fn apply(io: Io, gpa: Allocator, dir: Io.Dir, name: []const u8, action: Action, command: []const u8) !Outcome {
    const lock = try dir.createFile(io, lock_name, .{ .read = true, .truncate = false, .lock = .exclusive });
    defer lock.close(io);

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const old = try readExisting(io, arena, dir, name);
    if (old == null and action == .uninstall) return .unchanged;

    var root = try claude.parse(arena, old orelse "{}");
    const changed = switch (action) {
        .install => try claude.install(arena, &root, command),
        .uninstall => try claude.uninstall(&root),
    };
    if (!changed) return .unchanged;

    const bytes = try claude.render(arena, root);
    try writeAtomic(io, dir, name, bytes);
    const verified = try readExisting(io, arena, dir, name) orelse return error.VerifyFailed;
    if (!std.mem.eql(u8, verified, bytes)) return error.VerifyFailed;
    return .changed;
}

fn writeAtomic(io: Io, dir: Io.Dir, name: []const u8, bytes: []const u8) !void {
    var permissions: Io.File.Permissions = .default_file;
    if (try statExisting(io, dir, name)) |stat| {
        switch (stat.kind) {
            .sym_link => return error.SettingsIsSymlink,
            .file => permissions = stat.permissions,
            else => return error.SettingsNotRegularFile,
        }
    }

    var atomic = try dir.createFileAtomic(io, name, .{
        .permissions = permissions,
        .make_path = false,
        .replace = true,
    });
    defer atomic.deinit(io);

    var buf: [4096]u8 = undefined;
    var writer = atomic.file.writer(io, &buf);
    try writer.interface.writeAll(bytes);
    try writer.flush();
    try atomic.file.sync(io);
    try atomic.replace(io);
}

const testing = std.testing;

fn readBack(dir: Io.Dir, name: []const u8) ![]u8 {
    return dir.readFileAlloc(testing.io, name, testing.allocator, .limited(max_file_bytes));
}

test "install creates settings.json, then on/off are idempotent" {
    const io = testing.io;
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try testing.expectEqual(Outcome.unchanged, try apply(io, gpa, tmp.dir, "settings.json", .uninstall, "enforcer hook"));
    try testing.expectError(error.FileNotFound, tmp.dir.statFile(io, "settings.json", .{}));

    try testing.expectEqual(Outcome.changed, try apply(io, gpa, tmp.dir, "settings.json", .install, "enforcer hook"));
    try testing.expectEqual(Outcome.unchanged, try apply(io, gpa, tmp.dir, "settings.json", .install, "enforcer hook"));
    try testing.expectEqual(Outcome.changed, try apply(io, gpa, tmp.dir, "settings.json", .uninstall, "enforcer hook"));
    try testing.expectEqual(Outcome.unchanged, try apply(io, gpa, tmp.dir, "settings.json", .uninstall, "enforcer hook"));

    const got = try readBack(tmp.dir, "settings.json");
    defer gpa.free(got);
    try testing.expectEqualStrings("{}\n", got);
}

test "a no-op leaves the original bytes alone" {
    const io = testing.io;
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const original = "{\"model\":   \"opus\"}";
    try tmp.dir.writeFile(io, .{ .sub_path = "settings.json", .data = original });
    try testing.expectEqual(Outcome.unchanged, try apply(io, gpa, tmp.dir, "settings.json", .uninstall, "enforcer hook"));

    const got = try readBack(tmp.dir, "settings.json");
    defer gpa.free(got);
    try testing.expectEqualStrings(original, got);
}

test "invalid JSON is an error and the file is untouched" {
    const io = testing.io;
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "settings.json", .data = "{ not json" });
    try testing.expect(std.meta.isError(apply(io, gpa, tmp.dir, "settings.json", .install, "enforcer hook")));

    const got = try readBack(tmp.dir, "settings.json");
    defer gpa.free(got);
    try testing.expectEqualStrings("{ not json", got);
}

test "the file mode survives a rewrite" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const io = testing.io;
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "settings.json", .data = "{}", .flags = .{ .permissions = .fromMode(0o600) } });
    _ = try apply(io, gpa, tmp.dir, "settings.json", .install, "enforcer hook");
    const stat = try tmp.dir.statFile(io, "settings.json", .{});
    try testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
}

test "a symlinked settings.json is refused" {
    if (@import("builtin").os.tag == .windows) return error.SkipZigTest;
    const io = testing.io;
    const gpa = testing.allocator;
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "real.json", .data = "{}" });
    try tmp.dir.symLink(io, "real.json", "settings.json", .{});
    try testing.expectError(error.SettingsIsSymlink, apply(io, gpa, tmp.dir, "settings.json", .install, "enforcer hook"));

    const got = try readBack(tmp.dir, "real.json");
    defer gpa.free(got);
    try testing.expectEqualStrings("{}", got);
}
