const std = @import("std");

const Value = f64;
const simple_len = 1;
const constant_len = 2;

pub fn main() !u8 {
    const gpa = std.heap.smp_allocator;

    var chunk = Chunk.init(gpa);
    defer chunk.deinit();

    const constant = addConstant(&chunk, 1.2);
    writeChunk(&chunk, @intFromEnum(OpCode.Constant), 123);
    writeChunk(&chunk, constant, 123);
    writeChunk(&chunk, @intFromEnum(OpCode.Return), 123);

    chunk.disassembleChunk("test chunk");

    return 0;
}

fn writeChunk(chunk: *Chunk, byte: u8, line: u8) void {
    chunk.code.append(chunk.gpa, byte) catch |err| {
        std.log.err("Unable to Chunk.writeChunk(code): {any}", .{err});
    };
    chunk.lines.append(chunk.gpa, line) catch |err| {
        std.log.err("Unable to Chunk.writeChunk(line): {any}", .{err});
    };
}
fn addConstant(chunk: *Chunk, value: Value) u8 {
    chunk.constants.append(chunk.gpa, value) catch |err| {
        std.log.err("Unable to Chunk.addConstant: {any}", .{err});
    };

    return @intCast(chunk.constants.items.len - 1);
}

const OpCode = enum(u8) {
    Constant,
    Return,
};

const Chunk = struct {
    gpa: std.mem.Allocator,
    code: std.ArrayList(u8),
    lines: std.ArrayList(u8), // this is dumb.....(interval stuff)
    constants: std.ArrayList(Value),

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
            .Constant => |c| self.constantInstruction(c, offset),
            .Return => |r| self.simpleInstruction(r, offset),
        };
    }
    fn constantInstruction(self: *const Chunk, op: OpCode, offset: usize) usize {
        std.debug.assert(offset + 1 < self.code.items.len);

        const constant_idx = self.code.items[offset + 1];

        std.debug.print(
            "{t:<16} {d:4} '{d}'\n",
            .{ op, constant_idx, self.constants.items[constant_idx] },
        );
        return offset + constant_len;
    }
    fn simpleInstruction(self: *const Chunk, op: OpCode, offset: usize) usize {
        _ = self;
        std.debug.print("{t:<16}\n", .{op});
        return offset + simple_len;
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
};
