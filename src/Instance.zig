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

pub fn get(self: Instance, name: []const u8) LoxError!?RuntimeValue {
    if (self.fields.get(name)) |field| return field;

    return null;
}

pub fn getMethod(self: *Instance, name: []const u8) LoxError!?RuntimeValue {
    if (self.class.methods.get(name)) |method| {
        const bound_method = try method.bind(self);
        return bound_method;
    }
    return null;
}

pub fn set(self: *Instance, name: []const u8, value: RuntimeValue) LoxError!void {
    return self.fields.put(name, value);
}

pub fn format(self: Instance, w: *std.Io.Writer) !void {
    try w.print("{s} instance", .{self.class.name});
}
