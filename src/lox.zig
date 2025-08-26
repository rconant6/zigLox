const std = @import("std");
const exp = @import("parser/expression.zig");
const intp = @import("interpreter/interpreter.zig");
const lerr = @import("loxError.zig");
const tok = @import("scanner/token.zig");
const stmt = @import("parser/statement.zig");
pub const Callable = @import("interpreter/callable.zig").Callable;
pub const DiagnosticReporter = @import("DiagnoticReporter.zig");
pub const Environment = @import("interpreter/Environment.zig");
pub const ErrorContext = lerr.ErrorContext;
pub const Expr = exp.Expr;
pub const ExprValue = exp.ExprValue;
pub const Interpreter = intp.Interpreter;
pub const LoxError = lerr.LoxError;
pub const Parser = @import("parser/Parser.zig");
pub const Scanner = @import("scanner/Scanner.zig");
pub const Stmt = stmt.Stmt;
pub const Token = tok.Token;
pub const TokenType = tok.TokenType;

pub const RuntimeValue = union(enum) {
    Bool: bool,
    Nil: void,
    Number: f64,
    String: []const u8,
    Callable: Callable,

    pub fn isEqual(self: RuntimeValue, other: RuntimeValue) bool {
        std.debug.assert(std.meta.activeTag(self) == std.meta.activeTag(other));

        return switch (self) {
            .Bool => |b| b == other.Bool,
            .Nil => true,
            .Number => |n| n == other.Number,
            .String => |s| std.mem.eql(u8, s, other.String),
            .Callable => false,
        };
    }

    pub fn isTruthy(val: RuntimeValue) bool {
        return switch (val) {
            .Bool => |b| b,
            .Nil => false,
            else => true,
        };
    }
    pub fn format(val: RuntimeValue, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try switch (val) {
            .Bool => |b| w.print("{}", .{b}),
            .Nil => w.print("NIL", .{}),
            .Number => |n| w.print("{d}", .{n}),
            .String => |s| w.print("{s}", .{s}),
            .Callable => |c| w.print("{s}", .{c.getName()}),
        };
    }
};

pub fn ParseType(comptime fields: type) type {
    const fields_info = @typeInfo(fields).@"struct".fields;

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields_info,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub const Location = struct {
    line: usize = 0,
    col: usize = 0,

    pub fn advance(loc: *Location) void {
        loc.col += 1;
    }
    pub fn advanceBy(loc: *Location, dist: u32) void {
        loc.col += dist;
    }
    pub fn nextLine(loc: *Location) void {
        loc.line += 1;
        loc.col = 1;
    }

    pub fn advanced(loc: Location) Location {
        return .{ .line = loc.line, .col = loc.col + 1 };
    }
    pub fn advancedBy(loc: Location, dist: u32) Location {
        return .{ .line = loc.line, .col = loc.col + dist };
    }

    pub fn format(loc: Location, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return w.print(
            "Location: [line:{d:4} col:{d:4}]",
            .{ loc.line, loc.col },
        );
    }
};

pub const LiteralValue = union(enum) {
    string: []const u8,
    number: f64,
    bool: bool,
    void: void,
};

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
