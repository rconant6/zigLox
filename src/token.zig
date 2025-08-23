const std = @import("std");

const lox = @import("lox.zig");
const LiteralValue = lox.LiteralValue;
const Location = lox.Location;

pub const TokenType = enum {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    LEFT_BRACKET,
    RIGHT_BRACKET,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,

    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,

    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,

    // Keywords.
    AND,
    CLASS,
    ELSE,
    FALSE,
    FUN,
    FOR,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,

    EOF,
};

pub const Token = struct {
    type: TokenType,
    literal: LiteralValue,
    lexeme: []const u8,
    loc: Location,

    pub fn init(tok_type: TokenType, lexeme: []const u8, loc: Location) Token {
        const literal_val: LiteralValue = switch (tok_type) {
            .NUMBER => blk: {
                const num: f64 = std.fmt.parseFloat(f64, lexeme) catch {
                    std.log.err("Unable to convert {s} to f64\n", .{lexeme});
                    break :blk .{ .number = std.math.nan(f64) };
                };
                break :blk .{ .number = num };
            },
            .TRUE => .{ .bool = true },
            .FALSE => .{ .bool = false },
            .EOF => .{ .void = {} },
            else => .{ .string = lexeme },
        };

        return .{
            .type = tok_type,
            .literal = literal_val,
            .lexeme = lexeme,
            .loc = loc,
        };
    }
    pub fn format(t: Token, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print(
            "Token: Type: {t:<14} at :{f} Text: {s:<10}, Literal: {any}",
            .{ t.type, t.loc, t.lexeme, t.literal },
        );
    }
};
