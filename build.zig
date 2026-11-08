const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const exe = b.addExecutable(.{
        .name = "enforcer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });

    const opts = b.addOptions();
    opts.addOptionPath("exe_path", exe.getEmittedBin());
    const cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/cli_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cli_tests.root_module.addOptions("build_options", opts);
    const run_cli_tests = b.addRunArtifact(cli_tests);
    run_cli_tests.setCwd(b.path("."));

    const test_step = b.step("test", "Run unit and CLI tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
    test_step.dependOn(&run_cli_tests.step);

    const check = b.step("check", "Run zig fmt --check and the tests");
    const fmt = b.addFmt(.{ .paths = &.{ b.path("build.zig"), b.path("build.zig.zon"), b.path("src"), b.path("test") }, .check = true });
    check.dependOn(&fmt.step);
    check.dependOn(test_step);
}
