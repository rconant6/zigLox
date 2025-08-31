pub const Instance = @This();

const std = @import("std");
const lox = @import("lox.zig");
const ClassData = lox.ClassData;
const Environment = lox.Environment;
const ExprIdx = lox.ExprIdx;
const LoxError = lox.LoxError;
const RuntimeValue = lox.RuntimeValue;

class: ClassData,
fields: std.StringHashMap(RuntimeValue),

pub fn get(self: *const Instance, name: []const u8) LoxError!?RuntimeValue {
    std.log.debug("Instance.get: looking for '{s}', fields has {d} items", .{ name, self.fields.count() });
    if (self.fields.get(name)) |field| return field;

    return null;
}

pub fn getMethod(self: *Instance, name: []const u8) LoxError!?RuntimeValue {
    if (self.class.methods.get(name)) |method| {
        const bound_method = try method.bind(self);
        return bound_method;
    }

    if (self.class.getMethod(name)) |method| {
        switch (method) {
            .Callable => |callable| switch (callable) {
                .Function => |func| {
                    return try func.bind(self);
                },
                else => return null,
            },
            else => return null,
        }
    }

    return null;
}

pub fn set(self: *Instance, name: []const u8, value: RuntimeValue) LoxError!void {
    std.log.debug("Instance.set: storing '{s}' in fields", .{name});
    try self.fields.put(name, value);
}

pub fn format(self: Instance, w: *std.Io.Writer) !void {
    try w.print("{s} instance", .{self.class.name});
}
