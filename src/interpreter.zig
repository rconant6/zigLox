const std = @import("std");
const lox = @import("lox.zig");
const out_writer = lox.out_writer;
const DiagnosticReporter = lox.DiagnosticReporter;
const Environment = lox.Environment;
const ErrorContext = lox.ErrorContext;
const Expr = lox.Expr;
const LoxError = lox.LoxError;
const RuntimeValue = lox.RuntimeValue;
const Stmt = lox.Stmt;
const Token = lox.Token;

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticReporter,
    environment: *Environment,

    pub fn init(
        gpa: std.mem.Allocator,
        diagnostic: *DiagnosticReporter,
        env: *Environment,
    ) Interpreter {
        return .{
            .allocator = gpa,
            .diagnostics = diagnostic,
            .environment = env,
        };
    }

    pub fn interpret(self: *Interpreter, program: []const Stmt) !void {
        for (program) |stmt| {
            try self.execute(stmt);
        }
    }

    fn execute(self: *Interpreter, stmt: Stmt) LoxError!void {
        switch (stmt) {
            .Expression => |e| _ = try self.evalExpr(e.value),
            .Print => |p| {
                const value = try self.evalExpr(p.value);
                try out_writer.print("{f}\n", .{value});
                try out_writer.flush();
            },
            .Variable => |v| {
                const value = if (v.value) |val| try self.evalExpr(val) else RuntimeValue.Nil;
                try self.environment.define(v.name.lexeme, value);
            },
        }
    }

    pub fn evalExpr(self: *Interpreter, expr: *Expr) LoxError!RuntimeValue {
        switch (expr.*) {
            .Assign => |a| {
                const value = try self.evalExpr(a.value);
                try self.environment.assign(a.name.lexeme, value);
                return value;
            },
            .Binary => |b| {
                const right = try self.evalExpr(b.right);
                const left = try self.evalExpr(b.left);
                return try evalBinary(self, b.op, left, right);
            },
            .Group => |g| return try self.evalExpr(g.expr),
            .Literal => |l| return switch (l.value) {
                .String => |s| RuntimeValue{ .String = s },
                .Number => |n| RuntimeValue{ .Number = n },
                .Bool => |b| RuntimeValue{ .Bool = b },
            },
            .Unary => |u| {
                const right = try self.evalExpr(u.expr);

                switch (u.op.type) {
                    .BANG => return .{ .Bool = !right.isTruthy() },
                    .MINUS => {
                        const right_tag = std.meta.activeTag(right);
                        if (right_tag != .Number) {
                            self.processRuntimeError(
                                LoxError.TypeMismatch,
                                "Unary (-) operation requires a number on the right hand side",
                                u.op,
                            );
                            return LoxError.TypeMismatch;
                        }
                        return .{ .Number = -right.Number };
                    },
                    else => return .{ .Nil = {} },
                }
            },
            .Variable => |v| {
                return self.environment.get(v.name.lexeme);
            },
        }
    }

    fn evalBinary(
        self: *Interpreter,
        op: Token,
        left: RuntimeValue,
        right: RuntimeValue,
    ) LoxError!RuntimeValue {
        const left_tag = std.meta.activeTag(left);
        const right_tag = std.meta.activeTag(right);

        if (left_tag != right_tag) {
            return LoxError.TypeMismatch;
        }

        switch (op.type) {
            .EQUAL_EQUAL => return RuntimeValue{ .Bool = left.isEqual(right) },
            .BANG_EQUAL => return RuntimeValue{ .Bool = !left.isEqual(right) },
            .PLUS => {
                switch (left_tag) {
                    .String => return .{ .String = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}{s}",
                        .{ left.String, right.String },
                    ) },
                    .Number => return .{ .Number = left.Number + right.Number },
                    else => {
                        self.processRuntimeError(
                            LoxError.InvalidOperands,
                            "Invalid Binary expression Operand {s}",
                            op,
                        );
                        return LoxError.InvalidBinaryOperand; // TODO: real error handle
                    },
                }
            },
            .MINUS, .SLASH, .STAR, .GREATER, .GREATER_EQUAL, .LESS, .LESS_EQUAL => |sym| {
                if (left_tag != .Number) return LoxError.InvalidOperands;
                const left_num = left.Number;
                const right_num = right.Number;
                return switch (sym) {
                    .MINUS => .{ .Number = left_num - right_num },
                    .SLASH => .{ .Number = left_num / right_num }, // TODO: Divide by 0 check
                    .STAR => .{ .Number = left_num * right_num },
                    .GREATER => .{ .Bool = left_num > right_num },
                    .LESS => .{ .Bool = left_num < right_num },
                    .GREATER_EQUAL => .{ .Bool = left_num >= right_num },
                    .LESS_EQUAL => .{ .Bool = left_num <= right_num },
                    else => return LoxError.InvalidOperands,
                };
            },
            else => return LoxError.InvalidBinaryOperand,
        }
    }

    fn processRuntimeError(
        self: *Interpreter,
        err: LoxError,
        message: []const u8,
        token: Token,
    ) void {
        self.diagnostics.reportError(
            ErrorContext.init(message, err)
                .withToken(token),
        );
    }
};
