pub const Chunk = @This();

const std = @import("std");
const lox = @import("lox.zig");
const OpCode = lox.OpCode;
const Value = lox.Value;

gpa: std.mem.Allocator,
code: std.ArrayList(u8),
lines: std.ArrayList(u8), // this is dumb.....(interval stuff)
constants: std.ArrayList(Value),

pub fn writeChunk(self: *Chunk, byte: u8, line: u8) void {
    self.code.append(self.gpa, byte) catch |err| {
        std.log.err("Unable to Chunk.writeChunk(code): {any}", .{err});
    };
    self.lines.append(self.gpa, line) catch |err| {
        std.log.err("Unable to Chunk.writeChunk(line): {any}", .{err});
    };
}
pub fn addConstant(self: *Chunk, value: Value) u8 {
    self.constants.append(self.gpa, value) catch |err| {
        std.log.err("Unable to Chunk.addConstant: {any}", .{err});
    };

    return @intCast(self.constants.items.len - 1);
}

pub fn disassembleChunk(self: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var idx: usize = 0;
    while (idx < self.code.items.len) {
        idx = self.disassembleInstruction(idx);
    }
}
fn disassembleInstruction(self: *const Chunk, offset: usize) usize {
    std.debug.print("{d:0>4} ", .{offset}); // just the instruction code at this point?
    const instruction: OpCode = @enumFromInt(self.code.items[offset]);

    if (offset > 0 and self.lines.items[offset] == self.lines.items[offset - 1])
        std.debug.print("  | ", .{})
    else
        std.debug.print("{d:4>} ", .{self.lines.items[offset]});
    return switch (instruction) {
        .Constant => self.constantInstruction(instruction, offset),
        .Negate => self.simpleInstruction(instruction, offset),
        .Return => self.simpleInstruction(instruction, offset),
        .Add, .Divide, .Multiply, .Subtract => self.simpleInstruction(instruction, offset),
        .True => self.simpleInstruction(instruction, offset),
        .False => self.simpleInstruction(instruction, offset),
        .Nil => self.simpleInstruction(instruction, offset),
    };
}
fn constantInstruction(self: *const Chunk, op: OpCode, offset: usize) usize {
    std.debug.assert(offset + 1 < self.code.items.len);

    const constant_idx = self.code.items[offset + 1];

    std.debug.print(
        "{t:<16} {d:4} '{d}'\n",
        .{ op, constant_idx, self.constants.items[constant_idx] },
    );
    return offset + OpCode.CONSTANT_LEN;
}
fn simpleInstruction(self: *const Chunk, op: OpCode, offset: usize) usize {
    _ = self;
    std.debug.print("{t:<16}\n", .{op});
    return offset + OpCode.SIMPLE_LEN;
}

pub fn init(alloc: std.mem.Allocator) Chunk {
    return .{
        .gpa = alloc,
        .code = .empty,
        .lines = .empty,
        .constants = .empty,
    };
}
pub fn deinit(self: *Chunk) void {
    self.code.deinit(self.gpa);
    self.constants.deinit(self.gpa);
    self.lines.deinit(self.gpa);
}
