const std = @import("std");

const lox = @import("lox.zig");
const Environment = lox.Environment;
const ExprIdx = lox.ExprIdx;
const Instance = lox.Instance;
const Interpreter = lox.Interpreter;
const LoxError = lox.LoxError;
const RuntimeValue = lox.RuntimeValue;
const Stmt = lox.Stmt;
const Token = lox.Token;

const NativeFnImpl = struct {
    arity: usize,
    callFn: *const fn (*Interpreter, []const RuntimeValue) LoxError!RuntimeValue,
};

const NATIVE_FUNCTIONS = std.StaticStringMap(NativeFnImpl).initComptime(.{
    .{ "clock", NativeFnImpl{ .arity = 0, .callFn = clockImpl } },
    // .{ "print", NativeFnImpl{ .arity = 1, .callFn = printImpl } },
});

pub const ClassData = struct {
    name: []const u8,
    methods: std.StringHashMap(FunctionData),

    pub fn getMethod(self: ClassData, name: []const u8) ?RuntimeValue {
        const method = self.methods.get(name) orelse return null;
        return .{
            .Callable = .{
                .Function = method,
            },
        };
    }
};

pub const FunctionData = struct {
    name: []const u8,
    params: []const Token,
    body: Stmt,
    closure: *Environment,
    isInitializer: bool = false,

    pub fn bind(self: FunctionData, instance: *Instance) LoxError!RuntimeValue {
        const env = try self.closure.gpa.create(Environment);
        env.* = Environment.createLocalEnv(self.closure);
        try env.define("this", RuntimeValue{ .Instance = instance });

        return RuntimeValue{
            .Callable = .{
                .Function = .{
                    .name = self.name,
                    .params = self.params,
                    .body = self.body,
                    .closure = env,
                    .isInitializer = self.isInitializer,
                },
            },
        };
    }
};

pub const Callable = union(enum) {
    Class: ClassData,
    Function: FunctionData,
    NativeFunction: struct {
        name: []const u8,
    },

    pub fn call(
        self: Callable,
        interpreter: *Interpreter,
        arguments: []const RuntimeValue,
        src: []const u8,
    ) LoxError!RuntimeValue {
        switch (self) {
            .Class => |c| {
                const instance = try interpreter.allocator.create(Instance);
                instance.* = .{
                    .class = .{
                        .name = c.name,
                        .methods = c.methods,
                    },
                    .fields = std.StringHashMap(RuntimeValue).init(interpreter.allocator),
                };

                if (c.getMethod("init")) |init| switch (init) {
                    .Callable => |callable| {
                        const bound_init = try callable.Function.bind(instance);
                        _ = try bound_init.Callable.call(interpreter, arguments, src);
                    },
                    else => unreachable,
                };
                return .{ .Instance = instance };
            },
            .Function => |func| {
                if (func.isInitializer) return func.closure.get("this");

                return self.callFunction(
                    func,
                    interpreter,
                    arguments,
                    src,
                );
            },
            .NativeFunction => |native| {
                const impl = NATIVE_FUNCTIONS.get(native.name) orelse return .Nil;
                return impl.callFn(interpreter, arguments);
            },
        }
    }

    pub fn arity(self: Callable) usize {
        switch (self) {
            .Class => |c| {
                return if (c.getMethod("init")) |init| init.Callable.arity() else 0;
            },
            .Function => |func| return func.params.len,
            .NativeFunction => |native| return NATIVE_FUNCTIONS.get(native.name).?.arity,
        }
    }

    pub fn getName(self: Callable, src: []const u8) []const u8 {
        switch (self) {
            .Class => |class| return class.name.lexeme(src),
            .Function => |func| return func.name.lexeme(src),
            .NativeFunction => |native| return native.name,
        }
    }

    fn callFunction(
        self: Callable,
        func: @TypeOf(self.Function),
        interpreter: *Interpreter,
        arguments: []const RuntimeValue,
        src: []const u8,
    ) LoxError!RuntimeValue {
        const local_env = try interpreter.allocator.create(Environment);
        local_env.* = .createLocalEnv(func.closure);

        const parent_env = interpreter.environment;
        interpreter.environment = local_env;
        defer interpreter.environment = parent_env;

        for (func.params, arguments) |param, arg| {
            const param_name = param.lexeme(src);
            try local_env.define(param_name, arg);
        }

        interpreter.execute(func.body) catch |err| switch (err) {
            LoxError.Return => {
                const return_val = interpreter.return_value orelse .Nil;
                interpreter.return_value = null;
                return return_val;
            },
            else => {
                return err;
            },
        };

        return RuntimeValue.Nil;
    }
};

// MARK: BUILTIN FUNCTIONS
fn clockImpl(interpreter: *Interpreter, arguments: []const RuntimeValue) LoxError!RuntimeValue {
    _ = interpreter;
    _ = arguments;
    const now: f64 = @floatFromInt(std.time.milliTimestamp());
    return RuntimeValue{ .Number = now };
}
