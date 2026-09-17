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
    _ = enforcer.setHooks(.{
        .UserPromptSubmit = true,
    }) catch |err| {
        print("error: {s}\n", .{@errorName(err)});
        return false;
    };
    return true;
}

// `handler for `enforcer off`
fn uninstall() bool {
    _ = enforcer.setHooks(.{
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

    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try stdout_writer.flush(); // Don't forget to flush!
    return 0;
}
