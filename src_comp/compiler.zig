const std = @import("std");

const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const OpCode = lox.OpCode;
const Value = lox.Value;
const VirtualMachine = lox.VirtualMachine;

pub fn main() !u8 {
    const gpa = std.heap.smp_allocator;
    var vm: VirtualMachine = .init(gpa);
    defer vm.deinit();

    // Just a hand rolled thing tester for now
    var chunk = Chunk.init(gpa);
    defer chunk.deinit();

    var constant = chunk.addConstant(1.2);
    chunk.writeChunk(@intFromEnum(OpCode.Constant), 123);
    chunk.writeChunk(constant, 123);

    constant = chunk.addConstant(3.4);
    chunk.writeChunk(@intFromEnum(OpCode.Constant), 123);
    chunk.writeChunk(constant, 123);

    chunk.writeChunk(@intFromEnum(OpCode.Add), 123);

    constant = chunk.addConstant(5.6);
    chunk.writeChunk(@intFromEnum(OpCode.Constant), 123);
    chunk.writeChunk(constant, 123);

    chunk.writeChunk(@intFromEnum(OpCode.Divide), 123);
    chunk.writeChunk(@intFromEnum(OpCode.Negate), 123);
    chunk.writeChunk(@intFromEnum(OpCode.Return), 123);
    chunk.disassembleChunk("test chunk");

    const res = vm.interpret(&chunk);
    if (res != .Ok) {
        std.log.err("There was an error in compiling", .{});
        return 1;
    }
    return 0;
}
