const std = @import("std");

const lox = @import("lox.zig");
const Environment = lox.Environment;
const ExprIdx = lox.ExprIdx;
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

pub const Instance = struct {
    class: ClassData,
    fields: std.StringHashMap(ExprIdx),

    pub fn get(self: Instance, name: []const u8) LoxError!?ExprIdx {
        return self.fields.get(name);
    }

    pub fn set(self: *Instance, name: []const u8, value: ExprIdx) LoxError!void {
        return self.fields.put(name, value);
    }

    pub fn findMethod(self: Instance, name: []const u8) LoxError!RuntimeValue {
        return self.class.findMethod(name) orelse LoxError.MethodNotDefined;
    }

    pub fn format(self: Instance, w: *std.Io.Writer) !void {
        try w.print("{s} instance", .{self.class.name});
    }
};

const ClassData = struct {
    name: []const u8,
    methods: std.StringHashMap(RuntimeValue),

    pub fn findMethod(self: ClassData, name: []const u8) ?RuntimeValue {
        return self.methods.get(name);
    }
};

pub const Callable = union(enum) {
    Class: ClassData,
    Function: struct {
        name: []const u8,
        params: []const Token,
        body: Stmt,
        closure: *Environment,
    },
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
            .Class => |c| return .{
                .Instance = .{
                    .class = .{
                        .name = c.name,
                        .methods = c.methods,
                    },
                    .fields = std.StringHashMap(ExprIdx).init(interpreter.allocator),
                },
            },
            .Function => |func| return self.callFunction(
                func,
                interpreter,
                arguments,
                src,
            ),
            .NativeFunction => |native| {
                const impl = NATIVE_FUNCTIONS.get(native.name) orelse return .Nil;
                return impl.callFn(interpreter, arguments);
            },
        }
    }

    pub fn arity(self: Callable) usize {
        switch (self) {
            .Class => return 0,
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
        local_env.* = .createLocalEnv(func.closure); // Use the captured closure
        const parent_env = interpreter.environment;
        interpreter.environment = local_env;
        defer interpreter.environment = parent_env;
        for (func.params, arguments) |param, arg| {
            try local_env.define(param.lexeme(src), arg);
        }

        interpreter.execute(func.body) catch |err| switch (err) {
            LoxError.Return => {
                const return_val = interpreter.return_value orelse .Nil;
                interpreter.return_value = null;
                return return_val;
            },
            else => return err,
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
