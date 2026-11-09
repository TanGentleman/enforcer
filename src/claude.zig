//! Edits the UserPromptSubmit hook list in a parsed Claude Code settings.json.
//! Pure functions on `std.json.Value`; file IO lives in `settings.zig`.
//!
//! Shape written by `install`:
//!   {"hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "<exe> hook"}]}]}}

const std = @import("std");

const Allocator = std.mem.Allocator;
const Value = std.json.Value;

pub const event = "UserPromptSubmit";

pub const Error = error{
    SettingsNotObject,
    HooksNotObject,
    EventNotArray,
};

/// A hook command is ours when it runs a binary named `enforcer` with the
/// single argument `hook`, quoted or not. This also matches an install made
/// from another path, so `on` replaces it and `off` removes it.
pub fn isEnforcerCommand(command: []const u8) bool {
    const suffix = " hook";
    if (!std.mem.endsWith(u8, command, suffix)) return false;
    var exe = command[0 .. command.len - suffix.len];
    if (exe.len >= 2 and exe[0] == '\'' and exe[exe.len - 1] == '\'') exe = exe[1 .. exe.len - 1];
    return std.mem.eql(u8, std.fs.path.basenamePosix(exe), "enforcer");
}

fn hookCommand(hook: Value) ?[]const u8 {
    if (hook != .object) return null;
    const command = hook.object.get("command") orelse return null;
    if (command != .string) return null;
    return command.string;
}

/// Shell form of the hook command. The path is single-quoted unless every
/// byte is shell-safe.
pub fn renderCommand(gpa: Allocator, exe_path: []const u8) ![]u8 {
    const safe = for (exe_path) |c| {
        if (!(std.ascii.isAlphanumeric(c) or std.mem.indexOfScalar(u8, "/._-+:@%,=", c) != null)) break false;
    } else exe_path.len > 0;
    if (safe) return std.fmt.allocPrint(gpa, "{s} hook", .{exe_path});

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, '\'');
    for (exe_path) |c| {
        if (c == '\'') try out.appendSlice(gpa, "'\\''") else try out.append(gpa, c);
    }
    try out.appendSlice(gpa, "' hook");
    return out.toOwnedSlice(gpa);
}

fn eventList(root: *Value) Error!?*std.json.Array {
    if (root.* != .object) return error.SettingsNotObject;
    const hooks = root.object.getPtr("hooks") orelse return null;
    if (hooks.* != .object) return error.HooksNotObject;
    const list = hooks.object.getPtr(event) orelse return null;
    if (list.* != .array) return error.EventNotArray;
    return &list.array;
}

/// Removes every enforcer hook and any group it leaves empty. Groups and hook
/// entries with an unexpected shape are left alone. Returns the number removed.
fn removeOurs(list: *std.json.Array) usize {
    var removed: usize = 0;
    var g: usize = list.items.len;
    while (g > 0) {
        g -= 1;
        const group = &list.items[g];
        if (group.* != .object) continue;
        const hooks = group.object.getPtr("hooks") orelse continue;
        if (hooks.* != .array) continue;

        const before = removed;
        var h: usize = hooks.array.items.len;
        while (h > 0) {
            h -= 1;
            const command = hookCommand(hooks.array.items[h]) orelse continue;
            if (!isEnforcerCommand(command)) continue;
            _ = hooks.array.orderedRemove(h);
            removed += 1;
        }
        if (removed > before and hooks.array.items.len == 0) _ = list.orderedRemove(g);
    }
    return removed;
}

fn countOurs(list: *const std.json.Array, command: []const u8) struct { ours: usize, exact: usize } {
    var ours: usize = 0;
    var exact: usize = 0;
    for (list.items) |group| {
        if (group != .object) continue;
        const hooks = group.object.get("hooks") orelse continue;
        if (hooks != .array) continue;
        for (hooks.array.items) |hook| {
            const c = hookCommand(hook) orelse continue;
            if (!isEnforcerCommand(c)) continue;
            ours += 1;
            if (std.mem.eql(u8, c, command)) exact += 1;
        }
    }
    return .{ .ours = ours, .exact = exact };
}

