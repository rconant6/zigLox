const std = @import("std");
const build_options = @import("build_options");

// Get the debug trace setting from build options
const DEBUG_TRACE_EXECUTION = build_options.debug_trace_execution;

/// Basic trace function - replaces your original trace() function
pub inline fn trace(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print(fmt, args);
    }
}

/// Specialized trace functions for VM/Compiler operations
/// Trace VM instruction execution
pub inline fn traceInstruction(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("INSTR: " ++ fmt, args);
    }
}

/// Trace bytecode compilation
pub inline fn traceCompile(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("COMPILE: " ++ fmt, args);
    }
}

/// Trace VM stack operations
pub inline fn traceStack(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("STACK: " ++ fmt, args);
    }
}

/// Trace memory/GC operations
pub inline fn traceMemory(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("MEMORY: " ++ fmt, args);
    }
}

/// Trace function calls in VM
pub inline fn traceCall(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("CALL: " ++ fmt, args);
    }
}

/// Print bytecode disassembly
pub inline fn traceBytecode(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("BYTECODE: " ++ fmt, args);
    }
}

/// Generic trace functions (same as interpreter version)
pub inline fn traceWithTime(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        const timestamp = std.time.milliTimestamp();
        std.debug.print("[{}ms] " ++ fmt, .{timestamp} ++ args);
    }
}

pub inline fn traceEnter(comptime func_name: []const u8) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print(">>> {s}\n", .{func_name});
    }
}

pub inline fn traceExit(comptime func_name: []const u8) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("<<< {s}\n", .{func_name});
    }
}

pub inline fn traceVar(comptime name: []const u8, value: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        std.debug.print("{s} = {any}\n", .{ name, value });
    }
}

pub inline fn isTracingEnabled() bool {
    return DEBUG_TRACE_EXECUTION;
}

pub inline fn traceHere(comptime fmt: []const u8, args: anytype) void {
    if (comptime DEBUG_TRACE_EXECUTION) {
        const src = @src();
        std.debug.print("[{s}:{d}] " ++ fmt, .{ std.fs.path.basename(src.file), src.line } ++ args);
    }
}
