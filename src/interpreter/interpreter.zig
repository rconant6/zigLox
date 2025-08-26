const std = @import("std");
const ArrayList = std.ArrayList;

const lox = @import("../lox.zig");
const out_writer = lox.out_writer;
const Callable = lox.Callable;
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
    return_value: ?RuntimeValue = null,

    pub fn init(
        gpa: std.mem.Allocator,
        diagnostic: *DiagnosticReporter,
        env: *Environment,
    ) !Interpreter {
        const clock_native = try gpa.create(RuntimeValue);
        clock_native.* = .{
            .Callable = .{ .NativeFunction = .{
                .name = "clock",
            } },
        };
        try env.define("clock", clock_native.*);

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

    pub fn execute(self: *Interpreter, stmt: Stmt) LoxError!void {
        switch (stmt) {
            .Block => |b| {
                const outer_env = self.environment;
                const inner_env = try self.allocator.create(Environment);
                inner_env.* = Environment.createLocalEnv(outer_env);
                self.environment = inner_env;
                defer {
                    self.environment = outer_env;
                    self.allocator.destroy(inner_env);
                }
                return for (b.statements) |s| {
                    self.execute(s.*) catch |err| {
                        self.processRuntimeError(err, "RUNTIME ERROR in Block", b.loc);
                        return err;
                    };
                };
            },
            .Expression => |e| _ = try self.evalExpr(e.value),
            .Function => |f| {
                const function = RuntimeValue{
                    .Callable = .{
                        .Function = .{
                            .name = f.name,
                            .params = f.params,
                            .body = f.body,
                        },
                    },
                };
                try self.environment.define(f.name.lexeme, function);
            },
            .If => |i| {
                const condition = try self.evalExpr(i.condition);

                if (condition.isTruthy()) {
                    try self.execute(i.then_branch.*);
                } else if (i.else_branch) |eb| {
                    try self.execute(eb.*);
                }
            },
            .Print => |p| {
                const value = try self.evalExpr(p.value);
                try out_writer.print("{f}\n", .{value});
                try out_writer.flush();
            },
            // .Return => |r| {
            //     const value = if (r.value) |val| try self.evalExpr(val) else RuntimeValue.Nil;
            //     self.return_value = value;
            //     return LoxError.Return; // "Throw" the return
            // },
            .Variable => |v| {
                const value = if (v.value) |val| try self.evalExpr(val) else RuntimeValue.Nil;
                try self.environment.define(v.name.lexeme, value);
            },
            .While => |w| {
                while (true) {
                    const condition = try self.evalExpr(w.condition);
                    if (!condition.isTruthy()) break;

                    try self.execute(w.body.*);
                }
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
            .Call => |c| {
                const callee = try self.evalExpr(c.callee);

                var arguments: ArrayList(RuntimeValue) = .empty;
                defer arguments.deinit(self.allocator);
                for (c.args) |arg| {
                    const arg_value = try self.evalExpr(arg);
                    try arguments.append(self.allocator, arg_value);
                }

                switch (callee) {
                    .Callable => |callable| {
                        if (arguments.items.len != callable.arity()) {
                            self.processRuntimeError(
                                LoxError.WrongNumberOfArguments,
                                "Wrong number of arguments",
                                c.paren,
                            );
                            return LoxError.WrongNumberOfArguments;
                        }
                        return callable.call(self, arguments.items);
                    },
                    else => {
                        self.processRuntimeError(
                            LoxError.NotCallable,
                            "Only functions and classes are callable",
                            c.paren,
                        );
                        return LoxError.NotCallable;
                    },
                }
            },
            .Group => |g| return try self.evalExpr(g.expr),
            .Literal => |l| return switch (l.value) {
                .String => |s| RuntimeValue{ .String = s },
                .Number => |n| RuntimeValue{ .Number = n },
                .Bool => |b| RuntimeValue{ .Bool = b },
                .Nil => .Nil,
            },
            .Logical => |l| {
                const left = try self.evalExpr(l.left);

                if (l.op.type == .OR) {
                    if (left.isTruthy()) return left;
                } else {
                    if (!left.isTruthy()) return left;
                }

                return self.evalExpr(l.right);
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
