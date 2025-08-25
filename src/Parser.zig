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
const Stmt = lox.Stmt;

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

pub fn parse(self: *Parser, tokens: []const Token) LoxError![]const Stmt {
    var statements: std.ArrayList(Stmt) = .empty;
    self.source = tokens;
    self.panic_mode = false;

    while (self.peek()) |token| {
        if (token.type == .EOF) break;

        const stmt = self.declaration() catch |e| {
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

// MARK: STATEMENTS START
fn declaration(self: *Parser) LoxError!*Stmt {
    return self.varStatement();
}

fn varStatement(self: *Parser) LoxError!*Stmt {
    if (self.match(&.{.VAR})) |_| {
        if (self.match(&.{.IDENTIFIER})) |id| {
            return self.varDecl(id);
        } else {
            const err_token = self.previous() orelse self.source[self.current];
            self.parseError(
                LoxError.ExpectedIdentifier,
                "Expected variable name after 'var'",
                err_token,
            );
            return LoxError.ExpectedIdentifier;
        }
    }

    return self.statement();
}

fn varDecl(self: *Parser, id: Token) LoxError!*Stmt {
    var expr: ?*Expr = null;

    if (self.match(&.{.EQUAL})) |_| {
        expr = try self.expression();
    }

    if (self.match(&.{.SEMICOLON})) |_| {} else {
        const err_token = self.previous() orelse self.source[self.current];
        self.parseError(LoxError.ExpectedSemiColon, "Expected ';' after variable declaration", err_token);
        return LoxError.ExpectedSemiColon;
    }

    return self.createStmt(.{ .Variable = .{ .name = id, .value = expr } });
}

fn varDeclNoSemiColon(self: *Parser, id: Token) LoxError!*Stmt {
    var expr: ?*Expr = null;

    if (self.match(&.{.EQUAL})) |_| {
        expr = try self.expression();
    }

    return self.createStmt(.{ .Variable = .{ .name = id, .value = expr } });
}

fn statement(self: *Parser) LoxError!*Stmt {
    if (self.match(&.{
        .IF,    .LEFT_BRACE,
        .PRINT, .WHILE,
        .FOR,
    })) |tok| {
        switch (tok.type) {
            .FOR => return self.forStatement(),
            .IF => return self.ifStatement(),
            .LEFT_BRACE => return self.blockStatement(),
            .PRINT => return self.printStatement(),
            .WHILE => return self.whileStatement(),
            else => unreachable,
        }
    }

    return self.exprStatement();
}

fn exprStatement(self: *Parser) LoxError!*Stmt {
    const expr = try self.expression();

    if (self.consume(.SEMICOLON)) |_| {} else {
        const token = self.previous() orelse self.source[self.current];
        self.parseError(
            LoxError.ExpectedSemiColon,
            "Expected ';' to end an expression statement",
            token,
        );
        return LoxError.ExpectedSemiColon;
    }

    return self.createStmt(.{ .Expression = .{ .value = expr } });
}

fn blockStatement(self: *Parser) LoxError!*Stmt {
    var statements: std.ArrayList(*Stmt) = .empty;

    while (!self.check(.RIGHT_BRACE)) {
        const new_stmt = try self.declaration();
        try statements.append(self.allocator, new_stmt);
    }

    _ = try self.expect(.RIGHT_BRACE, "Expect '}' after block.");

    return self.createStmt(.{ .Block = .{
        .statements = try statements.toOwnedSlice(self.allocator),
        .loc = self.previous() orelse self.source[self.current],
    } });
}

fn forStatement(self: *Parser) LoxError!*Stmt {
    const loc = try self.expect(.LEFT_PAREN, "Expect '(' after 'for'");

    // Parse initializer
    const initializer = if (self.consume(.SEMICOLON)) |_|
        null
    else if (self.consume(.VAR)) |_| blk: {
        const id = try self.expect(.IDENTIFIER, "Expected variable name after 'var'");
        break :blk try self.varDeclNoSemiColon(id);
    } else blk: {
        const expr = try self.expression();
        break :blk try self.createStmt(.{ .Expression = .{ .value = expr } });
    };

    _ = try self.expect(.SEMICOLON, "Expect ';' after for loop initializer");

    // Parse condition
    const condition = if (self.check(.SEMICOLON))
        try self.createLiteralExpr(.{ .Bool = true })
    else
        try self.expression();

    _ = try self.expect(.SEMICOLON, "Expect ';' after loop condition");

    // Parse increment
    const increment = if (self.check(.RIGHT_PAREN))
        null
    else
        try self.expression();

    _ = try self.expect(.RIGHT_PAREN, "Expect ')' after 'for' clauses");

    const body = try self.statement();

    // Create while loop body with proper memory allocation
    const while_body = if (increment) |inc| blk: {
        const increment_stmt = try self.createStmt(.{ .Expression = .{ .value = inc } });

        // Allocate array properly instead of using stack reference
        const combined_stmts = try self.allocator.alloc(*Stmt, 2);
        combined_stmts[0] = body;
        combined_stmts[1] = increment_stmt;

        break :blk try self.createStmt(.{ .Block = .{ .loc = loc, .statements = combined_stmts } });
    } else body;

    const while_stmt = try self.createStmt(.{ .While = .{
        .condition = condition,
        .body = while_body,
    } });

    return if (initializer) |init_stmt| blk: {
        // Same fix here - allocate properly
        const combined_stmts = try self.allocator.alloc(*Stmt, 2);
        combined_stmts[0] = init_stmt;
        combined_stmts[1] = while_stmt;

        break :blk try self.createStmt(.{ .Block = .{ .loc = loc, .statements = combined_stmts } });
    } else while_stmt;
}
fn ifStatement(self: *Parser) LoxError!*Stmt {
    _ = try self.expect(.LEFT_PAREN, "Expect '(' after 'if'");
    const condition = try self.expression();
    errdefer self.freeExpr(condition);
    _ = try self.expect(.RIGHT_PAREN, "Expect ')' after 'if' condition");

    const then_branch = try self.statement();
    const else_branch = if (self.match(&.{.ELSE})) |_| try self.statement() else null;

    return self.createStmt(.{ .If = .{
        .condition = condition,
        .then_branch = then_branch,
        .else_branch = else_branch,
    } });
}

fn printStatement(self: *Parser) LoxError!*Stmt {
    const expr = try self.expression();
    errdefer self.freeExpr(expr);

    if (self.match(&.{.SEMICOLON})) |_| {} else {
        const err_token = self.previous() orelse self.source[self.current];
        self.parseError(
            LoxError.ExpectedSemiColon,
            "Expected ';' to end an print statement",
            err_token,
        );
        return LoxError.ExpectedSemiColon;
    }

    return self.createStmt(.{ .Print = .{ .value = expr } });
}

fn whileStatement(self: *Parser) LoxError!*Stmt {
    _ = try self.expect(.LEFT_PAREN, "Expect '(' after 'if'");
    const condition = try self.expression();
    errdefer self.freeExpr(condition);
    _ = try self.expect(.RIGHT_PAREN, "Expect ')' after 'if' condition");

    const body = try self.statement();

    return self.createStmt(.{ .While = .{
        .condition = condition,
        .body = body,
    } });
}

// MARK: STATEMENTS END

// MARK: EXPRESSION START
fn expression(self: *Parser) LoxError!*Expr {
    return self.assignment();
}

fn assignment(self: *Parser) LoxError!*Expr {
    const expr = try self.logicalOr();
    errdefer self.freeExpr(expr);

    if (self.match(&.{.EQUAL})) |_| {
        _ = self.previous();
        const value = try self.assignment();
        errdefer self.freeExpr(value);

        if (expr.* == .Variable) {
            return self.createExpr(.{
                .Assign = .{
                    .name = expr.Variable.name,
                    .value = value,
                },
            });
        }
        self.parseError(
            LoxError.ExpectedLVal,
            "Expected LVal for assignment",
            self.previous() orelse self.source[self.current - 3],
        );
        return LoxError.ExpectedLVal;
    }

    return expr;
}

fn logicalOr(self: *Parser) LoxError!*Expr {
    return self.parseLogical(.OR, logicalAnd);
}
fn logicalAnd(self: *Parser) LoxError!*Expr {
    return self.parseLogical(.AND, equality);
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
        errdefer self.freeExpr(right);

        return self.createExpr(.{
            .Unary = .{
                .op = op,
                .expr = right,
            },
        });
    }

    return self.primary();
}

fn primary(self: *Parser) LoxError!*Expr {
    const token = self.peek() orelse return LoxError.ExpectedExpression;

    switch (token.type) {
        .TRUE, .FALSE => return self.createLiteralExpr(.{ .Bool = token.literal.bool }),
        .NIL => return self.createLiteralExpr(.{ .Nil = {} }),
        .NUMBER => return self.createLiteralExpr(.{ .Number = token.literal.number }),
        .STRING => return self.createLiteralExpr(.{ .String = token.literal.string }),
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

            return self.createExpr(.{ .Group = .{ .expr = expr } });
        },
        .IDENTIFIER => {
            self.advance();

            return self.createExpr(.{ .Variable = .{ .name = token } });
        },
        else => {
            const err_token = self.previous() orelse self.source[self.current];
            self.parseError(LoxError.ExpectedExpression, "Expected expression", err_token);
            return LoxError.ExpectedExpression;
        },
    }
}
// MARK: EXPRESSION END

// MARK: De-duplicators
fn createStmt(self: *Parser, stmt: Stmt) !*Stmt {
    const node = try self.allocator.create(Stmt);
    node.* = stmt;
    return node;
}

fn createExpr(self: *Parser, expr: Expr) !*Expr {
    const node = try self.allocator.create(Expr);
    node.* = expr;
    return node;
}

fn binaryExpr(self: *Parser, left: *Expr, op: Token, right: *Expr) !*Expr {
    return self.createExpr(.{ .Binary = .{ .left = left, .op = op, .right = right } });
}

fn logicalExpr(self: *Parser, left: *Expr, op: Token, right: *Expr) !*Expr {
    return self.createExpr(.{ .Logical = .{ .left = left, .op = op, .right = right } });
}

fn createLiteralExpr(self: *Parser, expr_val: ExprValue) !*Expr {
    self.advance();
    return self.createExpr(.{ .Literal = .{ .value = expr_val } });
}

fn parseLogical(
    self: *Parser,
    op_type: TokenType,
    next_fn: *const fn (*Parser) LoxError!*Expr,
) LoxError!*Expr {
    var left = try next_fn(self);
    errdefer self.freeExpr(left);

    while (self.match(&.{op_type})) |op| {
        const right = try next_fn(self);
        errdefer self.freeExpr(right);

        left = try self.logicalExpr(left, op, right);
    }
    return left;
}

fn parseBinary(self: *Parser, comptime token_types: []const TokenType, next: fn (*Parser) LoxError!*Expr) LoxError!*Expr {
    var left = try next(self);
    errdefer self.freeExpr(left);

    while (true) {
        const op = self.match(token_types) orelse break;
        const right = try next(self);
        errdefer self.freeExpr(right);

        left = try self.binaryExpr(left, op, right);
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

    return LoxError.ExpectedToken;
}
