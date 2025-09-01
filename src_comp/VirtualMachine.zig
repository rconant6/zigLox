pub const VirtualMachine = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const InterpretResult = lox.InterpretResult;
const OpCode = lox.OpCode;
const Value = lox.Value;

const tracer = lox.trace_utils;
const trace = tracer.trace;

pub fn interpret(self: *VirtualMachine, chunk: *Chunk) InterpretResult {
    _ = self;
    var ip: usize = 0;

    vm: switch (readOp(chunk.code.items, &ip)) {
        .Constant => {
            const constant = readConstant(chunk.code.items, &ip, chunk);
            trace("Constant OP: {d}\n", .{constant});
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Return => return .Ok,
    }
}
inline fn readConstant(bytecode: []u8, ip: *usize, chunk: *const Chunk) Value {
    const val_idx = bytecode[ip.*];
    ip.* += 1;
    return chunk.constants.items[val_idx];
}
inline fn readOp(bytecode: []u8, ip: *usize) OpCode {
    const result: OpCode = @enumFromInt(bytecode[ip.*]);
    ip.* += 1;
    return result;
}

pub fn init() VirtualMachine {
    return .{};
}

pub fn deinit(vm: *VirtualMachine) void {
    _ = vm;
    return;
}
