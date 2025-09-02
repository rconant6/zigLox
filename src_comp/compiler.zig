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

    const constant = chunk.addConstant(1.2);
    chunk.writeChunk(@intFromEnum(OpCode.Constant), 123);
    chunk.writeChunk(constant, 123);
    chunk.writeChunk(@intFromEnum(OpCode.Return), 123);
    chunk.disassembleChunk("test chunk");

    const res = vm.interpret(&chunk);
    std.debug.print("{}\n", .{res});

    return 0;
}
