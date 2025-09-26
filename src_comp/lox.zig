const std = @import("std");
const err = @import("loxError.zig");

pub const Chunk = @import("Chunk.zig");
pub const Compiler = @import("Comp.zig");
pub const DiagnosticReporter = @import("DiagnosticReporter.zig");
pub const ErrorContext = err.ErrorContext;
pub const LoxError = err.LoxError;
pub const Scanner = @import("Scanner.zig");
pub const Token = @import("Token.zig");
pub const VirtualMachine = @import("VirtualMachine.zig");

pub const Value = f64;

pub const SourceLocation = struct {
    line: u32,
    col: u32,

    pub fn format(self: SourceLocation, w: *std.Io.Writer) !void {
        try w.print("Line: {d:4} Col: {d:4}", .{
            self.line,
            self.col,
        });
    }
};

pub const Location = struct {
    start: u32,
    end: u32,

    fn len(loc: Location) u32 {
        return loc.end - loc.start;
    }

    pub fn slice(self: Location, code: []const u8) []const u8 {
        return code[self.start..self.end];
    }

    pub fn format(self: Location, w: *std.Io.Writer) !void {
        try w.print("Start: {d:4} End: {d:4} Len: {d:2}", .{
            self.start,
            self.end,
            self.len(),
        });
    }
};

pub const InterpretResult = enum {
    Ok,
    Compile_Error,
    Runtime_Error,
};

pub const ValueType = union(enum) {
    string: []const u8,
    number: f64,
    bool: bool,
    void: void,
};

pub const OpCode = enum(u8) {
    Add,
    Constant,
    Divide,
    Multiply,
    Negate,
    Not,
    Return,
    Subtract,
    Nil,
    True,
    False,

    pub const SIMPLE_LEN = 1;
    pub const CONSTANT_LEN = 2;
};

pub const trace_utils = @import("trace.zig");
pub const trace = trace_utils.trace;

const stdin = std.fs.File.stdin();
const stdout = std.fs.File.stdout();
const stderr = std.fs.File.stderr();
var stdin_buffer: [1024]u8 = undefined;
var stdout_buffer: [4096]u8 = undefined;
var stderr_buffer: [1024]u8 = undefined;
var stdin_reader = stdin.reader(&stdin_buffer);
var stdout_writer = stdout.writer(&stdout_buffer);
var stderr_writer = stderr.writer(&stderr_buffer);
pub const in_reader: *std.Io.Reader = &stdin_reader.interface;
pub const out_writer: *std.Io.Writer = &stdout_writer.interface;
pub const err_writer: *std.Io.Writer = &stderr_writer.interface;
