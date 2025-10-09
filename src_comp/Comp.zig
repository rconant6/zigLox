pub const Compiler = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const DiagnosticReporter = lox.DiagnosticReporter;
const InterpretResult = lox.InterpretResult;
const LoxError = lox.LoxError;
const OpCode = lox.OpCode;
const Scanner = lox.Scanner;
const Token = lox.Token;
const Value = lox.Value;

const Tracer = lox.trace_utils;
const trace = Tracer.trace;

scanner: Scanner,
parser: Parser,
diagnostics: *DiagnosticReporter,
src: []const u8,
gpa: std.mem.Allocator,

const Parser = struct {
    current: Token,
    previous: Token,
    had_error: bool,
    panic_mode: bool,
};

const ParseState = enum {
    start,
    primary,
    unary,
    unimplemented,
    done,
};

const ParsingState = enum {
    expecting_value,
    got_value,
};

const OpPrecedence = enum(u8) {
    assignment,
    logic_or,
    logic_and,
    equality,
    comparision,
    term,
    factor,
    unary,
    group_start,

    inline fn binds_tighter(a: OpPrecedence, b: OpPrecedence) bool {
        return if (@intFromEnum(a) > @intFromEnum(b)) true else false;
    }
    inline fn nextLowerPrecedence(prec: OpPrecedence) OpPrecedence {
        const val: OpPrecedence = @enumFromInt(@intFromEnum(prec) + 1);
        std.log.debug("{t}", .{val});
        return val;
    }
};
const OpStorage = struct {
    precedence: OpPrecedence,
    code: OpCode,
};

fn getBinaryOp(token_tag: Token.Tag) ?OpStorage {
    return switch (token_tag) {
        .And => .{ .precedence = .logic_and, .code = .And },
        .BangEqual => .{ .precedence = .equality, .code = .NotEqual },
        .EqualEqual => .{ .precedence = .equality, .code = .Equal },
        .Greater => .{ .precedence = .comparision, .code = .Greater },
        .GreaterEqual => .{ .precedence = .comparision, .code = .GreaterEqual },
        .Less => .{ .precedence = .comparision, .code = .Less },
        .LessEqual => .{ .precedence = .comparision, .code = .LessEqual },
        .Minus => .{ .precedence = .term, .code = .Subtract },
        .Or => .{ .precedence = .logic_or, .code = .Or },
        .Plus => .{ .precedence = .term, .code = .Add },
        .Slash => .{ .precedence = .factor, .code = .Divide },
        .Star => .{ .precedence = .factor, .code = .Multiply },
        else => null,
    };
}
fn consumeGroup(
    self: *Compiler,
    stack: *std.ArrayList(OpStorage),
    chunk: *Chunk,
) void {
    Tracer.traceCompile("[PARSER] consuming stack grouping\n", .{});
    while (stack.items.len > 0) {
        const op = stack.pop() orelse break;
        if (op.precedence == .group_start) {
            break;
        }
        self.emitByte(chunk, @intFromEnum(op.code));
    }
}

fn consumeUnary(
    self: *Compiler,
    stack: *std.ArrayList(OpStorage),
    chunk: *Chunk,
) void {
    Tracer.traceCompile("[PARSER] consuming unary\n", .{});
    while (stack.items.len > 0) {
        const top = stack.items[stack.items.len - 1];
        if (top.precedence == .unary) {
            const op = stack.pop() orelse break;
            self.emitByte(chunk, @intFromEnum(op.code));
        } else {
            break;
        }
    }
}

fn consumeBinary(
    self: *Compiler,
    stack: *std.ArrayList(OpStorage),
    precedence: OpPrecedence,
    chunk: *Chunk,
) void {
    Tracer.traceCompile("[PARSER] consuming stack with precedence {t}\n", .{precedence});
    while (stack.items.len > 0) {
        const top = stack.items[stack.items.len - 1];

        // Stop if we hit a group marker - can't pop past it
        if (top.precedence == .group_start) {
            break;
        }

        if (top.precedence.binds_tighter(precedence) or
            (@intFromEnum(top.precedence) == @intFromEnum(precedence) and
                top.precedence != .group_start))
        {
            const op = stack.pop() orelse break;
            self.emitByte(chunk, @intFromEnum(op.code));
        } else {
            break;
        }
    }
}

