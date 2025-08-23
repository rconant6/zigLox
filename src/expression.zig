const std = @import("std");
const lox = @import("lox.zig");
const Token = lox.Token;

fn ExprType(comptime fields: type) type {
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

pub const ExprValue = union(enum) {
    String: []const u8,
    Number: f64,
    Bool: bool,

    pub fn format(val: ExprValue, w: *std.Io.Writer) !void {
        switch (val) {
            .String => |s| w.print("{s}", .{s}),
            .Number => |n| w.print("{d}", .{n}),
            .Bool => |b| w.print("{}", .{b}),
        }
    }
};

pub const Expr = union(enum) {
    Binary: ExprType(struct {
        left: *Expr,
        op: Token,
        right: *Expr,
    }),
    Group: ExprType(struct {
        expr: *Expr,
    }),
    Literal: ExprType(struct {
        value: ExprValue,
    }),
    Unary: ExprType(struct {
        op: Token,
        expr: *Expr,
    }),

    pub fn format(expr: Expr, w: *std.Io.Writer) !void {
        switch (expr) {
            .Binary => |b| {
                try w.print(
                    "BinaryExpr:\n  left {f} {s} right {f}",
                    .{ b.left, b.op.lexeme, b.right },
                );
            },
            .Group => |g| {
                try w.print("Grouping:\n  ({f})", .{g.expr});
            },
            .Literal => |l| {
                try w.print("Literal:\n  {f}", .{l.value});
            },
            .Unary => |u| {
                try w.print("Unary:\n  {s} {f}", .{ u.op.lexeme, u.expr });
            },
        }
    }
};
