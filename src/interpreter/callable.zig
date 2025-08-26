const std = @import("std");

const lox = @import("../lox.zig");
const Environment = lox.Environment;
const Interpreter = lox.Interpreter;
const LoxError = lox.LoxError;
const RuntimeValue = lox.RuntimeValue;
const Stmt = lox.Stmt;
const Token = lox.Token;

pub const Callable = union(enum) {
    Function: struct {
        name: Token,
        params: []const Token,
        body: *const Stmt,
        closure: *Environment,
    },
    NativeFunction: struct {
        name: []const u8,
        arity: usize,
        callFn: *const fn (
            *Interpreter,
            arguments: []const RuntimeValue,
        ) LoxError!RuntimeValue,
    },

    pub fn call(
        self: Callable,
        interpreter: *Interpreter,
        arguments: []const RuntimeValue,
    ) LoxError!RuntimeValue {
        switch (self) {
            .Function => |func| return self.callFunction(func, interpreter, arguments),
            .NativeFunction => |native| return native.callFn(interpreter, arguments),
        }
    }

    pub fn arity(self: Callable) usize {
        switch (self) {
            .Function => |func| return func.params.len,
            .NativeFunction => |native| return native.arity,
        }
    }

    fn callFunction(
        self: Callable,
        func: @TypeOf(self.Function),
        interpreter: *Interpreter,
        arguments: []const RuntimeValue,
    ) LoxError!RuntimeValue {
        const local_env = try interpreter.allocator.create(Environment);
        defer interpreter.allocator.destroy(local_env);
        local_env.* = .createGlobalEnv(interpreter.allocator);
        const parent_env = interpreter.environment;
        interpreter.environment = local_env;
        defer interpreter.environment = parent_env;

        for (func.params, arguments) |param, arg| {
            try local_env.define(param.lexeme, arg);
        }

        interpreter.execute(func.body.*) catch |err| switch (err) {
            LoxError.Return => {
                const return_val = interpreter.return_value orelse .Nil;
                interpreter.return_value = null;
                return return_val;
            },
            else => return err,
        };

        return RuntimeValue.Nil;
    }

    pub fn getName(self: Callable) []const u8 {
        switch (self) {
            .Function => |func| return func.name.lexeme,
            .NativeFunction => |native| return native.name,
        }
    }
};
