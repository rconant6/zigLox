pub const Compiler = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const DiagnosticReporter = lox.DiagnosticReporter;
const InterpretResult = lox.InterpretResult;
const OpCode = lox.OpCode;
const Scanner = lox.Scanner;
const Token = lox.Token;
const Value = lox.Value;

scanner: Scanner,
parser: Parser,
diagnostics: *DiagnosticReporter,
src: []const u8,

pub fn init(src: []const u8, diagnostic_reporter: *DiagnosticReporter) Compiler {
    return .{
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

pub fn compile(self: *Compiler, chunk: *Chunk) InterpretResult {
    self.advance();
    self.parseExpression(chunk);
    self.expect(.Eof, "Expect end of expression");
    self.endCompiler(chunk);

    if (self.diagnostics.hasErrors()) {
        self.diagnostics.printDiagnostics(lox.out_writer) catch {
            std.debug.print(
                "Had trouble printing diagnostics...OOPS\n",
                .{},
            );
        };
        self.diagnostics.clearErrors();
        return .Compile_Error;
    } else return .Ok;
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

fn advance(self: *Compiler) void {
    self.parser.previous = self.parser.current;

    // TODO: turn this into a state machine
    while (true) {
        self.parser.current = self.scanner.getToken();

        switch (self.parser.current.tag) {
            .Eof => {
                break;
            },
            .Invalid => {
                if (self.parser.panic_mode) break;
                self.parser.panic_mode = true;
                if (self.diagnostics.hasErrors()) {
                    // std.debug.print("ERROR FOUND: {f}", .{self.diagnostics.errors.items[0]});
                    std.debug.print("ERROR FOUND: \n", .{});
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
};

const ParsePrecedence = enum {
    none,
};

const ParseState = enum {
    expression,
    term,
    factor,
    unary,
    primary,
};

fn parseExpression(self: *Compiler, chunk: *Chunk) void {
    parse: switch (self.parser.current.tag) {
        .Number => {
            const value = self.parser.previous.literalValue(self.src).number;
            const constant = chunk.addConstant(value);
            self.emitBytes(chunk, @intFromEnum(OpCode.Constant), constant);
            self.advance();
            continue :parse self.parser.current.tag;
        },
        .LeftParen => {
            self.advance();
            self.parseExpression(chunk);
            self.expect(.RightParen, "Expect ')' after expression");
            self.advance();
            continue :parse self.parser.current.tag;
        },
        .Nil => {
            self.advance();
            self.emitByte(chunk, @intFromEnum(OpCode.Nil));
            continue :parse self.parser.current.tag;
        },
        .False => {
            self.advance();
            self.emitByte(chunk, @intFromEnum(OpCode.False));
            continue :parse self.parser.current.tag;
        },
        .True => {
            self.advance();
            self.emitByte(chunk, @intFromEnum(OpCode.True));
            continue :parse self.parser.current.tag;
        },
        .Minus => {
            self.advance();
            self.parseExpression(chunk);
            self.emitByte(chunk, @intFromEnum(OpCode.Negate));
            self.advance();
            continue :parse self.parser.current.tag;
        },
        .Plus, .Star, .Slash => {
            const op = self.parser.current.tag;
            self.advance();
            self.parseExpression(chunk);
            switch (op) {
                .Plus => self.emitByte(chunk, @intFromEnum(OpCode.Add)),
                .Star => self.emitByte(chunk, @intFromEnum(OpCode.Multiply)),
                .Slash => self.emitByte(chunk, @intFromEnum(OpCode.Divide)),
                else => unreachable,
            }
            self.advance();
            continue :parse self.parser.current.tag;
        },
        .Eof => return,
        .Invalid => return,
        else => {
            std.debug.print("[PARSER]: Unexpected or invalid token found", .{});
            return;
        },
    }
}

// fn errorAt(self: *Compiler, msg: []const u8) void {
//     self.parser.panic_mode = true;
//     std.debug.print("Compiler Error {s}", .{msg});
// }
