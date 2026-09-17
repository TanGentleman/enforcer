const std = @import("std");
const Io = std.Io;
const enforcer = @import("enforcer");
const print = std.debug.print;

// just `enforcer on` requires <120 bytes
const max_input_bytes: u32 = 4000;

const ValidInput = struct {
    prompt: []const u8,
};

// handler for `enforcer on`
fn install() ValidInput {
    print("enforcer enabled\n", .{});
    const settings: enforcer.hookSettings = .{ .beforePromptSubmit = true };
    const res = try enforcer.setHooks(settings);
    print("result: {}\n", .{res});
    return .{ .prompt = "on" };
}

// `handler for `enforcer off`
fn uninstall() ValidInput {
    print("enforcer disabled\n", .{});
    return .{ .prompt = "off" };
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
            const input = install();
            _ = input;
            return 0;
        }
        if (std.mem.eql(u8, "off", arg)) {
            const input = uninstall();
            _ = input;
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
