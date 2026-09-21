//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const hookSettings = struct {
    user_prompt_submit: bool,
    settings_path: []const u8,
};

fn mutateHooks(hooks_struct: anytype) bool {
    _ = hooks_struct;
    return true;
}

// TODO: move allocator to be backing_allocator, use another arena allocator within this fn scope
pub fn setHooks(allocator: std.mem.Allocator, io: std.Io, settings: hookSettings) !void {
    const max_settings_file_bytes = 1 * 1024 * 1024;
    // precondition: ~/.claude/settings.json exists
    const dir_path = std.fs.path.dirname(settings.settings_path) orelse ".";
    const filename = std.fs.path.basename(settings.settings_path);

    var dir = try Io.Dir.cwd().openDir(io, dir_path, .{ .follow_symlinks = false });
    defer dir.close(io);

    // get lock (rn its posix only)
    var lock_name_buf: [std.fs.max_name_bytes]u8 = undefined;
    const lock_name = try std.fmt.bufPrint(&lock_name_buf, "{s}.lock", .{filename});
    var lock_file = try dir.createFile(io, lock_name, .{
        .read = true,
        .lock = .exclusive,
        .truncate = false,
        .lock_nonblocking = true,
        .permissions = .fromMode(0o600),
    });
    defer lock_file.close(io);

    const stat = try dir.statFile(io, filename, .{ .follow_symlinks = false });
    switch (stat.kind) {
        .file => {},
        .sym_link => return error.SettingsSymlinkUnsupported,
        else => return error.SettingsFileWacky,
    }

    if (stat.size > max_settings_file_bytes) {
        return error.SettingsTooLarge;
    }

    const file_contents = try dir.readFileAlloc(
        io,
        filename,
        allocator,
        .limited(max_settings_file_bytes + 1),
    );
    // defer allocator.free(file_contents);
    // std.log.debug("Full file:\n---\n{s}---", .{file_contents[0..]});
    var parsed = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        file_contents,
        .{
            .duplicate_field_behavior = .@"error",
            .parse_numbers = false,
        },
    );
    // should be ok to not deinit since we're using arena allocator, right?
    // what's best practice here?
    // defer parsed.deinit();
    switch (parsed) {
        .object => {},
        else => return error.settingsFileNotJSON,
    }
    const success = mutateHooks(&parsed);
    std.debug.print("success mutating hooks: {}\n", .{success});
    std.debug.print("setting hook to {}\n", .{settings.user_prompt_submit});
    // postcondition: ~/.claude/settings.json sets hooks accordingly (no duplicates)
}

// NOTE: Test these cases for mutateHooks (no file io):
// 1. A settings file without a hooks field adds them in.
// 2. If enforcer hook already present, return false.
// 3. Removal deletes duplicates.
// 4. Removal preserves unrelated hooks.
// 5. Nonexistent hook removal returns false.
