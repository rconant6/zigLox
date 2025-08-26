const std = @import("std");
const lox = @import("../lox.zig");
const Expr = lox.Expr;
const ParseType = lox.ParseType;
const Token = lox.Token;

pub const Stmt = union(enum) {
    Block: ParseType(struct {
        statements: []const *Stmt,
        loc: Token,
    }),
    Expression: ParseType(struct {
        value: *Expr,
    }),
    Function: ParseType(struct {
        name: Token,
        params: []Token,
        body: []const *Stmt,
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
    While: ParseType(struct {
        condition: *Expr,
        body: *Stmt,
    }),

    pub fn format(stmt: Stmt, w: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (stmt) {
            .Block => |b| {
                try w.print("Block:\n", .{});
                for (b.statements) |statement| {
                    try w.print("  {f}", .{statement});
                }
            },
            .Function => |f| try w.print("Function: {s}", .{f.name.lexeme}),
            .If => |i| try w.print("IfStmt: ({f})", .{i.condition}),
            .Expression => |e| try w.print("ExpressionStmt: {f}", .{e.value}),
            .Print => |p| try w.print("PrintStmt: {f}", .{p.value}),
            .Variable => |v| try w.print("Variable: {s} = {}", .{ v.name.lexeme, v.value }),
            .While => |e| try w.print("WhileStmt: ({f})", .{e.condition}),
        }
    }
};
