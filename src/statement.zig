const std = @import("std");
const lox = @import("lox.zig");
const Expr = lox.Expr;
const ParseType = lox.ParseType;
const Token = lox.Token;

pub const Stmt = union(enum) {
    Expression: ParseType(struct {
        value: *Expr,
    }),
    Print: ParseType(struct {
        value: *Expr,
    }),

    pub fn format(stmt: Stmt, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (stmt) {
            .Expression => |e| {
                try w.print("ExpressionStmt: {f}", .{e.value});
            },
            .Print => |p| {
                try w.print("PrintStmt: {f}", .{p.value});
            },
        }
    }
};
