const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zss",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const zss = b.addRunArtifact(exe);
    zss.step.dependOn(b.getInstallStep());
    if (b.args) |args| zss.addArgs(args);
    const run = b.step("run", "Run the app");
    run.dependOn(&zss.step);

    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zsstest = b.addRunArtifact(tests);
    const testing = b.step("test", "Run unit tests");
    testing.dependOn(&zsstest.step);
}
