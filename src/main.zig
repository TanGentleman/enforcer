const std = @import("std");
const Io = std.Io;
const print = std.debug.print;
const enforcer = @import("enforcer");
const Settings = @import("enforcer").hookSettings;

const max_input_bytes: u32 = 4000;

const ValidInput = struct {
    prompt: []const u8,
};

// handler for `enforcer on`
fn install() bool {
    enforcer.setHooks(.{
        .UserPromptSubmit = true,
    }) catch |err| {
        print("error: {s}\n", .{@errorName(err)});
        return false;
    };
    return true;
}

// `handler for `enforcer off`
fn uninstall() bool {
    enforcer.setHooks(.{
        .UserPromptSubmit = false,
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
    var arena_buf: [max_input_bytes]u8 = undefined;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&arena_buf);
    var arena = std.heap.ArenaAllocator.init(fixed_allocator.allocator());
    defer arena.deinit();
    const arena_allocator = arena.allocator();
    const io = init.io;

    // validate config
    const home_dir = init.environ_map.get("HOME").?;
    //std.log.info("Home: {s}", .{home_dir});
    const config_path = try std.fs.path.join(arena_allocator, &.{
        home_dir,
        ".claude",
        "settings.json",
    });
    const cwd = Io.Dir.cwd();
    cwd.access(io, config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.ConfigMissing,
        else => {
            print("error: {s}\n", .{@errorName(err)});
            return err;
        },
    };
    std.log.info("config: {s}", .{config_path});
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
            const success = install();
            print("success: {}\n", .{success});
            return 0;
        }
        if (std.mem.eql(u8, "off", arg)) {
            const success = uninstall();
            print("success: {}\n", .{success});
            return 0;
        }
        if (std.mem.eql(u8, "--input", arg)) {
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
