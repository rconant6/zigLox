const std = @import("std");
const stdin = lox.in_reader;
const lox = @import("lox.zig");
const InterpretResult = lox.InterpretResult;
const OpCode = lox.OpCode;
const Value = lox.Value;
const VirtualMachine = lox.VirtualMachine;

pub fn main() !u8 {
    const gpa = std.heap.smp_allocator;
    var vm: VirtualMachine = .init(gpa);
    defer vm.deinit();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    switch (args.len) {
        1 => {
            try repl(gpa, &vm);
            return 0;
        },
        2 => {
            const result = try runFile(gpa, &vm, args[1]);
            return switch (result) {
                .Ok => 0,
                .Compile_Error => 65,
                .Runtime_Error => 70,
            };
        },
        else => {
            std.debug.print("Usage: zlox [script]\n", .{});
            return 64;
        },
    }
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);

    return buffer;
}

fn runFile(allocator: std.mem.Allocator, vm: *VirtualMachine, path: []const u8) !InterpretResult {
    const source = try readFile(allocator, path);
    defer allocator.free(source);

    return try vm.interpret(source);
}

fn repl(allocator: std.mem.Allocator, vm: *VirtualMachine) !void {
    var lines: std.ArrayList(u8) = .empty;
    defer lines.deinit(allocator);

    while (true) {
        std.debug.print("> ", .{});

        const bytes = try stdin.takeDelimiterExclusive('\n');
        try lines.appendSlice(allocator, bytes);

        if (lines.items.len == 0) {
            std.debug.print("\n", .{});
            break;
        }

        if (needsMoreInput(lines.items)) {
            continue;
        }

        _ = try vm.interpret(lines.items);
        lines.clearRetainingCapacity();
    }
}

fn needsMoreInput(line: []const u8) bool {
    if (line.len > 0 and line[line.len - 1] == '\\') {
        return true;
    }

    var brace_count: i32 = 0;
    for (line) |c| {
        switch (c) {
            '{' => brace_count += 1,
            '}' => brace_count -= 1,
            else => {},
        }
    }

    return brace_count > 0;
}
