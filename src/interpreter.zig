const std = @import("std");
const ArrayList = std.ArrayList;

const lox = @import("lox.zig");
const out_writer = lox.out_writer;
const Callable = lox.Callable;
const DiagnosticReporter = lox.DiagnosticReporter;
const Environment = lox.Environment;
const ErrorContext = lox.ErrorContext;
const Expr = lox.Expr;
const LoxError = lox.LoxError;
const InterpreterConfig = lox.InterpreterConfig;
const RuntimeValue = lox.RuntimeValue;
const Stmt = lox.Stmt;
const Token = lox.Token;

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticReporter,
    environment: *Environment,
    return_value: ?RuntimeValue = null,
    source_code: []const u8,
    expressions: []const Expr,
    statements: []const Stmt,
    locals: std.AutoArrayHashMapUnmanaged(Token, usize),

    pub fn init(
        gpa: std.mem.Allocator,
        config: InterpreterConfig,
    ) !Interpreter {
        const clock_native = try gpa.create(RuntimeValue);
        clock_native.* = .{
            .Callable = .{ .NativeFunction = .{
                .name = "clock",
            } },
        };
        try config.global_env.define("clock", clock_native.*);

        return .{
            .allocator = gpa,
            .diagnostics = config.diagnostic,
            .source_code = config.source_code,
            .environment = config.global_env,
            .expressions = config.expressions,
            .statements = config.statements,
            .locals = .empty,
        };
    }

    pub fn interpret(self: *Interpreter, program: Stmt) !void {
        try self.execute(program);
    }

    pub fn resolve(self: *Interpreter, expr: Expr, depth: usize) !void {
        const token = switch (expr) {
            .Assign => |a| a.name,
            .Variable => |v| v.name,
            else => return,
        };
        try self.locals.put(self.allocator, token, depth);
    }

    pub fn execute(self: *Interpreter, root: Stmt) LoxError!void {
        switch (root) {
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
                    const stmt = self.statements[s];
                    self.execute(stmt) catch |err| {
                        switch (err) {
                            LoxError.Return => return err,
                            else => {
                                self.processRuntimeError(
                                    err,
                                    "RUNTIME ERROR in Block",
                                    b.loc,
                                );
                                return err;
                            },
                        }
                    };
                };
            },
            .Class => |c| {
                const name = c.name.lexeme(self.source_code);
                try self.environment.define(name, .Nil);
                const new_class = RuntimeValue{
                    .Callable = .{
                        .Class = .{
                            .name = name,
                        },
                    },
                };
                try self.environment.assign(name, new_class);
            },
            .Expression => |e| _ = try self.evalExpr(self.expressions[e.value]),
            .Function => |f| {
                const closure_env = try self.allocator.create(Environment);
                closure_env.* = Environment.createLocalEnv(self.environment);

                const function = RuntimeValue{
                    .Callable = .{
                        .Function = .{
                            .name = f.name.lexeme(self.source_code),
                            .params = f.params,
                            .body = self.statements[f.body],
                            .closure = closure_env,
                        },
                    },
                };
                try self.environment.define(f.name.lexeme(self.source_code), function);
            },
            .If => |i| {
                const condition = try self.evalExpr(self.expressions[i.condition]);

                if (condition.isTruthy()) {
                    try self.execute(self.statements[i.then_branch]);
                } else if (i.else_branch) |eb| {
                    try self.execute(self.statements[eb]);
                }
            },
            .Print => |p| {
                const value = try self.evalExpr(self.expressions[p.value]);
                try out_writer.print("{f}\n", .{value});
                try out_writer.flush();
            },
            .Return => |r| {
                const value = if (r.value) |val|
                    try self.evalExpr(self.expressions[val])
                else
                    RuntimeValue.Nil;
                self.return_value = value;
                return LoxError.Return;
            },
            .Variable => |v| {
                const value = if (v.value) |val| try self.evalExpr(
                    self.expressions[val],
                ) else RuntimeValue.Nil;
                try self.environment.define(v.name.lexeme(self.source_code), value);
            },
            .While => |w| {
                while (true) {
                    const condition = try self.evalExpr(self.expressions[w.condition]);
                    if (!condition.isTruthy()) break;

                    try self.execute(self.statements[w.body]);
                }
            },
        }
    }

    pub fn evalExpr(self: *Interpreter, expr: Expr) LoxError!RuntimeValue {
        switch (expr) {
            .Assign => |a| {
                const value = try self.evalExpr(self.expressions[a.value]);
                const name = a.name.lexeme(self.source_code);
                if (self.locals.get(a.name)) |distance| {
                    var env = self.environment;
                    for (0..distance) |_| {
                        env = env.parent orelse return LoxError.UndefinedVariable;
                    }
                    try env.assign(name, value);
                } else {
                    try self.environment.assign(name, value);
                }
                return value;
            },
            .Binary => |b| {
                const right = try self.evalExpr(self.expressions[b.right]);
                const left = try self.evalExpr(self.expressions[b.left]);
                return try evalBinary(self, b.op, left, right);
            },
            .Call => |c| {
                const callee = try self.evalExpr(self.expressions[c.callee]);

                var arguments: ArrayList(RuntimeValue) = .empty;
                defer arguments.deinit(self.allocator);
                for (c.args) |arg| {
                    const arg_value = try self.evalExpr(self.expressions[arg]);
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
                        return callable.call(self, arguments.items, self.source_code);
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
            .Group => |g| return try self.evalExpr(self.expressions[g.expr]),
            .Literal => |l| return switch (l.value) {
                .String => |s| RuntimeValue{ .String = s },
                .Number => |n| RuntimeValue{ .Number = n },
                .Bool => |b| RuntimeValue{ .Bool = b },
                .Nil => .Nil,
            },
            .Logical => |l| {
                const left = try self.evalExpr(self.expressions[l.left]);

                if (l.op.tag == .Or) {
                    if (left.isTruthy()) return left;
                } else {
                    if (!left.isTruthy()) return left;
                }

                return self.evalExpr(self.expressions[l.right]);
            },
            .Unary => |u| {
                const right = try self.evalExpr(self.expressions[u.expr]);

                switch (u.op.tag) {
                    .Bang => return .{ .Bool = !right.isTruthy() },
                    .Minus => {
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
                const name = v.name.lexeme(self.source_code);
                if (self.locals.get(v.name)) |distance| {
                    // Walk up the environment chain
                    var env = self.environment;
                    std.debug.print("Assignment distance: {}\n", .{distance});
                    for (0..distance) |_| {
                        env = env.parent orelse return LoxError.UndefinedVariable;
                    }
                    return env.get(name);
                } else {
                    // Global variable
                    return self.environment.get(name);
                }
            },
        }
    }

    fn evalBinary(
        self: *Interpreter,
        op: Token,
        left: RuntimeValue,
        right: RuntimeValue,
    ) LoxError!RuntimeValue {
        switch (op.tag) {
            .EqualEqual => return RuntimeValue{ .Bool = left.isEqual(right) },
            .BangEqual => return RuntimeValue{ .Bool = !left.isEqual(right) },
            .Plus => {
                const left_tag = std.meta.activeTag(left);
                const right_tag = std.meta.activeTag(right);

                if (left_tag != right_tag) {
                    return LoxError.TypeMismatch;
                }

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
            .Minus, .Slash, .Star, .Greater, .GreaterEqual, .Less, .LessEqual => |sym| {
                const left_tag = std.meta.activeTag(left);
                const right_tag = std.meta.activeTag(right);

                if (left_tag != right_tag) {
                    return LoxError.TypeMismatch;
                }

                if (left_tag != .Number) return LoxError.InvalidOperands;
                const left_num = left.Number;
                const right_num = right.Number;
                return switch (sym) {
                    .Minus => .{ .Number = left_num - right_num },
                    .Slash => .{ .Number = left_num / right_num }, // TODO: Divide by 0 check
                    .Star => .{ .Number = left_num * right_num },
                    .Greater => .{ .Bool = left_num > right_num },
                    .Less => .{ .Bool = left_num < right_num },
                    .GreaterEqual => .{ .Bool = left_num >= right_num },
                    .LessEqual => .{ .Bool = left_num <= right_num },
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
        self.diagnostics.reportError(ErrorContext.init(message, err, token));
    }
};
