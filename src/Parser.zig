pub const Parser = @This();

const std = @import("std");
const lox = @import("lox.zig");
const DiagnosticsReporter = lox.DiagnosticReporter;
const ErrorContext = lox.ErrorContext;
const Expr = lox.Expr;
const ExprValue = lox.ExprValue;
const LoxError = lox.LoxError;
const Token = lox.Token;
const TokenType = lox.TokenType;

allocator: std.mem.Allocator,
source: []const Token,
expressions: std.ArrayList(Expr),
diagnostics: *DiagnosticsReporter,
current: usize,
panic_mode: bool,

pub fn init(
    gpa: std.mem.Allocator,
    tokens: []const Token,
    diagnostic: *DiagnosticsReporter,
) Parser {
    return .{
        .allocator = gpa,
        .source = tokens,
        .expressions = .empty,
        .diagnostics = diagnostic,
        .current = 0,
        .panic_mode = false,
    };
}

pub fn parse(self: *Parser) LoxError!*Expr {
    return self.expression();
}

fn expression(self: *Parser) LoxError!*Expr {
    return self.equality();
}

fn equality(self: *Parser) LoxError!*Expr {
    return self.parseBinary(
        &.{ .BANG_EQUAL, .EQUAL_EQUAL },
        comparison,
    );
}

fn comparison(self: *Parser) LoxError!*Expr {
    return self.parseBinary(
        &.{ .GREATER, .GREATER_EQUAL, .LESS, .LESS_EQUAL },
        term,
    );
}
fn term(self: *Parser) LoxError!*Expr {
    return self.parseBinary(
        &.{ .MINUS, .PLUS },
        factor,
    );
}
fn factor(self: *Parser) LoxError!*Expr {
    return self.parseBinary(
        &.{ .SLASH, .STAR },
        unary,
    );
}

fn unary(self: *Parser) LoxError!*Expr {
    if (self.match(&.{ .BANG, .MINUS })) |op| {
        const right = try self.unary();

        const node = try self.allocator.create(Expr);
        errdefer self.allocator.destroy(node);
        node.* = .{ .Unary = .{
            .op = op,
            .expr = right,
        } };

        return node;
    }

    return self.primary();
}

fn primary(self: *Parser) LoxError!*Expr {
    const token = self.peek() orelse return LoxError.ExpectedExpression;

    const node = try self.allocator.create(Expr);
    errdefer self.allocator.destroy(node);

    switch (token.type) {
        .TRUE, .FALSE => {
            self.advance();
            node.* = .{ .Literal = .{
                .value = ExprValue{ .Bool = token.literal.bool },
            } };
            return node;
        },
        .NUMBER => {
            self.advance();
            node.* = .{ .Literal = .{
                .value = ExprValue{ .Number = token.literal.number },
            } };
            return node;
        },
        .STRING => {
            self.advance();
            node.* = .{ .Literal = .{ .value = .{
                .String = token.literal.string,
            } } };
            return node;
        },
        .LEFT_PAREN => {
            self.advance();
            const expr = try self.expression();
            errdefer self.freeExpr(expr);

            if ((self.match(&.{.RIGHT_PAREN}))) |_| {} else {
                const err_token = self.previous() orelse self.source[self.current];
                self.parseError(
                    LoxError.ExpectedClosingParen,
                    "Expected ')' to close '('",
                    err_token,
                );
            }

            node.* = .{ .Group = .{ .expr = expr } };
            return node;
        },
        else => {
            const err_token = self.previous() orelse self.source[self.current];
            self.parseError(LoxError.ExpectedExpression, "Expected expression", err_token);
            return LoxError.ExpectedExpression;
        },
    }
}

// MARK: Parsing Creators
fn parseBinary(self: *Parser, comptime token_types: []const TokenType, next: fn (*Parser) LoxError!*Expr) LoxError!*Expr {
    var left = try next(self);
    errdefer self.freeExpr(left);

    while (true) {
        const token = self.match(token_types) orelse break;
        const right = try next(self);
        errdefer self.freeExpr(right);

        const node = try self.allocator.create(Expr);
        errdefer self.allocator.destroy(node);

        node.* = .{ .Binary = .{
            .left = left,
            .op = token,
            .right = right,
        } };
        left = node;
    }
    return left;
}

// MARK: Error Handling
fn parseError(self: *Parser, err: LoxError, message: []const u8, token: Token) void {
    if (self.panic_mode) return;

    self.panic_mode = true;
    self.diagnostics.reportError(ErrorContext.init(message, err).withToken(token));
}

fn synchronize(self: *Parser) void {
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
fn freeExpr(self: *Parser, expr: *Expr) void {
    switch (expr.*) {
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
        .Literal => {},
        .Unary => |u| {
            self.freeExpr(u.expr);
            self.allocator.destroy(u.expr);
        },
    }
}

// MARK: Helpers
fn previous(self: *Parser) ?Token {
    if (self.current <= 0) return null;
    return self.source[self.current];
}

fn peek(self: *Parser) ?Token {
    if (self.current >= self.source.len) return null;
    return self.source[self.current];
}

fn advance(self: *Parser) void {
    if (self.current < self.source.len) self.current += 1;
}

fn check(self: *Parser, t_type: TokenType) bool {
    if (self.current >= self.source.len) return false;
    const curr_type = self.source[self.current];
    return curr_type.type == t_type;
}

fn match(self: *Parser, types: []const TokenType) ?Token {
    const token = self.peek() orelse return null;

    for (types) |t| {
        if (token.type == t) {
            self.advance();
            return token;
        }
    }

    return null;
}

fn consume(self: *Parser, t_type: TokenType) ?Token {
    const token = self.peek() orelse return null;
    if (token.type == t_type) {
        self.advance();
        return token;
    } else return null;
}

fn expect(self: *Parser, t_type: TokenType, message: []const u8) !Token {
    if (self.consume(t_type)) |token|
        return token;
    const token = self.peek() orelse self.source[self.current - 1];
    self.parseError(LoxError.ExpectedToken, message, token);
}
