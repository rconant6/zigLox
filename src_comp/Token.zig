pub const Token = @This();

const std = @import("std");
const lox = @import("lox.zig");
const LiteralValue = lox.Value;
const Loc = lox.Location;
const SrcLoc = lox.SourceLocation;

tag: Tag,
loc: Loc,
src_loc: SrcLoc,

pub fn lexeme(self: Token, code: []const u8) []const u8 {
    return self.loc.slice(code);
}

pub fn literalValue(self: Token, code: []const u8) LiteralValue {
    return switch (self.tag) {
        .Number => .{ .number = std.fmt.parseFloat(
            f64,
            self.loc.slice(code),
        ) catch unreachable },
        .String => blk: {
            const slice = self.loc.slice(code);
            const len = slice.len;
            break :blk .{ .string = slice[1 .. len - 1] };
        },
        .Identifier => .{ .string = self.loc.slice(code) },
        .True => .{ .bool = true },
        .False => .{ .bool = false },
        else => .{ .nil = {} },
    };
}

pub fn error_format(self: Token, w: *std.Io.Writer) !void {
    try w.print(" at: {f}", .{
        self.src_loc,
    });
}

pub fn format(self: Token, w: *std.Io.Writer) !void {
    try w.print(
        "TOKEN: {t:13} Src: {f}, Data: {f}",
        .{ self.tag, self.src_loc, self.loc },
    );
}

pub const Tag = enum {
    // Single-character tokens.
    LeftParen,
    RightParen,
    LeftBrace,
    RightBrace,
    LeftBracket,
    RightBracket,
    Comma,
    Dot,
    Minus,
    Plus,
    SemiColon,
    Slash,
    Star,
    // One or two character tokens.
    Bang,
    BangEqual,
    Equal,
    EqualEqual,
    Greater,
    GreaterEqual,
    Less,
    LessEqual,
    // Literals.
    Identifier,
    String,
    Number,
    // Keywords.
    And,
    Class,
    Else,
    False,
    Fun,
    For,
    If,
    Nil,
    Or,
    Print,
    Return,
    Super,
    This,
    True,
    Var,
    While,

    Eof,
    Invalid,
};
