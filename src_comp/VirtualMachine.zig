pub const VirtualMachine = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const Compiler = lox.Compiler;
const InterpretResult = lox.InterpretResult;
const OpCode = lox.OpCode;
const Value = lox.Value;

const Tracer = lox.trace_utils;
const trace = Tracer.trace;

gpa: std.mem.Allocator,
stack: std.ArrayList(Value),

pub fn interpret(self: *VirtualMachine, src: []const u8) InterpretResult {
    // var ip: usize = 0;
    var chunk: Chunk = .init(self.gpa);
    defer chunk.deinit();

    var compiler: Compiler = .init(src[0..]);
    const compiler_result = compiler.compile(&chunk);
    return compiler_result;

    // var instruction = readOp(chunk.code.items, &ip);

    // vm: switch (instruction) {
    //     .Add => {
    //         trace("Binary OP: {s}\n", .{"+"});
    //         self.binaryOp(struct {
    //             fn add(a: f64, b: f64) f64 {
    //                 return a + b;
    //             }
    //         }.add);

    //         instruction = readOp(chunk.code.items, &ip);
    //         continue :vm instruction;
    //     },
    //     .Subtract => {
    //         trace("Binary OP: {s}\n", .{"-"});
    //         self.binaryOp(struct {
    //             fn sub(a: f64, b: f64) f64 {
    //                 return a - b;
    //             }
    //         }.sub);
    //         continue :vm readOp(chunk.code.items, &ip);
    //     },
    //     .Multiply => {
    //         trace("Binary OP: {s}\n", .{"*"});
    //         self.binaryOp(struct {
    //             fn mul(a: f64, b: f64) f64 {
    //                 return a * b;
    //             }
    //         }.mul);
    //         continue :vm readOp(chunk.code.items, &ip);
    //     },
    //     .Divide => {
    //         trace("Binary OP: {s}\n", .{"/"});
    //         self.binaryOp(struct {
    //             fn div(a: f64, b: f64) f64 {
    //                 return a / b;
    //             }
    //         }.div);
    //         continue :vm readOp(chunk.code.items, &ip);
    //     },
    //     .Constant => {
    //         const constant = readConstant(chunk.code.items, &ip, chunk);
    //         trace("Constant OP: {d}\n", .{constant});
    //         self.push(constant);
    //         continue :vm readOp(chunk.code.items, &ip);
    //     },
    //     .Negate => {
    //         self.push(-self.pop());
    //         continue :vm readOp(chunk.code.items, &ip);
    //     },
    //     .Return => {
    //         std.debug.print("{d}\n", .{self.pop()});
    //         return .Ok;
    //     },
    // }
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
fn binaryOp(self: *VirtualMachine, comptime op: fn (f64, f64) f64) void {
    const b = self.pop();
    const a = self.pop();
    self.push(op(a, b));
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
