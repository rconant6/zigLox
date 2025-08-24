const std = @import("std");
const lox = @import("lox.zig");
const ParseType = lox.ParseType;
const Token = lox.Token;

pub const ExprValue = union(enum) {
    String: []const u8,
    Number: f64,
    Bool: bool,

    pub fn format(val: ExprValue, w: *std.Io.Writer) !void {
        switch (val) {
            .String => |s| try w.print("{s}", .{s}),
            .Number => |n| try w.print("{d}", .{n}),
            .Bool => |b| try w.print("{}", .{b}),
        }
    }
};

pub const Expr = union(enum) {
    Binary: ParseType(struct {
        left: *Expr,
        op: Token,
        right: *Expr,
    }),
    Group: ParseType(struct {
        expr: *Expr,
    }),
    Literal: ParseType(struct {
        value: ExprValue,
    }),
    Unary: ParseType(struct {
        op: Token,
        expr: *Expr,
    }),

    pub fn format(expr: Expr, w: *std.Io.Writer) !void {
        switch (expr) {
            .Binary => |b| {
                try w.print(
                    "BinaryExpr: {f} {s} {f}",
                    .{ b.left, b.op.lexeme, b.right },
                );
            },
            .Group => |g| {
                try w.print("Grouping: ({f})", .{g.expr});
            },
            .Literal => |l| {
                try w.print("{f}", .{l.value});
            },
            .Unary => |u| {
                try w.print("Unary: {s} {f}", .{ u.op.lexeme, u.expr });
            },
        }
    }
};