fn consumeAllOperators(
    self: *Compiler,
    stack: *std.ArrayList(OpStorage),
    chunk: *Chunk,
) void {
    Tracer.traceCompile(
        "[PARSER] consuming all remaining operators with len: {d}\n",
        .{stack.items.len},
    );
    while (stack.items.len > 0) {
        const op = stack.pop() orelse break;
        if (op.precedence != .group_start) {
            self.emitByte(chunk, @intFromEnum(op.code));
        }
    }
}
// parser.previous is your current token to be processed
// parser.current is what you used to decide on the next state to move to
// advance is called to then move current into previous
// and set up the decision tree again once the new token is set
pub fn compile(self: *Compiler, chunk: *Chunk) InterpretResult {
    self.parser.current = self.scanner.getToken();
    self.advance();

    var op_stack: std.ArrayList(OpStorage) = .empty;
    defer op_stack.deinit(self.gpa);

    var parse_state: ParsingState = .expecting_value;

    var open_paren_cnt: u16 = 0; // max of 65k+

    parse: switch (ParseState.start) {
        .start => {
            Tracer.traceCompile("[PARSER] .start {t} (state: {t})\n", .{ self.parser.previous.tag, parse_state });

            switch (parse_state) {
                .expecting_value => {
                    // We need a value - handle value tokens
                    switch (self.parser.previous.tag) {
                        .Number, .True, .False, .Nil => continue :parse .primary,
                        .Bang => continue :parse .unary,
                        .Minus => continue :parse .unary,
                        .LeftParen => {
                            open_paren_cnt += 1;
                            op_stack.append(self.gpa, .{
                                .precedence = .group_start,
                                .code = .Nil,
                            }) catch unreachable;

                            self.advance();
                            continue :parse .start;
                        },
                        .Eof => continue :parse .done,
                        else => continue :parse .unimplemented,
                    }
                },
                .got_value => {
                    // We have a value, look for operators
                    switch (self.parser.previous.tag) {
                        .Eof => continue :parse .done,
                        .RightParen => {
                            // Tracer.traceCompile(
                            //     "[PARSER] .right_paren  count: {d}  \n",
                            //     .{open_paren_cnt},
                            // );
                            if (open_paren_cnt <= 0) {
                                self.diagnostics.reportError(.{
                                    .error_type = LoxError.UnmatchedClosingParen,
                                    .message = "')' requires an opening paren ')'",
                                    .src_code = self.src[self.parser.previous.loc.start..self.parser.previous.loc.end],
                                    .token = self.parser.previous,
                                });
                                break :parse;
                            }

                            open_paren_cnt -= 1;

                            // close out the grouping
                            self.consumeGroup(&op_stack, chunk);

                            // keep precedence order for ops
                            // BUG: this can't live here
                            self.consumeUnary(&op_stack, chunk);

                            self.advance();
                            continue :parse .start;
                        },
                        else => {
                            Tracer.traceCompile(
                                "[PARSER] .got_value else_binary  count: {d}  \n",
                                .{op_stack.items.len},
                            );
                            // Check if it's a binary operator
                            if (getBinaryOp(self.parser.previous.tag)) |binary_op| {
                                // Handle previous binary operators with precedence
                                self.consumeBinary(&op_stack, binary_op.precedence, chunk);

                                // Push the new operator onto the stack
                                Tracer.traceCompile("[PARSER] about to push operator to stack\n", .{});
                                op_stack.append(self.gpa, binary_op) catch unreachable;
                                Tracer.traceCompile("[PARSER] pushed operator to stack\n", .{}); // Now we expect a value again

                                parse_state = .expecting_value;
                                self.advance();
                                continue :parse .start;
                            } else {
                                // Not a binary operator, error
                                continue :parse .unimplemented;
                            }
                        },
                    }
                },
            }
        },
        .primary => {
            Tracer.traceCompile("[PARSER] .primary\n", .{});
            switch (self.parser.previous.tag) {
                .Number => {
                    Tracer.traceCompile("[PARSER] .number\n", .{});
                    const value = self.parser.previous.literalValue(self.src).number;
                    self.emitConstant(chunk, .{ .number = value });
                },
                .True => {
                    Tracer.traceCompile("[PARSER] .true\n", .{});
                    self.emitByte(chunk, @intFromEnum(OpCode.True));
                },
                .False => {
                    Tracer.traceCompile("[PARSER] .false\n", .{});
                    self.emitByte(chunk, @intFromEnum(OpCode.False));
                },
                .Nil => {
                    Tracer.traceCompile("[PARSER] .nil\n", .{});
                    self.emitByte(chunk, @intFromEnum(OpCode.Nil));
                },
                .Eof => continue :parse .done,
                else => unreachable, // NOTE: unimplemented or an error?
            }

            // manage what parser is looking for
            parse_state = .got_value;

            // Look ahead for binary operators
            Tracer.traceCompile("[PARSER] .primary_fall {t}\n", .{
                self.parser.current.tag,
            });

            // Set parse state based on what we just parsed
            parse_state = .got_value;

            // Continue to handle what comes next
            self.advance();
            continue :parse .start;
        },
        .unary => {
            Tracer.traceCompile("[PARSER] .unary {t}\n", .{
                self.parser.current.tag, // operand start
            });

            // push the operation
            const op = self.parser.previous.tag;
            switch (op) {
                .Minus => op_stack.append(self.gpa, .{
                    .precedence = .unary,
                    .code = .Negate,
                }) catch unreachable,
                .Bang => op_stack.append(self.gpa, .{
                    .precedence = .unary,
                    .code = .Not,
                }) catch unreachable,
                else => unreachable,
            }

            // go and get the operand
            parse_state = .expecting_value;
            self.advance();
            continue :parse .start;
        },
        .done => {
            if (open_paren_cnt > 0) {
                self.diagnostics.reportError(.{
                    .error_type = LoxError.Unclosedgrouping,
                    .message = "')' requires an opening paren ')'",
                    .src_code = self.src[self.parser.previous.loc.start..self.parser.previous.loc.end],
                    .token = self.parser.previous,
                });
            }
            Tracer.traceCompile("[PARSER] .done\n", .{});

            // Consume all remaining operators before finishing
            self.consumeAllOperators(&op_stack, chunk);

            self.emitReturn(chunk);
            break :parse;
        },
        .unimplemented => {
            Tracer.traceCompile("[PARSER] .unimplemented\n", .{});
            self.diagnostics.reportError(.{
                .message = "[PARSER] unimplemented op",
                .token = self.parser.previous,
                .error_type = LoxError.Unimplemented,
                .src_code = self.src[self.parser.previous.loc.start..self.parser.current.loc.end],
            });
            return .Compile_Error;
        },
    }
    return .Ok;
}

