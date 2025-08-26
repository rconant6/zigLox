pub const Parser = @This();

const std = @import("std");
const ArrayList = std.ArrayList;
const lox = @import("../lox.zig");
const DiagnosticsReporter = lox.DiagnosticReporter;
const ErrorContext = lox.ErrorContext;
const Expr = lox.Expr;
const ExprValue = lox.ExprValue;
const LoxError = lox.LoxError;
const Token = lox.Token;
const TokenType = lox.TokenType;
const Stmt = lox.Stmt;
const program = @import("statements.zig").program;

const expression_int = @import("expressions.zig").expression;

allocator: std.mem.Allocator,
source: []const Token = undefined,
expressions: std.ArrayList(Expr),
diagnostics: *DiagnosticsReporter,
current: usize,
panic_mode: bool,

pub fn init(
    gpa: std.mem.Allocator,
    diagnostic: *DiagnosticsReporter,
) Parser {
    return .{
        .allocator = gpa,
        .expressions = .empty,
        .diagnostics = diagnostic,
        .current = 0,
        .panic_mode = false,
    };
}

// TODO: Update to use labeled switch w/ states? see Tokenizer.zig from loris
// TODO: Remove all pointers for Expr and Stmt: store AST in array, track idices
pub fn parse(self: *Parser, tokens: []const Token) LoxError![]const Stmt {
    var statements: ArrayList(Stmt) = .empty;
    self.source = tokens;
    self.panic_mode = false;

    while (self.peek()) |token| {
        if (token.type == .EOF) break;

        const stmt = program(self) catch |e| {
            if (e == LoxError.ExpectedSemiColon) {
                self.synchronize();
                continue;
            }
            return e;
        };

        // if (stmt) |s| {
        try statements.append(self.allocator, stmt.*);
        // }
    }

    return statements.toOwnedSlice(self.allocator);
}

pub fn expression(p: *Parser) LoxError!*Expr {
    return expression_int(p);
}

// MARK: Error Handling
pub fn parseError(self: *Parser, err: LoxError, message: []const u8, token: Token) void {
    if (self.panic_mode) return;

    self.panic_mode = true;
    self.diagnostics.reportError(ErrorContext.init(message, err).withToken(token));
}

pub fn synchronize(self: *Parser) void {
    self.panic_mode = false;

    while (self.peek()) |token| {
        if (self.previous()) |prev| {
            if (prev.type == .SEMICOLON) return;
        }

        switch (token.type) {
            .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN => return,
            else => {},
        }
        self.advance();
    }
}

// MARK: MemoryManagement
pub fn freeExpr(self: *Parser, expr: *Expr) void {
    switch (expr.*) {
        .Assign => |a| {
            self.freeExpr(a.value);
        },
        .Binary => |b| {
            self.freeExpr(b.left);
            self.freeExpr(b.right);
            self.allocator.destroy(b.left);
            self.allocator.destroy(b.right);
        },
        .Group => |g| {
            self.freeExpr(g.expr);
            self.allocator.destroy(g.expr);
        },
        .Logical => |l| {
            self.freeExpr(l.left);
            self.freeExpr(l.right);
            self.allocator.destroy(l.left);
            self.allocator.destroy(l.right);
        },
        .Unary => |u| {
            self.freeExpr(u.expr);
            self.allocator.destroy(u.expr);
        },
        inline else => {},
    }
}

// MARK: Helpers
pub fn previous(self: *Parser) ?Token {
    if (self.current <= 0) return null;
    return self.source[self.current];
}

pub fn peek(self: *Parser) ?Token {
    if (self.current >= self.source.len) return null;
    return self.source[self.current];
}

pub fn advance(self: *Parser) void {
    if (self.current < self.source.len) self.current += 1;
}

pub fn check(self: *Parser, t_type: TokenType) bool {
    if (self.current >= self.source.len) return false;
    const curr_type = self.source[self.current];
    return curr_type.type == t_type;
}

pub fn match(self: *Parser, types: []const TokenType) ?Token {
    const token = self.peek() orelse return null;

    for (types) |t| {
        if (token.type == t) {
            self.advance();
            return token;
        }
    }

    return null;
}

pub fn consume(self: *Parser, t_type: TokenType) ?Token {
    const token = self.peek() orelse return null;
    if (token.type == t_type) {
        self.advance();
        return token;
    } else return null;
}

pub fn expect(self: *Parser, t_type: TokenType, message: []const u8) !Token {
    if (self.consume(t_type)) |token|
        return token;
    const token = self.peek() orelse self.source[self.current - 1];
    self.parseError(LoxError.ExpectedToken, message, token);

    return LoxError.ExpectedToken;
}
