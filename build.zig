const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addModule("lib", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    const thermit = b.dependency("thermit", .{ .target = target, .optimize = optimize });
    lib.addImport("thermit", thermit.module("thermit"));

    const exe = b.addExecutable(.{
        .name = "zss",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    exe.root_module.addImport("lib", lib);

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
