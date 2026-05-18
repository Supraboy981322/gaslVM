const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opts = b.addOptions();
    {
        const debug_trace = b.option(bool, "use_debug_trace", "enable debug tracing");
        opts.addOption(bool, "use_debug_trace", if (debug_trace) |t| t else false);

        const stack_size = b.option(usize, "stack_size", "set the stack size") orelse 256;
        opts.addOption(usize, "stack_size", stack_size);
    }

    const mod_root = b.option([]const u8, "mod_root", "override module root dir") orelse "src";
    const mod =try module(b, opts, target, optimize, mod_root);
    try tests(b, opts, target, optimize, mod_root);
    try cli(b, opts, target, optimize, mod);

}

fn cli(
    b:*std.Build,
    opts:*std.Build.Step.Options,
    target:std.Build.ResolvedTarget,
    optimize:?std.builtin.OptimizeMode,
    mod:*std.Build.Module,
) !void {
    const cli_root = b.option([]const u8, "cli_root", "override cli root dir") orelse "cli";
    const bin = b.addExecutable(.{
        .name = "gaslVM",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ cli_root, "main.zig"})),
            .target = target,
            .optimize = optimize,
        }),
    });
    bin.root_module.addOptions("options", opts);
    b.installArtifact(bin);

    const run_bin = b.addRunArtifact(bin);
    if (b.args) |args| {
        run_bin.addArgs(args);
    }
    const run_step = b.step("run", "run the program");
    run_step.dependOn(&run_bin.step);
}

fn module(
    b:*std.Build,
    opts:*std.Build.Step.Options,
    target:std.Build.ResolvedTarget,
    optimize:?std.builtin.OptimizeMode,
    mod_root:[]const u8
) !*std.Build.Module {
    var mod = b.addModule("gaslVM", .{
        .root_source_file = b.path(b.pathJoin(&.{ mod_root, "gaslVM.zig" })),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("options", opts);
    return mod;
}

fn tests(
    b:*std.Build,
    opts:*std.Build.Step.Options,
    target:std.Build.ResolvedTarget,
    optimize:?std.builtin.OptimizeMode,
    mod_root:[]const u8,
) !void {
    const ze_tests = b.addTest(.{
        .root_module = b.addModule("tests", .{
            .root_source_file = b.path(b.pathJoin(&.{ mod_root, "test.zig" })),
            .target = target,
            .optimize = optimize,
        }),
    });
    ze_tests.root_module.addOptions("options", opts);
    const run_test = b.addRunArtifact(ze_tests);
    run_test.has_side_effects = true;
    const test_step = b.step("test", "run the gaslVM tests");
    test_step.dependOn(&run_test.step);
}
