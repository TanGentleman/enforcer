//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const hookSettings = struct {
    UserPromptSubmit: bool,
};

pub fn setHooks(settings: hookSettings) !void {
    // precondition: ~/.claude/settings.json exists
    std.debug.print("setting hook to {}\n", .{settings.UserPromptSubmit});
    // postcondition: ~/.claude/settings.json sets hooks accordingly (no duplicates)
}
