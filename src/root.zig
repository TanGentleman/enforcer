//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const HookSettings = struct {
    user_prompt_submit: bool,
    settings_path: []const u8,
};

const hook_command = "$HOME/.enforcer/bin/enforcer hook";

fn isEnforcerHook(v: *std.json.Value) !bool {
    if (v.* != .object) return error.ValueNotObject;
    const commandValue = v.object.get("command") orelse return false;
    if (commandValue != .string) return false;
    return (std.mem.eql(u8, commandValue.string, hook_command));
}
// return True if settings_struct is changed
fn mutateHooks(allocator: std.mem.Allocator, settings_struct: *std.json.Value, settings: HookSettings) !bool {
    const root = settings_struct;
    if (root.* != .object) return error.SettingsExpectedObject;
    const gop = try root.object.getOrPut(allocator, "hooks");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = .empty };
    if (gop.value_ptr.* != .object) return error.HooksExpectedObject;

    // ups stands for user_prompt_submit
    const ups = try gop.value_ptr.object.getOrPut(allocator, "UserPromptSubmit");
    if (!ups.found_existing) ups.value_ptr.* = .{ .object = .empty };
    if (ups.value_ptr.* != .object) return error.HooksExpectedObject;
    const ups_hooks = try ups.value_ptr.object.getOrPut(allocator, "hooks");
    if (!ups_hooks.found_existing) @panic("idk how to init an array here");
    if (ups_hooks.value_ptr.* != .array) return error.HooksSubfieldExpectedObject;
    const arr = ups_hooks.value_ptr.array;
    var i: usize = arr.items.len;
    while (i > 0) {
        i -= 1;
        if (try isEnforcerHook(&arr.items[i])) @panic("WOOHOO!");
    }

    if (settings.user_prompt_submit == true) return error.NotImplementedYet;

    var entry: std.json.ObjectMap = .empty;
    try entry.put(allocator, "type", .{ .string = "command" });
    try entry.put(allocator, "command", .{ .string = hook_command });
    var inner = std.json.Array.init(allocator);
    try inner.append(.{ .object = entry });

    var group: std.json.ObjectMap = .empty;
    try group.put(allocator, "hooks", .{ .array = inner });
    return true;
}

// TODO: move allocator to be backing_allocator, use another arena allocator within this fn scope
pub fn setHooks(allocator: std.mem.Allocator, io: std.Io, settings: HookSettings) !void {
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
    const success = try mutateHooks(allocator, &parsed, settings);
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
