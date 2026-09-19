//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const hookSettings = struct {
    UserPromptSubmit: bool,
    config_path: []const u8,
};

pub fn setHooks(allocator: std.mem.Allocator, io: std.Io, settings: hookSettings) !void {
    // precondition: ~/.claude/settings.json exists
    const dir_path = std.fs.path.dirname(settings.config_path) orelse ".";
    const filename = std.fs.path.basename(settings.config_path);

    var dir = try Io.Dir.cwd().openDir(io, dir_path, .{ .follow_symlinks = false });
    defer dir.close(io);
    std.log.info("f: {s}", .{filename});
    _ = allocator;
    std.debug.print("setting hook to {}\n", .{settings.UserPromptSubmit});
    // postcondition: ~/.claude/settings.json sets hooks accordingly (no duplicates)
}
