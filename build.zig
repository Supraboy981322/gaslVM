const std = @import("std");

pub fn build(b: *std.Build) !void {
    const root = b.option([]const u8, "root", "override root dir") orelse "src";

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opts = b.addOptions();

    //build settings
    const bin = b.addExecutable(.{
        .name = "gaslVM",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ root, "main.zig"})),
            .target = target,
            .optimize = optimize,
        }),
    });

    {
        const debug_trace = b.option(bool, "use_debug_trace", "enable debug tracing");
        opts.addOption(bool, "use_debug_trace", if (debug_trace) |t| t else false);

        const stack_size = b.option(usize, "stack_size", "set the stack size") orelse 256;
        opts.addOption(usize, "stack_size", stack_size);
    }

    bin.root_module.addOptions("options", opts);

    b.installArtifact(bin);
    //for 'zig build run'
    const run_bin = b.addRunArtifact(bin);
    if (b.args) |args| {
        run_bin.addArgs(args);
    }
    const run_step = b.step("run", "run the program");
    run_step.dependOn(&run_bin.step);

    const tests = b.addTest(.{
        .root_module = b.addModule("tests", .{
            .root_source_file = b.path(b.pathJoin(&.{ root, "test.zig" })),
            .target = target,
            .optimize = optimize,
        }),
    });

    tests.root_module.addOptions("options", opts);

    const run_test = b.addRunArtifact(tests);
    run_test.has_side_effects = true;

    const test_step = b.step("test", "run the tests");
    test_step.dependOn(&run_test.step);
}
