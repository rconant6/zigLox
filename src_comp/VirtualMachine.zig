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
        .Add => {
            trace("Binary OP: {s}\n", .{"+"});
            self.binaryOp(struct {
                fn add(a: f64, b: f64) f64 {
                    return a + b;
                }
            }.add);
            // TODO: String needs to be handled here

            continue :vm readOp(chunk.code.items, &ip);
        },
        .Subtract => {
            trace("Binary OP: {s}\n", .{"-"});
            self.binaryOp(struct {
                fn sub(a: f64, b: f64) f64 {
                    return a - b;
                }
            }.sub);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Multiply => {
            trace("Binary OP: {s}\n", .{"*"});
            self.binaryOp(struct {
                fn mul(a: f64, b: f64) f64 {
                    return a * b;
                }
            }.mul);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Divide => {
            trace("Binary OP: {s}\n", .{"/"});
            self.binaryOp(struct {
                fn div(a: f64, b: f64) f64 {
                    return a / b;
                }
            }.div);
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
            self.push(-self.pop());
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Not => {
            trace("Not OP:\n", .{});
            const val = self.pop();
            const rep_val: f64 = if (val == 0.0 or std.math.isNan(val)) 1.0 else 0.0;
            self.push(rep_val);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Return => {
            trace("RETURN .Ok\n", .{});
            return .Ok;
        },
        .True => {
            trace("True:\n", .{});
            self.push(@intFromBool(true));
            continue :vm readOp(chunk.code.items, &ip);
        },
        .False => {
            trace("False:\n", .{});
            self.push(@intFromBool(false));
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Nil => {
            trace("Nil:\n", .{});
            self.push(std.math.nan(f64));
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Equal => {
            trace("Equal OP:\n", .{});
            const b = self.pop();
            const a = self.pop();
            self.push(if (a == b) 1.0 else 0.0);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .NotEqual => {
            trace("NotEqual OP:\n", .{});
            const b = self.pop();
            const a = self.pop();
            self.push(if (a != b) 1.0 else 0.0);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Greater => {
            trace("Greater OP:\n", .{});
            self.binaryOp(struct {
                fn gt(a: f64, b: f64) f64 {
                    return if (a > b) 1.0 else 0.0;
                }
            }.gt);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .GreaterEqual => {
            trace("GreaterEqual OP:\n", .{});
            self.binaryOp(struct {
                fn ge(a: f64, b: f64) f64 {
                    return if (a >= b) 1.0 else 0.0;
                }
            }.ge);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .Less => {
            trace("Less OP:\n", .{});
            self.binaryOp(struct {
                fn lt(a: f64, b: f64) f64 {
                    return if (a < b) 1.0 else 0.0;
                }
            }.lt);
            continue :vm readOp(chunk.code.items, &ip);
        },
        .LessEqual => {
            trace("LessEqual OP:\n", .{});
            self.binaryOp(struct {
                fn le(a: f64, b: f64) f64 {
                    return if (a <= b) 1.0 else 0.0;
                }
            }.le);
            continue :vm readOp(chunk.code.items, &ip);
        },
    }
    return .Ok;
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
fn binaryOp(self: *VirtualMachine, comptime op: fn (Value, Value) f64) void {
    const b = self.pop();
    const a = self.pop();
    self.push(op(a, b));
}

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

fn push(vm: *VirtualMachine, val: f64) void {
    Tracer.traceStack("VM.Push: {d}\n", .{val});
    vm.stack.append(vm.gpa, val) catch |err| {
        std.log.err("Unable to VM.push: {any}\n", .{err});
        unreachable;
    };
}
fn pop(vm: *VirtualMachine) f64 {
    Tracer.traceStack("VM.Pop \n", .{});
    return if (vm.stack.pop()) |v| v else {
        std.log.err("VM.pop on an empty stack\n", .{});
        unreachable;
    };
}
