pub const Compiler = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Chunk = lox.Chunk;
const InterpretResult = lox.InterpretResult;
const Scanner = lox.Scanner;
const Token = lox.Token;

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
    _ = chunk;

    self.advance();
    expression();
    self.expect(.Eof, "Expect end of expression");

    return if (self.parser.had_error)
        .{ .Compile_Error = self.scanner.scan_error.? }
    else
        .{ .Ok = {} };
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

fn expression() void {}
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
