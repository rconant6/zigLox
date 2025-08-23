pub const Scanner = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Token = lox.Token;
const TokenType = lox.TokenType;
const Location = lox.Location;

const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "and", .AND },     .{ "or", .OR },         .{ "if", .IF },
    .{ "else", .ELSE },   .{ "class", .CLASS },   .{ "this", .THIS },
    .{ "super", .SUPER }, .{ "true", .TRUE },     .{ "false", .FALSE },
    .{ "nil", .NIL },     .{ "for", .FOR },       .{ "while", .WHILE },
    .{ "print", .PRINT }, .{ "return", .RETURN }, .{ "fun", .FUN },
    .{ "var", .VAR },     .{ "eof", .EOF },
});

const symbols = std.StaticStringMap(TokenType).initComptime(.{
    .{ "(", .LEFT_PAREN },     .{ ")", .RIGHT_PAREN },
    .{ "{", .LEFT_BRACE },     .{ "}", .RIGHT_BRACE },
    .{ "<=", .LESS_EQUAL },    .{ "<", .LESS },
    .{ ">=", .GREATER_EQUAL }, .{ ">", .GREATER },
    .{ "!=", .BANG_EQUAL },    .{ "!", .BANG },
    .{ "==", .EQUAL_EQUAL },   .{ "=", .EQUAL },
    .{ ",", .COMMA },          .{ ";", .SEMICOLON },
    .{ ".", .DOT },            .{ "/", .SLASH },
    .{ "+", .PLUS },           .{ "-", .MINUS },
    .{ "*", .STAR },
});

const tab_width = 2;

allocator: std.mem.Allocator,
data: []const u8,
tokens: std.ArrayList(Token),
file_loc: Location,
current: u32,
start: u32,
end: u32,

pub fn init(allocator: std.mem.Allocator, data: []const u8) !Scanner {
    return .{
        .allocator = allocator,
        .data = data,
        .tokens = try .initCapacity(allocator, 1028),
        .file_loc = .{ .line = 1, .col = 1 },
        .current = 0,
        .start = 0,
        .end = 0,
    };
}

pub fn scanTokens(self: *Scanner) ![]const Token {
    while (!self.isAtEnd()) {
        const c = self.advance();

        if (std.ascii.isWhitespace(c)) {
            switch (c) {
                '\n' => self.file_loc.nextLine(),
                '\r' => self.file_loc.nextLine(),
                '\t' => self.file_loc.advanceBy(tab_width),
                ' ' => self.file_loc.advance(),
                else => {},
            }
            continue;
        }
        if (c == '/') {
            if (self.matchNext('/')) {
                self.current += 2;
                var nc: u8 = self.advance();
                while (!self.isAtEnd()) : (nc = self.advance()) {
                    if (nc == '\n') break;
                }
                self.file_loc.nextLine();
                continue;
            }
        }
        if (c == '"') {
            std.log.debug("Making a string", .{});
            self.start = self.current;
            var nc = self.advance();
            while (!self.isAtEnd()) : (nc = self.advance()) {
                if (nc == '"') {
                    self.end = self.current - 1; // skip the closing "
                    self.addToken(.STRING);
                    break;
                }
                if (nc == '\n') {
                    self.file_loc.nextLine();
                } else {
                    self.file_loc.advance();
                }
            }

            if (self.remaining() == 0) {
                // TODO: add error for unclosed string
                std.log.err("unclosed string ending file", .{});
            }
            continue;
        }
        if (std.ascii.isAlphabetic(c) or c == '_') {
            self.start = self.current - 1;
            var nc = self.advance();
            while (!self.isAtEnd()) : (nc = self.advance()) {
                if (!std.ascii.isAlphanumeric(nc)) break;
                self.file_loc.advance();
            }
            self.end = self.current - 1;
            const str_len = self.end - self.start;
            const text = self.data[self.start .. self.start + str_len];
            self.reverse();

            const t_type = keywords.get(text) orelse .IDENTIFIER;
            self.addToken(t_type);

            continue;
        }
        if (std.ascii.isDigit(c)) {
            self.start = self.current - 1;
            var nc = self.advance();
            var dot_scene = false;
            while (!self.isAtEnd()) : (nc = self.advance()) {
                if (!std.ascii.isDigit(nc)) {
                    if (!dot_scene and self.floatTest()) {
                        nc = self.advance();
                        dot_scene = true;
                        continue;
                    }
                    self.reverse();
                    break;
                }
            }
            self.end = self.current;
            self.addToken(.NUMBER);
            continue;
        }

        if (self.peek() == '=') { // length 2 symbols
            self.start = self.current - 1;
            const word: [2]u8 = .{ c, '=' };
            if (symbols.get(&word)) |symbol| {
                _ = self.advance(); // consume the equqal sign
                self.end = self.current;
                self.addToken(symbol);
                self.file_loc.advanceBy(2);
                continue;
            }
        }

        if (symbols.get(&.{c})) |symbol| { // length 1 symbols
            self.start = self.current - 1;
            self.end = self.start + 1;
            self.addToken(symbol);
            self.file_loc.advance();
            continue;
        }

        // TODO: add an unexpected character error
    }

    self.closeOut();

    return self.tokens.toOwnedSlice(self.allocator);
}

fn addToken(self: *Scanner, tok_type: TokenType) void {
    const tok_len = self.end - self.start;
    const token: Token = .init(
        tok_type,
        self.data[self.start .. self.start + tok_len],
        self.file_loc,
    );
    self.tokens.append(self.allocator, token) catch |err| {
        std.log.err(
            "Unable to add token to scanner.tokens: Token: {any} Error: {any}\n",
            .{ token, err },
        );
    };
}

fn matchNext(self: *Scanner, c: u8) bool {
    if (self.current >= self.data.len) return false;
    return c == self.peek();
}

fn floatTest(self: *Scanner) bool {
    if (self.current + 2 >= self.data.len) return false;
    const next = self.data[self.current - 1];
    const next_is_dot = next == '.';
    const isNum = std.ascii.isDigit(self.peek());

    std.log.debug("Next: {c} NextIsDot: {} Peek: {c} isNum: {}", .{ next, next_is_dot, self.peek(), isNum });
    return (next_is_dot and isNum);
}

fn peek(self: *Scanner) u8 {
    return self.data[self.current];
}

fn advance(self: *Scanner) u8 {
    const result = self.data[self.current];
    self.current += 1;
    return result;
}
fn advancedBy(self: *Scanner, offset: u32) u8 {
    std.debug.assert(self.data.len > self.current + 2);
    self.current += offset;
    return self.data[self.current - 1];
}
fn reverse(self: *Scanner) void {
    self.current -= 1;
}

fn remaining(self: *Scanner) u64 {
    return self.data.len - self.current;
}

fn isAtEnd(self: *Scanner) bool {
    return self.current >= self.data.len;
}

fn closeOut(self: *Scanner) void {
    self.start = self.current;
    self.end = self.start;
    self.addToken(.EOF);
}
