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

const Parser = struct {
    current: Token,
    previous: Token,
    had_error: bool,
    panic_mode: bool,
};

const ParseState = enum {
    start,
    primary,
    unimplemented,
    done,
};

/// parser.previous is your current token to be processed
/// parser.current is what you used to decide on the next state to move to
/// advance is called to then move current into previous
/// and set up the decision tree again once the new token is set
pub fn compile(self: *Compiler, chunk: *Chunk) InterpretResult {
    self.parser.current = self.scanner.getToken();
    self.advance();

    parse: switch (ParseState.start) {
        .start => {
            Tracer.traceCompile("[PARSER] .start {t}\n", .{self.parser.previous.tag});
            switch (self.parser.previous.tag) {
                .Number, .True, .False, .Nil => continue :parse .primary,
                .Eof => continue :parse .done,
                else => continue :parse .unimplemented,
            }
        },
        .primary => {
            Tracer.traceCompile("[PARSER] .primary\n", .{});
            switch (self.parser.previous.tag) {
                .Number => {
                    Tracer.traceCompile("[PARSER] .number\n", .{});
                    const value = self.parser.previous.literalValue(self.src).number;
                    self.emitConstant(chunk, value);
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
                else => unreachable,
            }

            // fall through to decide next action since not forced by the above
            Tracer.traceCompile("[PARSER] .primary_fall {t}\n", .{
                self.parser.current.tag,
            });
            switch (self.parser.current.tag) {
                .Eof => continue :parse .done,
                else => {
                    self.advance();
                    continue :parse .start;
                },
            }
        },
        .done => {
            Tracer.traceCompile("[PARSER] .done\n", .{});
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
