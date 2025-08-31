const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod_interp = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_interp = b.addExecutable(.{
        .name = "zlox_interp",
        .root_module = exe_mod_interp,
    });

    b.installArtifact(exe_interp);

    const run_cmd = b.addRunArtifact(exe_interp);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("runInt", "run zlox interpreter");
    run_step.dependOn(&run_cmd.step);

    //////////////////  FOR PART 2 //////////////////////////
    const exe_mod_comp = b.createModule(.{
        .root_source_file = b.path("src_comp/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_comp = b.addExecutable(.{
        .name = "zlox_comp",
        .root_module = exe_mod_comp,
    });

    b.installArtifact(exe_comp);

    const run_comp = b.addRunArtifact(exe_comp);

    run_comp.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_comp.addArgs(args);
    }

    const run_comp_step = b.step("runComp", "run zlox compiler");
    run_comp_step.dependOn(&run_comp.step);
}
