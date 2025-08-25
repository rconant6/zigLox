pub const Environment = @This();

const std = @import("std");
const lox = @import("lox.zig");
const LoxError = lox.LoxError;
const RuntimeValue = lox.RuntimeValue;

parent: ?*Environment = null,
env: std.StringHashMap(RuntimeValue),
gpa: std.mem.Allocator,

pub fn createGlobalEnv(allocator: std.mem.Allocator) Environment {
    return .{
        .gpa = allocator,
        .env = std.StringHashMap(RuntimeValue).init(allocator),
    };
}

pub fn createLocalEnv(parent: *Environment) Environment {
    return .{
        .parent = parent,
        .env = std.StringHashMap(RuntimeValue).init(parent.gpa),
        .gpa = parent.gpa,
    };
}

pub fn define(self: *Environment, name: []const u8, val: RuntimeValue) !void {
    const name_cpy = try self.gpa.dupe(u8, name);
    try self.env.put(name_cpy, val);
}

pub fn get(self: *Environment, name: []const u8) !RuntimeValue {
    if (self.env.get(name)) |val| {
        return val;
    }

    if (self.parent) |parent| return parent.get(name);

    return LoxError.UndefinedVariable;
}

pub fn assign(self: *Environment, name: []const u8, val: RuntimeValue) !void {
    if (self.env.contains(name)) {
        return try self.env.put(name, val);
    }

    if (self.parent) |parent| return parent.assign(name, val);

    return LoxError.UndefinedVariable;
}

pub fn debugPrintAll(self: *Environment) void {
    std.debug.print("DEBUG: Environment contents ({} items):\n", .{self.env.count()});
    var iterator = self.env.iterator();
    while (iterator.next()) |entry| {
        std.debug.print("  key='{s}' value={any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
