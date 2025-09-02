pub const VirtualMachine = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const InterpretResult = lox.InterpretResult;
const OpCode = lox.OpCode;
const Value = lox.Value;

const Tracer = lox.trace_utils;
const trace = Tracer.trace;

gpa: std.mem.Allocator,
stack: std.ArrayList(Value),

pub fn interpret(self: *VirtualMachine, chunk: *Chunk) InterpretResult {
    var ip: usize = 0;

    vm: switch (readOp(chunk.code.items, &ip)) {
        .Constant => {
            const constant = readConstant(chunk.code.items, &ip, chunk);
            trace("Constant OP: {d}\n", .{constant});
            self.push(constant);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Return => {
            std.debug.print("RETURN: {d}\n", .{self.pop()});
            return .Ok;
        },
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

pub fn init(alloc: std.mem.Allocator) VirtualMachine {
    return .{
        .gpa = alloc,
        .stack = .empty,
    };
}

pub fn deinit(vm: *VirtualMachine) void {
    vm.stack.deinit(vm.gpa);
    return;
}

fn push(vm: *VirtualMachine, val: Value) void {
    Tracer.traceStack("VM.Push: {d}\n", .{val});
    vm.stack.append(vm.gpa, val) catch |err| {
        std.log.err("Unable to VM.push: {any}", .{err});
    };
}
fn pop(vm: *VirtualMachine) Value {
    Tracer.traceStack("VM.Pop \n", .{});
    return if (vm.stack.pop()) |v| v else {
        std.log.err("VM.pop on an empty stack", .{});
        unreachable;
    };
}
