const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Step 1: Declare the httpz dependency
    const httpz_dep = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    const dotenv_dep = b.dependency("dotenv", .{
        .target = target,
        .optimize = optimize,
    });

    // Step 2: Get the httpz module
    const httpz_module = httpz_dep.module("httpz");
    const dotenv_module = dotenv_dep.module("dotenv");

    // Step 3: Configure your executable
    const exe = b.addExecutable(.{
        .name = "uchihabot",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Step 4: Add the httpz module to your executable
    exe.root_module.addImport("httpz", httpz_module);
    exe.root_module.addImport("dotenv", dotenv_module);
    // Step 5: Install the executable
    b.installArtifact(exe);

    // Step 6: Configure the run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