/// Ensures exactly one enforcer hook running `command`. Returns false when
/// the settings already had exactly that. `arena` owns everything added.
pub fn install(arena: Allocator, root: *Value, command: []const u8) !bool {
    if (try eventList(root)) |list| {
        const n = countOurs(list, command);
        if (n.ours == 1 and n.exact == 1) return false;
        _ = removeOurs(list);
    }

    const hooks = try root.object.getOrPut(arena, "hooks");
    if (!hooks.found_existing) hooks.value_ptr.* = .{ .object = .empty };
    const list = try hooks.value_ptr.object.getOrPut(arena, event);
    if (!list.found_existing) list.value_ptr.* = .{ .array = std.json.Array.init(arena) };

    var entry: std.json.ObjectMap = .empty;
    try entry.put(arena, "type", .{ .string = "command" });
    try entry.put(arena, "command", .{ .string = command });
    var inner = std.json.Array.init(arena);
    try inner.append(.{ .object = entry });
    var group: std.json.ObjectMap = .empty;
    try group.put(arena, "hooks", .{ .array = inner });
    try list.value_ptr.array.append(.{ .object = group });
    return true;
}

/// Removes every enforcer hook, then the `UserPromptSubmit` list and the
/// `hooks` object if that left them empty. Returns false if there was none.
pub fn uninstall(root: *Value) !bool {
    const list = try eventList(root) orelse return false;
    if (removeOurs(list) == 0) return false;

    const hooks = root.object.getPtr("hooks").?;
    if (list.items.len == 0) _ = hooks.object.orderedRemove(event);
    if (hooks.object.count() == 0) _ = root.object.orderedRemove("hooks");
    return true;
}

pub fn parse(arena: Allocator, bytes: []const u8) !Value {
    // number_string keeps numbers byte-for-byte; duplicate keys are refused
    // rather than silently dropped on rewrite.
    return std.json.parseFromSliceLeaky(Value, arena, bytes, .{
        .duplicate_field_behavior = .@"error",
        .parse_numbers = false,
    });
}

pub fn render(gpa: Allocator, root: Value) ![]u8 {
    const body = try std.json.Stringify.valueAlloc(gpa, root, .{ .whitespace = .indent_2 });
    defer gpa.free(body);
    return std.mem.concat(gpa, u8, &.{ body, "\n" });
}

const testing = std.testing;

fn roundTrip(input: []const u8, comptime op: enum { on, off }, want_changed: bool, want: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var root = try parse(arena, input);
    const changed = switch (op) {
        .on => try install(arena, &root, "/usr/local/bin/enforcer hook"),
        .off => try uninstall(&root),
    };
    try testing.expectEqual(want_changed, changed);
    const got = try render(arena, root);
    try testing.expectEqualStrings(want, got);
}

test "install into empty settings" {
    try roundTrip("{}", .on, true,
        \\{
        \\  "hooks": {
        \\    "UserPromptSubmit": [
        \\      {
        \\        "hooks": [
        \\          {
        \\            "type": "command",
        \\            "command": "/usr/local/bin/enforcer hook"
        \\          }
        \\        ]
        \\      }
        \\    ]
        \\  }
        \\}
        \\
    );
}

test "install is a no-op when the same hook is present" {
    try roundTrip(
        \\{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/usr/local/bin/enforcer hook"}]}]}}
    , .on, false,
        \\{
        \\  "hooks": {
        \\    "UserPromptSubmit": [
        \\      {
        \\        "hooks": [
        \\          {
        \\            "type": "command",
        \\            "command": "/usr/local/bin/enforcer hook"
        \\          }
        \\        ]
        \\      }
        \\    ]
        \\  }
        \\}
        \\
    );
}

test "install keeps other keys, numbers and hooks, and replaces an old path" {
    try roundTrip(
        \\{"model":"opus","cleanupPeriodDays":30,"ratio":1.50,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"log.sh"},{"type":"command","command":"$HOME/.enforcer/bin/enforcer hook"}]}]}}
    , .on, true,
        \\{
        \\  "model": "opus",
        \\  "cleanupPeriodDays": 30,
        \\  "ratio": 1.50,
        \\  "hooks": {
        \\    "Stop": [
        \\      {
        \\        "hooks": [
        \\          {
        \\            "type": "command",
        \\            "command": "say done"
        \\          }
        \\        ]
        \\      }
        \\    ],
        \\    "UserPromptSubmit": [
        \\      {
        \\        "hooks": [
        \\          {
        \\            "type": "command",
        \\            "command": "log.sh"
        \\          }
        \\        ]
        \\      },
        \\      {
        \\        "hooks": [
        \\          {
        \\            "type": "command",
        \\            "command": "/usr/local/bin/enforcer hook"
        \\          }
        \\        ]
        \\      }
        \\    ]
        \\  }
        \\}
        \\
    );
}