fn emitByte(self: *Compiler, chunk: *Chunk, byte: u8) void {
    Tracer.traceCompile("[EMIT] byte={} opcode={any}\n", .{ byte, @as(OpCode, @enumFromInt(byte)) });
    chunk.writeChunk(byte, @intCast(self.parser.previous.src_loc.line));
}
fn emitBytes(self: *Compiler, chunk: *Chunk, byte1: u8, byte2: u8) void {
    chunk.writeChunk(byte1, @intCast(self.parser.previous.src_loc.line));
    chunk.writeChunk(byte2, @intCast(self.parser.previous.src_loc.line));
}
fn emitConstant(self: *Compiler, chunk: *Chunk, value: Value) void {
    const constant = chunk.addConstant(value);
    self.emitBytes(chunk, @intFromEnum(OpCode.Constant), constant);
}

fn emitReturn(self: *Compiler, chunk: *Chunk) void {
    self.emitByte(chunk, @intFromEnum(OpCode.Return));
}
fn endCompiler(self: *Compiler, chunk: *Chunk) void {
    self.emitReturn(chunk);
}

fn advance(self: *Compiler) void {
    self.parser.previous = self.parser.current;

    while (true) {
        self.parser.current = self.scanner.getToken();

        switch (self.parser.current.tag) {
            .Eof => {
                break;
            },
            .Invalid => {
                if (self.parser.panic_mode) break;
                self.parser.panic_mode = true;
                break;
            },
            else => return,
        }
    }
}
fn expect(self: *Compiler, tag: Token.Tag, msg: []const u8) void {
    if (self.parser.current.tag == tag) {
        self.advance();
        return;
    }

    std.debug.print("{f} Error {s}\n", .{
        self.parser.current.src_loc,
        msg,
    });
}

pub fn init(
    gpa: std.mem.Allocator,
    src: []const u8,
    diagnostic_reporter: *DiagnosticReporter,
) Compiler {
    return .{
        .gpa = gpa,
        .scanner = .init(src[0..], diagnostic_reporter),
        .parser = .{
            .current = undefined,
            .previous = undefined,
            .had_error = false,
            .panic_mode = false,
        },
        .diagnostics = diagnostic_reporter,
        .src = src[0..],
    };
}
