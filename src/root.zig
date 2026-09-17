//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const hookSettings = struct {
    beforePromptSubmit: bool,
};

pub fn setHooks(settings: hookSettings) !bool {
    std.debug.print("setting hook to {}\n", .{settings.beforePromptSubmit});
    return true;
}
