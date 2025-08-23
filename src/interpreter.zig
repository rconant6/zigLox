const std = @import("std");
const lox = @import("lox.zig");
const DiagnosticReporter = lox.DiagnosticReporter;
const Expr = lox.Expr;
const LoxError = lox.LoxError;
const Token = lox.Token;

pub const RuntimeValue = union(enum) {
    Bool: bool,
    Nil: void,
    Number: f64,
    String: []const u8,

    pub fn isEqual(self: RuntimeValue, other: RuntimeValue) bool {
        std.debug.assert(std.meta.activeTag(self) == std.meta.activeTag(other));

        return switch (self) {
            .Bool => |b| b == other.Bool,
            .Nil => true,
            .Number => |n| n == other.Number,
            .String => |s| std.mem.eql(u8, s, other.String),
        };
    }

    fn isTruthy(val: RuntimeValue) bool {
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
        };
    }
};

pub const Interpreter = struct {
    allocator: std.mem.Allocator,
    diagnostics: *DiagnosticReporter,

    pub fn init(gpa: std.mem.Allocator, diagnostic: *DiagnosticReporter) Interpreter {
        return .{
            .allocator = gpa,
            .diagnostics = diagnostic,
        };
    }

    pub fn evalExpr(self: *Interpreter, expr: *Expr) LoxError!RuntimeValue {
        switch (expr.*) {
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
                            // TODO: error stuff here
                            std.log.debug("yup can't minus a non-number", .{});
                            return LoxError.TypeMismatch;
                        }
                        return .{ .Number = -right.Number };
                    },
                    else => return .{ .Nil = {} },
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
                    else => return LoxError.InvalidOperands, // TODO: real error handle
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
};
