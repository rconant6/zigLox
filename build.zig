const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options for tracing
    const debug_trace = b.option(bool, "debug-trace", "Enable debug trace execution") orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "debug_trace_execution", debug_trace);

    // ===== INTERPRETER (Tree-Walking) =====

    const interp_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    interp_module.addOptions("build_options", build_options);

    const exe_interp = b.addExecutable(.{
        .name = "zlox_interp",
        .root_module = interp_module,
    });
    b.installArtifact(exe_interp);

    // Standard interpreter run
    const run_interp = b.addRunArtifact(exe_interp);
    run_interp.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_interp.addArgs(args);
    }

    const run_interp_step = b.step("runInt", "Run zlox interpreter");
    run_interp_step.dependOn(&run_interp.step);

    // Debug interpreter run (with tracing enabled)
    const interp_debug_options = b.addOptions();
    interp_debug_options.addOption(bool, "debug_trace_execution", true);

    const interp_debug_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    interp_debug_module.addOptions("build_options", interp_debug_options);

    const exe_interp_debug = b.addExecutable(.{
        .name = "zlox_interp_debug",
        .root_module = interp_debug_module,
    });

    const run_interp_debug = b.addRunArtifact(exe_interp_debug);
    run_interp_debug.step.dependOn(&b.addInstallArtifact(exe_interp_debug, .{}).step);
    if (b.args) |args| {
        run_interp_debug.addArgs(args);
    }

    const run_interp_debug_step = b.step("runIntDebug", "Run zlox interpreter with debug tracing");
    run_interp_debug_step.dependOn(&run_interp_debug.step);

    // ===== COMPILER (Bytecode VM) =====

    const comp_module = b.createModule(.{
        .root_source_file = b.path("src_comp/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    comp_module.addOptions("build_options", build_options);

    const exe_comp = b.addExecutable(.{
        .name = "zlox_comp",
        .root_module = comp_module,
    });
    b.installArtifact(exe_comp);

    // Standard compiler run
    const run_comp = b.addRunArtifact(exe_comp);
    run_comp.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_comp.addArgs(args);
    }

    const run_comp_step = b.step("runComp", "Run zlox compiler");
    run_comp_step.dependOn(&run_comp.step);

    // Debug compiler run (with tracing enabled)
    const comp_debug_options = b.addOptions();
    comp_debug_options.addOption(bool, "debug_trace_execution", true);

    const comp_debug_module = b.createModule(.{
        .root_source_file = b.path("src_comp/compiler.zig"),
        .target = target,
        .optimize = optimize,
    });
    comp_debug_module.addOptions("build_options", comp_debug_options);

    const exe_comp_debug = b.addExecutable(.{
        .name = "zlox_comp_debug",
        .root_module = comp_debug_module,
    });

    const run_comp_debug = b.addRunArtifact(exe_comp_debug);
    run_comp_debug.step.dependOn(&b.addInstallArtifact(exe_comp_debug, .{}).step);
    if (b.args) |args| {
        run_comp_debug.addArgs(args);
    }

    const run_comp_debug_step = b.step("runCompDebug", "Run zlox compiler with debug tracing");
    run_comp_debug_step.dependOn(&run_comp_debug.step);

    // ===== CONVENIENCE STEPS =====

    // Run both versions
    const run_both_step = b.step("runBoth", "Run both interpreter and compiler versions");
    run_both_step.dependOn(&run_interp.step);
    run_both_step.dependOn(&run_comp.step);

    // Default run step (interpreter)
    const run_default_step = b.step("run", "Run default zlox (interpreter)");
    run_default_step.dependOn(&run_interp.step);

    // ===== RELEASE BUILDS =====
    // Optimized release builds (tracing disabled)
    const release_options = b.addOptions();
    release_options.addOption(bool, "debug_trace_execution", false);

    const interp_release_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    interp_release_module.addOptions("build_options", release_options);

    const exe_interp_release = b.addExecutable(.{
        .name = "zlox_interp_release",
        .root_module = interp_release_module,
    });

    const comp_release_module = b.createModule(.{
        .root_source_file = b.path("src_comp/compiler.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    comp_release_module.addOptions("build_options", release_options);

    const exe_comp_release = b.addExecutable(.{
        .name = "zlox_comp_release",
        .root_module = comp_release_module,
    });

    const install_release_step = b.step("install-release", "Install optimized release builds");
    install_release_step.dependOn(&b.addInstallArtifact(exe_interp_release, .{}).step);
    install_release_step.dependOn(&b.addInstallArtifact(exe_comp_release, .{}).step);
}
//  zig build runInt                    # Run interpreter (normal)
//  zig build runIntDebug               # Run interpreter with debug tracing
//  zig build testInt                   # Run interpreter tests

//  Compiler (Bytecode VM):
//  bashzig build runComp               # Run compiler (normal)
//  zig build runCompDebug              # Run compiler with debug tracing
//  zig build testComp                  # Run compiler tests

//  Combined/Convenience:
//  zig build run                   # Default (runs interpreter)
//  zig build runBoth                   # Run both versions
//  zig build test                      # Run all tests
//  zig build install-release           # Build optimized releases

//  With command-line options:
//  zig build runInt -Ddebug-trace=true     # Enable tracing via flag
//  zig build runComp -Ddebug-trace=false   # Explicitly disable tracing
