pub const VirtualMachine = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const Compiler = lox.Compiler;
const DiagnosticReporter = lox.DiagnosticReporter;
const InterpretResult = lox.InterpretResult;
const OpCode = lox.OpCode;
const Value = lox.Value;

const Tracer = lox.trace_utils;
const trace = Tracer.trace;

gpa: std.mem.Allocator,
stack: std.ArrayList(Value),
diagnostics: DiagnosticReporter,

pub fn interpret(self: *VirtualMachine, src: []const u8) InterpretResult {
    var ip: usize = 0;
    var chunk: Chunk = .init(self.gpa);
    defer chunk.deinit();

    var compiler: Compiler = .init(self.gpa, src[0..], &self.diagnostics);
    _ = compiler.compile(&chunk);
    if (self.diagnostics.hasErrors()) {
        std.log.debug("Compiler returned and error", .{});
        for (self.diagnostics.errors.items) |item| {
            std.log.debug("{f}", .{item});
        }
        return .Compile_Error;
    }

    chunk.disassembleChunk("Interpret");

    vm: switch (readOp(chunk.code.items, &ip)) {
        // TODO: Lets look at a better way to wrap this?
        // I'm think we add states to the vm and start is what we have now
        // then we can set the value jump to opCall or what ever and then if its Ok
        // do the continue :start readOp(chunk.code.items, &ip)?
        // but this is a later thing when we add more than just calcualtor functions
        .Add => {
            trace("Binary OP: {s}\n", .{"+"});
            const res = self.binaryOp(Value, isNumber, add);
            // TODO: String needs to be handled here too
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Subtract => {
            trace("Binary OP: {s}\n", .{"-"});
            const res = self.binaryOp(Value, isNumber, sub);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Multiply => {
            trace("Binary OP: {s}\n", .{"*"});
            const res = self.binaryOp(Value, isNumber, mul);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Divide => {
            trace("Binary OP: {s}\n", .{"/"});
            const res = self.binaryOp(Value, isNumber, div);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Constant => {
            const constant = readConstant(chunk.code.items, &ip, &chunk);
            trace("Constant OP: {any}\n", .{constant});
            self.push(constant);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Negate => {
            trace("Negate OP:\n", .{});
            const val = self.pop();
            if (!isNumber(val))
                return .Runtime_Error;
            self.push(.{ .number = -val.number });
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Not => {
            trace("Not OP:\n", .{});
            const val = self.pop();
            if (!isBool(val))
                return .Runtime_Error;
            self.push(.{ .bool = !val.bool });
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Return => {
            trace("RETURN .Ok\n", .{});
            return .Ok;
        },
        .True => {
            trace("True:\n", .{});
            self.push(.{ .bool = true });
            continue :vm readOp(chunk.code.items, &ip);
        },
        .False => {
            trace("False:\n", .{});
            self.push(.{ .bool = false });
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Nil => {
            trace("Nil:\n", .{});
            self.push(.{ .nil = {} });
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Equal => {
            trace("Equal OP:\n", .{});
            const b = self.pop();
            const a = self.pop();

            const equal = if (checkTypesMatch(a, b))
                switch (a) {
                    .number => a.number == b.number,
                    .bool => a.bool == b.bool,
                    .nil => true,
                    .string => std.mem.eql(u8, a.string, b.string),
                }
            else
                false;

            self.push(.{ .bool = equal });
            continue :vm readOp(chunk.code.items, &ip);
        },
        .NotEqual => {
            trace("NotEqual OP:\n", .{});
            const b = self.pop();
            const a = self.pop();
            const equal = if (checkTypesMatch(a, b))
                switch (a) {
                    .number => a.number != b.number,
                    .bool => a.bool != b.bool,
                    .nil => false,
                    .string => !std.mem.eql(u8, a.string, b.string),
                }
            else
                true;

            self.push(.{ .bool = equal });
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Greater => {
            trace("Greater OP:\n", .{});
            const res = self.binaryOp(Value, isNumber, greaterThan);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .GreaterEqual => {
            trace("GreaterEqual OP:\n", .{});

            const res = self.binaryOp(Value, isNumber, greaterThanEqual);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Less => {
            trace("Less OP:\n", .{});
            const res = self.binaryOp(Value, isNumber, lessThan);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .LessEqual => {
            trace("LessEqual OP:\n", .{});
            const res = self.binaryOp(Value, isNumber, lessThanEqual);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .And => {
            trace("And OP:\n", .{});
            const res = self.binaryOp(Value, isBool, logicalAnd);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Or => {
            trace("Or OP:\n", .{});
            const res = self.binaryOp(Value, isBool, logicalOr);
            if (res != .Ok) return res;
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Jump => {
            trace("Jump OP:\n", .{});
            @panic("TODO: this isn't implemented yet");
            // This needs to jump N bytes if falsey else continue
        },
        .JumpIfFalse => {
            trace("Jump False OP:\n", .{});
            @panic("TODO: this isn't implemented yet");
            // This needs to do the jump to the write offset
        },
    }
    return .Ok;
}
// MARK: Execution Helpers
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
fn binaryOp(
    self: *VirtualMachine,
    comptime ResultType: type,
    comptime typeCheck: fn (Value) bool,
    comptime op: fn (Value, Value) ResultType,
) InterpretResult {
    const b = self.pop();
    const a = self.pop();

    if (!typeCheck(a) or !typeCheck(b)) {
        // TODO: use diagnostics
        std.log.err("Runtime Error: Type mismatch for binary operation", .{});
        return .Runtime_Error;
    }

    self.push(op(a, b));

    return .Ok;
}
fn add(a: Value, b: Value) Value {
    return .{ .number = a.number + b.number };
}
fn sub(a: Value, b: Value) Value {
    return .{ .number = a.number - b.number };
}
fn mul(a: Value, b: Value) Value {
    return .{ .number = a.number * b.number };
}
fn div(a: Value, b: Value) Value {
    return .{ .number = a.number / b.number };
}
fn greaterThan(a: Value, b: Value) Value {
    return if (a.number > b.number) .{ .bool = true } else .{ .bool = false };
}
fn greaterThanEqual(a: Value, b: Value) Value {
    return if (a.number >= b.number) .{ .bool = true } else .{ .bool = false };
}
fn lessThan(a: Value, b: Value) Value {
    return if (a.number < b.number) .{ .bool = true } else .{ .bool = false };
}
fn lessThanEqual(a: Value, b: Value) Value {
    return if (a.number <= b.number) .{ .bool = true } else .{ .bool = false };
}
fn logicalAnd(a: Value, b: Value) Value {
    return .{ .bool = a.bool and b.bool };
}
fn logicalOr(a: Value, b: Value) Value {
    return .{ .bool = a.bool or b.bool };
}
// MARK: Memory management
pub fn init(alloc: std.mem.Allocator) VirtualMachine {
    return .{
        .gpa = alloc,
        .stack = .empty,
        .diagnostics = .init(alloc),
    };
}
pub fn deinit(vm: *VirtualMachine) void {
    vm.stack.deinit(vm.gpa);
    vm.diagnostics.deinit();
    return;
}

// MARK: Stack management
fn push(vm: *VirtualMachine, val: Value) void {
    Tracer.traceStack("VM.Push: {f}\n", .{val});
    vm.stack.append(vm.gpa, val) catch |err| {
        std.log.err("Unable to VM.push: {any}\n", .{err});
        unreachable;
    };
}
fn pop(vm: *VirtualMachine) Value {
    Tracer.traceStack("VM.Pop \n", .{});
    return if (vm.stack.pop()) |v| v else {
        std.log.err("VM.pop on an empty stack\n", .{});
        unreachable;
    };
}

// MARK: Runtime Type Checking
fn isTruthy(val: Value) bool {
    return switch (val) {
        .bool => |b| b,
        .nil => false,
        else => true, // numbers, strings, objects are truthy
    };
}
fn isNumber(val: Value) bool {
    return std.meta.activeTag(val) == .number;
}

fn isBool(val: Value) bool {
    return std.meta.activeTag(val) == .bool;
}
fn checkTypesMatch(a: Value, b: Value) bool {
    return std.meta.activeTag(a) == std.meta.activeTag(b);
}
