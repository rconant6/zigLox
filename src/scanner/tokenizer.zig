const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const lox = @import("../lox.zig");
const DiagnosticReporter = lox.DiagnosticReporter;
const ErrorContext = lox.ErrorContext;
const LiteralValue = lox.LiteralValue;
const LoxError = lox.LoxError;

pub const Token = struct {
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
            else => .{ .void = {} },
        };
    }

    pub fn error_format(self: Token, w: *std.Io.Writer) !void {
        try w.print("at: {f}   type: {t:13}", .{
            self.src_loc,
            self.tag,
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

    const SrcLoc = struct {
        line: u32,
        col: u32,

        pub fn format(self: SrcLoc, w: *std.Io.Writer) !void {
            try w.print("Line: {d:4} Col: {d:4}", .{
                self.line,
                self.col,
            });
        }
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
            try w.print("Start: {d:4} End: {d:4} Len: {d:2}", .{
                self.start,
                self.end,
                self.len(),
            });
        }
    };
};

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

pub const Tokenizer = struct {
    idx: u32,
    line: u32,
    col: u32,

    pub fn init() Tokenizer {
        return .{ .idx = 0, .line = 1, .col = 1 };
    }

    // SRC Navigation
    fn char(self: *Tokenizer, src: []const u8) u8 {
        if (self.idx >= src.len) return 0;
        return src[self.idx];
    }
    fn advance(self: *Tokenizer) void {
        self.idx += 1;
        self.col += 1;
    }
    fn newline(self: *Tokenizer) void {
        self.idx += 1;
        self.line += 1;
        self.col = 1;
    }
    fn peek(self: *Tokenizer, src: []const u8, offset: u32) u8 {
        const pos = self.idx + offset;
        if (pos >= src.len) return 0;
        return src[pos];
    }

    // TOKEN Management
    fn startToken(self: *Tokenizer, tok: *Token) void {
        tok.loc.start = self.idx;
        tok.src_loc.line = self.line;
        tok.src_loc.col = self.col;
    }
    fn endToken(self: *Tokenizer, tok: *Token) void {
        tok.loc.end = self.idx;
    }
    fn singleCharToken(self: *Tokenizer, tok: *Token, tag: Token.Tag) void {
        self.startToken(tok);
        self.advance();
        self.endToken(tok);
        tok.tag = tag;
    }
    fn twoCharToken(
        self: *Tokenizer,
        tok: *Token,
        single_tag: Token.Tag,
        double_tag: Token.Tag,
        second_char: u8,
        src: []const u8,
    ) void {
        self.startToken(tok);
        self.advance();

        if (self.char(src) == second_char) {
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

    pub fn scanTokens(
        self: *Tokenizer,
        gpa: Allocator,
        src: []const u8,
        diagnostic: *DiagnosticReporter,
    ) ![]Token {
        var tokens: ArrayList(Token) = .empty;
        var tok: Token = .{
            .tag = .Invalid,
            .loc = .{ .start = 0, .end = 0 },
            .src_loc = .{ .line = 0, .col = 0 },
        };

        state: switch (State.start) {
            .start => start: switch (self.char(src)) {
                0 => {
                    tok.tag = .Eof;
                    self.startToken(&tok);
                    self.endToken(&tok);
                    try tokens.append(gpa, tok);
                    continue :state .end;
                },
                // Whitespace
                ' ', '\t', '\r' => {
                    self.advance();
                    continue :start self.char(src);
                },
                '\n' => {
                    self.newline();
                    continue :start self.char(src);
                },
                // Single character tokens
                '(', ')', '[', ']', '{', '}', ',', '.', '-', '+', ';', '*' => |c| {
                    const tag = single_char_tokens.get(&.{c}) orelse .Invalid;
                    self.singleCharToken(&tok, tag);
                    try tokens.append(gpa, tok);
                    continue :start self.char(src);
                },
                // Potential two-character tokens
                '!', '=', '<', '>' => |c| {
                    const single_tag = double_char_tokens.get(&.{c}) orelse .Invalid;
                    const double_tag = double_char_tokens.get(&.{ c, '=' }) orelse single_tag;
                    self.twoCharToken(&tok, single_tag, double_tag, '=', src);
                    try tokens.append(gpa, tok);
                    continue :start self.char(src);
                },
                // Slash or comment
                '/' => {
                    if (self.peek(src, 1) == '/') {
                        self.advance();
                        self.advance();
                        continue :state .comment;
                    } else {
                        self.singleCharToken(&tok, .Slash);
                        try tokens.append(gpa, tok);
                        continue :start self.char(src);
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
                    self.singleCharToken(&tok, .Invalid);
                    const ctx: ErrorContext = .init(
                        "Invalid character",
                        LoxError.UnRecognizedCharacter,
                        tok,
                    );
                    diagnostic.reportError(ctx);
                    continue :start self.char(src);
                },
            },
            .comment => comment: switch (self.char(src)) {
                0 => {
                    // EOF - add EOF token and finish
                    tok.tag = .Eof;
                    self.startToken(&tok);
                    self.endToken(&tok);
                    try tokens.append(gpa, tok);
                    continue :state .end;
                },
                '\n' => {
                    self.newline();
                    continue :state .start;
                },
                else => {
                    // self.singleCharToken(&tok, .Invalid);
                    self.advance();
                    continue :comment self.char(src);
                },
            },
            .string => string: switch (self.char(src)) {
                0 => {
                    // Unterminated string - invalid token and EOF
                    self.endToken(&tok);
                    tok.tag = .Invalid;
                    const ctx: ErrorContext = .init(
                        "Unterminated string",
                        LoxError.UnterminatedString,
                        tok,
                    );
                    diagnostic.reportError(ctx);

                    tok.tag = .Eof;
                    self.startToken(&tok);
                    self.endToken(&tok);
                    try tokens.append(gpa, tok);
                    continue :state .end;
                },
                '"' => {
                    self.advance();
                    self.endToken(&tok);
                    tok.tag = .String;
                    try tokens.append(gpa, tok);
                    continue :state .start;
                },
                '\n' => {
                    self.newline();
                    continue :string self.char(src);
                },
                else => {
                    self.advance();
                    continue :string self.char(src);
                },
            },
            .identifier => identifier: switch (self.char(src)) {
                'A'...'Z', 'a'...'z', '0'...'9', '_' => {
                    self.advance();
                    continue :identifier self.char(src);
                },
                else => {
                    self.endToken(&tok);
                    const lexeme = tok.lexeme(src);
                    tok.tag = keywords.get(lexeme) orelse .Identifier;
                    try tokens.append(gpa, tok);
                    continue :state .start;
                },
            },
            .number => number: switch (self.char(src)) {
                '0'...'9' => {
                    self.advance();
                    continue :number self.char(src);
                },
                '.' => {
                    if (std.ascii.isDigit(self.peek(src, 1))) {
                        self.advance(); // consume '.'
                        continue :state .number_after_dot;
                    } else {
                        self.endToken(&tok);
                        tok.tag = .Number;
                        try tokens.append(gpa, tok);
                        continue :state .start;
                    }
                },
                else => {
                    self.endToken(&tok);
                    tok.tag = .Number;
                    try tokens.append(gpa, tok);
                    continue :state .start;
                },
            },
            .number_after_dot => after_dot: switch (self.char(src)) {
                '0'...'9' => {
                    self.advance();
                    continue :after_dot self.char(src);
                },
                else => {
                    // End of number
                    self.endToken(&tok);
                    tok.tag = .Number;
                    try tokens.append(gpa, tok);
                    continue :state .start;
                },
            },

            .end => {
                for (tokens.items) |token| {
                    std.debug.print("{f} {s}\n", .{ token, token.lexeme(src) });
                }
                if (diagnostic.hasErrors()) {
                    tokens.deinit(gpa);
                    return LoxError.LexingError;
                }
                return tokens.toOwnedSlice(gpa);
            },
        }
    }
};
