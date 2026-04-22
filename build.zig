const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const threaded_mod = b.addModule("Threaded", .{
        .root_source_file = b.path("lib/std/Io/Threaded.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "run smoke test");

    {
        const exe = b.addExecutable(.{
            .name = "smoke",
            .root_module = b.createModule(.{
                .root_source_file = b.path("test/smoke.zig"),
                .target = target,
                .optimize = optimize,
                .single_threaded = false,
            }),
        });
        exe.root_module.addImport("Threaded", threaded_mod);
        const install = b.addInstallArtifact(exe, .{});

        const run = b.addRunArtifact(exe);
        run.step.dependOn(&install.step);
        test_step.dependOn(&run.step);
    }
}
