const std = @import("std");
const lox = @import("lox.zig");
const ParseType = lox.ParseType;
const Token = lox.Token;

pub const ExprValue = union(enum) {
    String: []const u8,
    Number: f64,
    Bool: bool,
    Nil: void,

    pub fn format(val: ExprValue, w: *std.Io.Writer) !void {
        switch (val) {
            .String => |s| try w.print("{s}", .{s}),
            .Number => |n| try w.print("{d}", .{n}),
            .Bool => |b| try w.print("{}", .{b}),
            .Nil => try w.print("nil"),
        }
    }
};

pub const Expr = union(enum) {
    Assign: ParseType(struct {
        name: Token,
        value: *Expr,
    }),
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
    Logical: ParseType(struct {
        left: *Expr,
        op: Token,
        right: *Expr,
    }),
    Unary: ParseType(struct {
        op: Token,
        expr: *Expr,
    }),
    Variable: ParseType(struct {
        name: Token,
    }),

    pub fn format(expr: Expr, w: *std.Io.Writer) !void {
        switch (expr) {
            .Assign => |a| try w.print("AssignExpr: {s} = {f}", .{ a.name, a.value }),
            .Binary => |b| {
                try w.print(
                    "BinaryExpr: {f} {s} {f}",
                    .{ b.left, b.op.lexeme, b.right },
                );
            },
            .Group => |g| try w.print("Grouping: ({f})", .{g.expr}),
            .Literal => |l| try w.print("{f}", .{l.value}),
            .Logical => |l| try w.print("xx  {s}  yy", .{l.op.lexeme}),
            .Unary => |u| try w.print("Unary: {s} {f}", .{ u.op.lexeme, u.expr }),
            .Variable => |v| try w.print("Variable: {s}", .{v.name.lexeme}),
        }
    }
};
