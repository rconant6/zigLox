const std = @import("std");

pub fn main() !u8 {
    const gpa = std.heap.smp_allocator;

    var chunks = Chunk.init();
    defer chunks.deinit(gpa);

    writeChunk(gpa, &chunks, .Return);

    chunks.disassembleChunk("test chunk");

    return 0;
}

fn writeChunk(alloc: std.mem.Allocator, chunk: *Chunk, opCode: OpCode) void {
    chunk.code.append(alloc, opCode) catch {
        @panic("Falied to write a chunk");
    };
}

const OpCode = enum(u8) {
    Return,
};

const Chunk = struct {
    code: std.ArrayList(OpCode),

    pub fn disassembleChunk(self: *Chunk, name: []const u8) void {
        std.debug.print("== {s} ==\n", .{name});

        for (0..self.code.items.len) |i| {
            _ = self.disassembleInstruction(i);
        }
    }

    pub fn disassembleInstruction(self: *const Chunk, offset: usize) usize {
        std.debug.print("{d:0>4} ", .{offset});
        const instruction = self.code.items[offset];

        switch (instruction) {
            .Return => return simpleInstruction(instruction, offset),
        }
    }

    fn simpleInstruction(op: OpCode, offset: usize) usize {
        std.debug.print("{t}\n", .{op});
        return offset + 1;
    }

    pub fn init() Chunk {
        return .{
            .code = .empty,
        };
    }
    pub fn deinit(self: *Chunk, alloc: std.mem.Allocator) void {
        self.code.deinit(alloc);
    }
};
