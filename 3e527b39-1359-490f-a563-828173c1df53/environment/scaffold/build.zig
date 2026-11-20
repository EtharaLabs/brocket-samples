const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Zig 0.15 moved linkage onto the module, so link_libc is a module option and system
    // libraries are linked through the module rather than the compile step.
    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.linkSystemLibrary("z", .{});

    const exe = b.addExecutable(.{
        .name = "git",
        .root_module = root,
    });
    b.installArtifact(exe);
}
