pub const Chunk = @import("Chunk.zig");
pub const VirtualMachine = @import("VirtualMachine.zig");

pub const Value = f64;

pub const InterpretResult = enum {
    Ok,
    Compile_Error,
    Runtime_Error,
};

pub const OpCode = enum(u8) {
    Add,
    Constant,
    Divide,
    Multiply,
    Negate,
    Return,
    Subtract,

    pub const SIMPLE_LEN = 1;
    pub const CONSTANT_LEN = 2;
};

pub const trace_utils = @import("trace.zig");
pub const trace = trace_utils.trace;
