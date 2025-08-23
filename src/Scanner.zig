pub const Scanner = @This();

const std = @import("std");
const lox = @import("lox.zig");
const DiagnosticsReporter = lox.DiagnosticReporter;
const ErrorContext = lox.ErrorContext;
const Location = lox.Location;
const LoxError = lox.LoxError;
const Token = lox.Token;
const TokenType = lox.TokenType;

const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "and", .AND },     .{ "or", .OR },         .{ "if", .IF },
    .{ "else", .ELSE },   .{ "class", .CLASS },   .{ "this", .THIS },
    .{ "super", .SUPER }, .{ "true", .TRUE },     .{ "false", .FALSE },
    .{ "nil", .NIL },     .{ "for", .FOR },       .{ "while", .WHILE },
    .{ "print", .PRINT }, .{ "return", .RETURN }, .{ "fun", .FUN },
    .{ "var", .VAR },
});

const tab_width = 2;

allocator: std.mem.Allocator,
source: []const u8,
diagnostics: *DiagnosticsReporter,
tokens: std.ArrayList(Token),
start: usize,
current: usize,
line: u32,
column: u32,
start_column: u32,
pub fn init(
    allocator: std.mem.Allocator,
    source: []const u8,
    diagnostics: *DiagnosticsReporter,
) !Scanner {
    return .{
        .allocator = allocator,
        .source = source,
        .diagnostics = diagnostics,
        .tokens = .empty,
        .start = 0,
        .current = 0,
        .line = 1,
        .column = 1,
        .start_column = 1,
    };
}

pub fn scanTokens(self: *Scanner) ![]const Token {
    while (!self.isAtEnd()) {
        self.start = self.current;
        try self.scanToken();
    }

    self.start = self.current;
    try self.addToken(.EOF);

    return try self.tokens.toOwnedSlice(self.allocator);
}

fn scanToken(self: *Scanner) !void {
    const c = self.advance();
    self.start_column = self.column - 1;

    switch (c) {
        ' ', '\r', '\t' => {},
        '\n' => self.newLine(),

        '(' => try self.addToken(.LEFT_PAREN),
        ')' => try self.addToken(.RIGHT_PAREN),
        '{' => try self.addToken(.LEFT_BRACE),
        '}' => try self.addToken(.RIGHT_BRACE),
        '[' => try self.addToken(.LEFT_BRACKET),
        ']' => try self.addToken(.RIGHT_BRACKET),
        ',' => try self.addToken(.COMMA),
        '.' => try self.addToken(.DOT),
        '-' => try self.addToken(.MINUS),
        '+' => try self.addToken(.PLUS),
        ';' => try self.addToken(.SEMICOLON),
        '*' => try self.addToken(.STAR),

        '!' => try self.addToken(if (self.match('=')) .BANG_EQUAL else .BANG),
        '=' => try self.addToken(if (self.match('=')) .EQUAL_EQUAL else .EQUAL),
        '<' => try self.addToken(if (self.match('=')) .LESS_EQUAL else .LESS),
        '>' => try self.addToken(if (self.match('=')) .GREATER_EQUAL else .GREATER),

        '/' => {
            if (self.match('/')) {
                self.skipLineComment();
            } else {
                try self.addToken(.SLASH);
            }
        },

        '"' => try self.scanString(),

        '0'...'9' => try self.scanNumber(),

        'a'...'z', 'A'...'Z', '_' => try self.scanIdentifier(),

        else => {
            self.diagnostics.reportError(ErrorContext.init(
                "Unexpected character found",
                LoxError.UnexpectedCharacter,
            ).withLocation(.{
                .line = self.line,
                .col = self.start_column,
            }));
            return LoxError.UnexpectedCharacter;
        },
    }
}

fn addToken(self: *Scanner, token_type: TokenType) !void {
    const text = self.source[self.start..self.current];
    const location = Location{
        .line = self.line,
        .col = self.start_column,
    };

    const token = Token.init(token_type, text, location);
    try self.tokens.append(self.allocator, token);
}

fn scanString(self: *Scanner) !void {
    const start_line = self.line;
    const start_col = self.column;

    while (!self.isAtEnd() and self.peek() != '"') {
        if (self.peek() == '\n') {
            self.newLine();
        }
        _ = self.advance();
    }

    if (self.isAtEnd()) {
        self.diagnostics.reportError(ErrorContext.init(
            "Unterminated string found ",
            LoxError.UnterminatedString,
        ).withLocation(.{
            .line = start_line,
            .col = start_col,
        }));
        return LoxError.UnterminatedString;
    }

    _ = self.advance(); // eat the closing "

    try self.addToken(.STRING);
}

fn scanNumber(self: *Scanner) !void {
    while (isDigit(self.peek())) {
        _ = self.advance();
    }

    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();

        while (isDigit(self.peek())) {
            _ = self.advance();
        }
    }

    try self.addToken(.NUMBER);
}

fn scanIdentifier(self: *Scanner) !void {
    while (isAlphaNumeric(self.peek())) {
        _ = self.advance();
    }

    const text = self.source[self.start..self.current];
    const token_type = keywords.get(text) orelse .IDENTIFIER;

    try self.addToken(token_type);
}

fn skipLineComment(self: *Scanner) void {
    while (!self.isAtEnd() and self.peek() != '\n') {
        _ = self.advance();
    }
}

// MARK: Source Navigation Helpers
fn newLine(self: *Scanner) void {
    self.line += 1;
    self.column = 1;
}

fn advance(self: *Scanner) u8 {
    if (self.isAtEnd()) return 0;

    const c = self.source[self.current];
    self.current += 1;
    self.column += 1;
    return c;
}

fn match(self: *Scanner, expected: u8) bool {
    if (self.isAtEnd()) return false;
    if (self.source[self.current] != expected) return false;

    self.current += 1;
    self.column += 1;
    return true;
}

fn peek(self: *Scanner) u8 {
    if (self.isAtEnd()) return 0;
    return self.source[self.current];
}

fn peekNext(self: *Scanner) u8 {
    if (self.current + 1 >= self.source.len) return 0;
    return self.source[self.current + 1];
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.source.len;
}

// MARK: ASCII Helpers
fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        c == '_';
}

fn isAlphaNumeric(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}
