pub const Scanner = @This();

const std = @import("std");
const lox = @import("lox.zig");
const ErrorData = lox.ErrorData;
const Token = lox.Token;

const string_error_msg = "Unclosed string, missing '\"'";
const unrecognized_character = "Unrecognized character";

const single_char_tokens = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "(", .LeftParen },   .{ ")", .RightParen },
    .{ "{", .LeftBrace },   .{ "}", .RightBrace },
    .{ "[", .LeftBracket }, .{ "]", .RightBracket },
    .{ ",", .Comma },       .{ ";", .SemiColon },
    .{ ".", .Dot },         .{ "-", .Minus },
    .{ "+", .Plus },        .{ "*", .Star },
});

const double_char_tokens = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "!=", .BangEqual },    .{ "!", .Bang },
    .{ "==", .EqualEqual },   .{ "=", .Equal },
    .{ "<=", .LessEqual },    .{ "<", .Less },
    .{ ">=", .GreaterEqual }, .{ ">", .Greater },
});

const keywords = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "and", .And },     .{ "or", .Or },         .{ "if", .If },
    .{ "else", .Else },   .{ "class", .Class },   .{ "this", .This },
    .{ "super", .Super }, .{ "true", .True },     .{ "false", .False },
    .{ "nil", .Nil },     .{ "for", .For },       .{ "while", .While },
    .{ "print", .Print }, .{ "return", .Return }, .{ "fun", .Fun },
    .{ "var", .Var },
});

idx: u32,
line: u32,
col: u32,
src: []const u8,
scan_error: ?ErrorData = null,

pub fn init(code: []const u8) Scanner {
    return .{
        .idx = 0,
        .line = 1,
        .col = 1,
        .src = code[0..],
    };
}

// SRC Navigation
fn char(self: *Scanner) u8 {
    if (self.idx >= self.src.len) return 0;
    return self.src[self.idx];
}
fn advance(self: *Scanner) void {
    self.idx += 1;
    self.col += 1;
}
fn newline(self: *Scanner) void {
    self.idx += 1;
    self.line += 1;
    self.col = 1;
}
fn peek(self: *Scanner, offset: u32) u8 {
    const pos = self.idx + offset;
    if (pos >= self.src.len) return 0;
    return self.src[pos];
}

// TOKEN Management
fn startToken(self: *Scanner, tok: *Token) void {
    tok.loc.start = self.idx;
    tok.src_loc.line = self.line;
    tok.src_loc.col = self.col;
}
fn endToken(self: *Scanner, tok: *Token) void {
    tok.loc.end = self.idx;
}
fn singleCharToken(self: *Scanner, tok: *Token, tag: Token.Tag) void {
    self.startToken(tok);
    self.advance();
    self.endToken(tok);
    tok.tag = tag;
}
fn twoCharToken(
    self: *Scanner,
    tok: *Token,
    single_tag: Token.Tag,
    double_tag: Token.Tag,
    second_char: u8,
) void {
    self.startToken(tok);
    self.advance();

    if (self.char() == second_char) {
        self.advance();
        tok.tag = double_tag;
    } else {
        tok.tag = single_tag;
    }

    self.endToken(tok);
}

const State = enum {
    start,
    comment,
    identifier,
    number,
    number_after_dot,
    string,
    end,
};

pub fn getToken(
    self: *Scanner,
) !Token {
    var tok: Token = .{
        .tag = .Invalid,
        .loc = .{ .start = 0, .end = 0 },
        .src_loc = .{ .line = 0, .col = 0 },
    };

    state: switch (State.start) {
        .start => start: switch (self.char()) {
            0 => {
                tok.tag = .Eof;
                self.startToken(&tok);
                self.endToken(&tok);
                continue :state .end;
            },
            // Whitespace
            ' ', '\t', '\r' => {
                self.advance();
                continue :start self.char();
            },
            '\n' => {
                self.newline();
                continue :start self.char();
            },
            // Single character tokens
            '(', ')', '[', ']', '{', '}', ',', '.', '-', '+', ';', '*' => |c| {
                const tag = single_char_tokens.get(&.{c}) orelse .Invalid;
                self.singleCharToken(&tok, tag);
                continue :state .end;
            },
            // Potential two-character tokens
            '!', '=', '<', '>' => |c| {
                const single_tag = double_char_tokens.get(&.{c}) orelse .Invalid;
                const double_tag = double_char_tokens.get(&.{ c, '=' }) orelse single_tag;
                self.twoCharToken(&tok, single_tag, double_tag, '=');
                continue :state .end;
            },
            // Slash or comment
            '/' => {
                if (self.peek(1) == '/') {
                    self.advance();
                    self.advance();
                    continue :state .comment;
                } else {
                    self.singleCharToken(&tok, .Slash);
                    continue :state .end;
                }
            },
            // String literal
            '"' => {
                self.startToken(&tok);
                self.advance();
                continue :state .string;
            },
            // Numbers
            '0'...'9' => {
                self.startToken(&tok);
                continue :state .number;
            },
            // Identifiers
            'A'...'Z', 'a'...'z', '_' => {
                self.startToken(&tok);
                continue :state .identifier;
            },
            // Invalid character
            else => {
                self.startToken(&tok);
                self.endToken(&tok);
                self.scan_error = .{
                    .src = tok.src_loc,
                    .msg = Scanner.unrecognized_character,
                };
                continue :state .end;
            },
        },
        .comment => comment: switch (self.char()) {
            0 => {
                // EOF - add EOF token and finish
                tok.tag = .Eof;
                self.startToken(&tok);
                self.endToken(&tok);
                continue :state .end;
            },
            '\n' => {
                self.newline();
                continue :state .start;
            },
            else => {
                self.advance();
                continue :comment self.char();
            },
        },
        .string => string: switch (self.char()) {
            0 => {
                self.endToken(&tok);
                tok.tag = .Invalid;
                tok.tag = .Eof;
                self.startToken(&tok);
                self.endToken(&tok);
                self.scan_error = .{
                    .msg = Scanner.string_error_msg,
                    .src = tok.src_loc,
                };
                continue :state .end;
            },
            '"' => {
                self.advance();
                self.endToken(&tok);
                tok.tag = .String;
                continue :state .end;
            },
            '\n' => {
                self.newline();
                continue :string self.char();
            },
            else => {
                self.advance();
                continue :string self.char();
            },
        },
        .identifier => identifier: switch (self.char()) {
            'A'...'Z', 'a'...'z', '0'...'9', '_' => {
                self.advance();
                continue :identifier self.char();
            },
            else => {
                self.endToken(&tok);
                const lexeme = tok.lexeme(self.src);
                tok.tag = keywords.get(lexeme) orelse .Identifier;
                continue :state .end;
            },
        },
        .number => number: switch (self.char()) {
            '0'...'9' => {
                self.advance();
                continue :number self.char();
            },
            '.' => {
                if (std.ascii.isDigit(self.peek(1))) {
                    self.advance(); // consume '.'
                    continue :state .number_after_dot;
                } else {
                    self.endToken(&tok);
                    tok.tag = .Number;
                    continue :state .end;
                }
            },
            else => {
                self.endToken(&tok);
                tok.tag = .Number;
                continue :state .end;
            },
        },
        .number_after_dot => after_dot: switch (self.char()) {
            '0'...'9' => {
                self.advance();
                continue :after_dot self.char();
            },
            else => {
                // End of number
                self.endToken(&tok);
                tok.tag = .Number;
                continue :state .end;
            },
        },
        .end => {
            if (self.scan_error != null or tok.tag == .Invalid) {
                return error.ScannerError;
            }
            return tok;
        },
    }
}