test "install collapses duplicates of the same command" {
    try roundTrip(
        \\{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/usr/local/bin/enforcer hook"}]},{"hooks":[{"type":"command","command":"/usr/local/bin/enforcer hook"}]}]}}
    , .on, true,
        \\{
        \\  "hooks": {
        \\    "UserPromptSubmit": [
        \\      {
        \\        "hooks": [
        \\          {
        \\            "type": "command",
        \\            "command": "/usr/local/bin/enforcer hook"
        \\          }
        \\        ]
        \\      }
        \\    ]
        \\  }
        \\}
        \\
    );
}

test "uninstall removes every enforcer hook and keeps the rest" {
    try roundTrip(
        \\{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"log.sh"},{"type":"command","command":"'/opt/my tools/enforcer' hook"}]},{"hooks":[{"type":"command","command":"/usr/local/bin/enforcer hook"}]}]}}
    , .off, true,
        \\{
        \\  "hooks": {
        \\    "UserPromptSubmit": [
        \\      {
        \\        "hooks": [
        \\          {
        \\            "type": "command",
        \\            "command": "log.sh"
        \\          }
        \\        ]
        \\      }
        \\    ]
        \\  }
        \\}
        \\
    );
}

test "uninstall drops containers it emptied" {
    try roundTrip(
        \\{"model":"opus","hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/usr/local/bin/enforcer hook"}]}]}}
    , .off, true,
        \\{
        \\  "model": "opus"
        \\}
        \\
    );
}

test "uninstall without our hook reports unchanged" {
    try roundTrip("{\"hooks\":{\"Stop\":[]}}", .off, false,
        \\{
        \\  "hooks": {
        \\    "Stop": []
        \\  }
        \\}
        \\
    );
    try roundTrip("{}", .off, false, "{}\n");
}

test "unexpected shapes are errors, not rewrites" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var array_root = try parse(arena, "[]");
    try testing.expectError(error.SettingsNotObject, install(arena, &array_root, "x"));
    var bad_hooks = try parse(arena, "{\"hooks\":[]}");
    try testing.expectError(error.HooksNotObject, install(arena, &bad_hooks, "x"));
    var bad_event = try parse(arena, "{\"hooks\":{\"UserPromptSubmit\":{}}}");
    try testing.expectError(error.EventNotArray, uninstall(&bad_event));
    try testing.expectError(error.DuplicateField, parse(arena, "{\"a\":1,\"a\":2}"));
}

test "isEnforcerCommand" {
    try testing.expect(isEnforcerCommand("/usr/local/bin/enforcer hook"));
    try testing.expect(isEnforcerCommand("enforcer hook"));
    try testing.expect(isEnforcerCommand("'/opt/my tools/enforcer' hook"));
    try testing.expect(!isEnforcerCommand("/usr/local/bin/enforcer"));
    try testing.expect(!isEnforcerCommand("/bin/not-enforcer hook"));
    try testing.expect(!isEnforcerCommand("enforcer hook --other"));
}

test "renderCommand quotes only when needed" {
    const plain = try renderCommand(testing.allocator, "/usr/local/bin/enforcer");
    defer testing.allocator.free(plain);
    try testing.expectEqualStrings("/usr/local/bin/enforcer hook", plain);

    const spaced = try renderCommand(testing.allocator, "/opt/it's mine/enforcer");
    defer testing.allocator.free(spaced);
    try testing.expectEqualStrings("'/opt/it'\\''s mine/enforcer' hook", spaced);
}
