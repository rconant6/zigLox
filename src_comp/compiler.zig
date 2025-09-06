pub const Compiler = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const InterpretResult = lox.InterpretResult;
const OpCode = lox.OpCode;
const Scanner = lox.Scanner;
const Token = lox.Token;
const Value = lox.Value;

scanner: Scanner,
parser: Parser,
src: []const u8,

pub fn init(src: []const u8) Compiler {
    return .{
        .scanner = .init(src[0..]),
        .parser = .{
            .current = undefined,
            .previous = undefined,
            .had_error = false,
            .panic_mode = false,
        },
        .src = src[0..],
    };
}

pub fn compile(self: *Compiler, chunk: *Chunk) InterpretResult {
    self.advance();
    self.expression(chunk);
    self.expect(.Eof, "Expect end of expression");
    self.endCompiler(chunk);

    return if (self.parser.had_error) .{ .Compile_Error = self.scanner.scan_error.? } else .Ok;
}
fn parsePrecedence(self: *Compiler, precedence: Parser.Precedence, chunk: *Chunk) void {
    _ = self;
    _ = chunk;
    _ = precedence;
}

fn emitByte(self: *Compiler, chunk: *Chunk, byte: u8) void {
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

fn expression(self: *Compiler, chunk: *Chunk) void {
    if (self.parser.current.tag == .Number) {
        self.parsePrecedence(.Assignment, chunk);
    }
}
fn grouping(self: *Compiler, chunk: *Chunk) void {
    self.expression(chunk);
    self.expect(.RightParen, "Expect ')' after expression");
}
fn unary(self: *Compiler, chunk: *Chunk) void {
    const op_type = self.parser.previous.tag;

    self.parsePrecedence(.Assignment, chunk);

    switch (op_type) {
        .Minus => {
            self.emitByte(chunk, @intFromEnum(.Negate));
        },
        // missing not when we add bool
        else => unreachable,
    }
    self.expect(.RightParen, "Expect ')' after expression");
}
fn number(self: *Compiler, chunk: *Chunk) void {
    const value = self.parser.previous.literalValue(self.src).number;
    const constant = chunk.addConstant(value);
    self.emitBytes(chunk, @intFromEnum(OpCode.Constant), constant);
}

fn advance(self: *Compiler) void {
    self.parser.previous = self.parser.current;

    // TODO: turn this into a state machine
    while (true) {
        self.parser.current = self.scanner.getToken();
        // std.debug.print("{f}\n", .{self.parser.current});

        switch (self.parser.current.tag) {
            .Eof => {
                std.debug.print(" at end of input\n", .{});
                break;
            },
            .Invalid => {
                if (self.parser.panic_mode) break;
                self.parser.panic_mode = true;
                if (self.scanner.scan_error) |scan_error| {
                    // BUG: Dummy error Processing for now
                    std.debug.print("{f} Error {s}\n", .{
                        scan_error.src,
                        scan_error.msg,
                    });
                }
                break;
            },
            else => std.debug.print(" {s}\n", .{
                self.parser.current.lexeme(self.src),
            }),
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

const Parser = struct {
    current: Token,
    previous: Token,
    had_error: bool,
    panic_mode: bool,

    const Precedence = enum {
        None,
        Assignment, // =
        Or, // or
        And, // and
        Equality, // == !=
        Comparison, // < > <= >=
        Term, // + -
        Factor, // * /
        Unary, // ! -
        Call, // . ()
        Primary,
    };
};
