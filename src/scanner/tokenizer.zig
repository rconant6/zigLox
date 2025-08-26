const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const lox = @import("../lox.zig");
const LiteralValue = lox.LiteralValue;

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    fn lexeme(self: Token, code: []const u8) []const u8 {
        return self.loc.slice(code);
    }

    fn literalValue(self: Token, code: []const u8) LiteralValue {
        return switch (self.tag) {
            .Number => .{ .number = std.fmt.parseFloat(
                f64,
                self.loc.slice(code),
            ) catch unreachable },
            .String => blk: {
                const slice = self.loc.slice;
                const len = slice.len;
                break :blk .{ .string = slice[1 .. len - 1] };
            },
            .Identifier => .{ .string = self.loc.slice(code) },
            .True => .{ .bool = true },
            .False => .{ .bool = false },
            else => .{ .void = {} },
        };
    }

    pub fn format(self: Token, w: *std.Io.Writer) !void {
        try w.print("Token: {t} Loc: {f}", .{ self.tag, self.loc });
    }

    const Tag = enum {
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
        Semicolon,
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
    };

    const Loc = struct {
        start: u32,
        end: u32,
        fn len(loc: Loc) u32 {
            return loc.end - loc.start;
        }
        fn slice(self: Loc, code: []const u8) []const u8 {
            return code[self.start..self.end];
        }

        pub fn format(self: Loc, w: *std.Io.Writer) !void {
            try w.print("Start: {d:4}  End: {d:4}  Len: {d}", .{
                self.start,
                self.end,
                self.len(),
            });
        }
    };
};

pub const Tokenizer = struct {
    idx: u32,

    pub fn init() Tokenizer {
        return .{ .idx = 0 };
    }

    fn next(self: *Tokenizer, src: []const u8) ?Token {
        _ = self;
        _ = src;
        @panic("Not Implemented");
    }

    pub fn scanTokens(self: *Tokenizer, gpa: Allocator, src: []const u8) ![]Token {
        var tokens: ArrayList(Token) = .empty;

        while (self.next(src)) |token| {
            try tokens.append(gpa, token);
            std.debug.print("{f}", .{token});
        }

        return tokens.toOwnedSlice(gpa);
    }
};
