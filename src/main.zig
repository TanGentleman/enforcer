const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const enforcer = @import("enforcer");
const Settings = @import("enforcer").HookSettings;

const allocator_max_bytes: u32 = 4 * 1024 * 1024;
var process_buf: [allocator_max_bytes]u8 = undefined;

const ValidInput = struct {
    prompt: []const u8,
};

// handler for `enforcer on`
fn install(allocator: std.mem.Allocator, io: std.Io, settings_path: []const u8) bool {
    enforcer.setHooks(allocator, io, .{
        .user_prompt_submit = true,
        .settings_path = settings_path,
    }) catch |err| {
        print("error: {s}\n", .{@errorName(err)});
        return false;
    };
    return true;
}

// `handler for `enforcer off`
fn uninstall(allocator: std.mem.Allocator, io: std.Io, settings_path: []const u8) bool {
    enforcer.setHooks(allocator, io, .{
        .user_prompt_submit = false,
        .settings_path = settings_path,
    }) catch |err| {
        print("error: {s}\n", .{@errorName(err)});
        return false;
    };
    return true;
}

fn parseInput(input_string: []const u8) ValidInput {
    print("input length in bytes: {d}\n", .{input_string.len});
    return .{ .prompt = "..." };
}

pub fn main(init: std.process.Init) !u8 {
    // This is appropriate for anything that lives as long as the process.
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&process_buf);
    var arena_state = std.heap.ArenaAllocator.init(fixed_allocator.allocator());
    defer arena_state.deinit();
    const arena_allocator = arena_state.allocator();
    const io = init.io;

    // validate config
    const home_dir = init.environ_map.get("HOME").?;
    //std.log.info("Home: {s}", .{home_dir});
    const settings_path = try std.fs.path.join(arena_allocator, &.{
        home_dir,
        ".claude",
        "settings.json",
    });
    const cwd = Io.Dir.cwd();
    cwd.access(io, settings_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.ConfigMissing,
        else => {
            print("error: {s}\n", .{@errorName(err)});
            return err;
        },
    };
    std.log.info("config: {s}", .{settings_path});

    // Accessing command line arguments:
    const args = init.minimal.args.toSlice(arena_allocator) catch |err| {
        switch (err) {
            error.OutOfMemory => {
                print("input too big\n", .{});
                return 1;
            },
            else => {
                print("error: {s}\n", .{@errorName(err)});
                return err;
            },
        }
    };

    var expecting_input = false;
    var count: u32 = 0;
    for (args) |arg| {
        // std.log.info("arg: {s}", .{arg});
        if (count == 0) {
            count += 1;
            continue;
        }
        if (std.mem.eql(u8, "on", arg)) {
            const success = install(arena_allocator, io, settings_path);
            print("success: {}\n", .{success});
            switch (success) {
                true => return 0,
                false => return 1,
            }
        }
        if (std.mem.eql(u8, "off", arg)) {
            const success = uninstall(arena_allocator, io, settings_path);
            print("success: {}\n", .{success});
            switch (success) {
                true => return 0,
                false => return 1,
            }
        }
        if (std.mem.eql(u8, "hook", arg)) {
            expecting_input = true;
            continue;
        }
        if (!expecting_input) {
            print("ignoring unknown flag and aborting\n", .{});
            return 1;
        }

        // handle input
        const input = parseInput(arg);
        _ = input;
        return 0;
    }
    return 1;
}
