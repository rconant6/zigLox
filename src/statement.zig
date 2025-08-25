const std = @import("std");
const lox = @import("lox.zig");
const Expr = lox.Expr;
const ParseType = lox.ParseType;
const Token = lox.Token;

pub const Stmt = union(enum) {
    Block: ParseType(struct {
        statements: []const Stmt,
        loc: Token,
    }),
    Expression: ParseType(struct {
        value: *Expr,
    }),
    If: ParseType(struct {
        condition: *Expr,
        then_branch: *Stmt,
        else_branch: ?*Stmt,
    }),
    Print: ParseType(struct {
        value: *Expr,
    }),
    Variable: ParseType(struct {
        name: Token,
        value: ?*Expr,
    }),

    pub fn format(stmt: Stmt, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (stmt) {
            .Block => |b| {
                try w.print("Block:\n", .{});
                for (b.statements) |statement| {
                    try w.print("  {f}", .{statement});
                }
            },
            .If => |i| {
                try w.print("IfStmt: ({f})", .{i.condition});
            },
            .Expression => |e| {
                try w.print("ExpressionStmt: {f}", .{e.value});
            },
            .Print => |p| {
                try w.print("PrintStmt: {f}", .{p.value});
            },
            .Variable => |v| {
                try w.print("Variable: {s} = {}", .{ v.name.lexeme, v.value });
            },
        }
    }
};
