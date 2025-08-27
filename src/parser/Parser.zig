pub const Parser = @This();

const std = @import("std");
const ArrayList = std.ArrayList;
const lox = @import("../lox.zig");
const DiagnosticsReporter = lox.DiagnosticReporter;
const ErrorContext = lox.ErrorContext;
const ExprIdx = lox.ExprIdx;
const LoxError = lox.LoxError;
const ParseType = lox.ParseType;
const Token = lox.Token;
const TokenType = Token.Tag;
const StmtIdx = lox.StmtIdx;

gpa: std.mem.Allocator,
src: []const Token = undefined,
code: []const u8 = undefined,
expressions: std.ArrayList(Expr),
statements: std.ArrayList(Stmt),
diagnostics: *DiagnosticsReporter,
current: usize,
panic_mode: bool,

pub fn init(
    gpa: std.mem.Allocator,
    diagnostic: *DiagnosticsReporter,
    tokens: []const Token,
    src_code: []const u8,
) Parser {
    return .{
        .gpa = gpa,
        .src = tokens,
        .code = src_code,
        .expressions = .empty,
        .statements = .empty,
        .diagnostics = diagnostic,
        .current = 0,
        .panic_mode = false,
    };
}

pub fn deinit(self: *Parser) void {
    self.expressions.deinit(self.gpa);
    self.statements.deinit(self.gpa);
}

pub fn parse(self: *Parser, tokens: []const Token) LoxError!Stmt {
    self.src = tokens; // REPL support
    self.panic_mode = false;

    var statements: ArrayList(StmtIdx) = .empty;
    errdefer statements.deinit(self.gpa);

    while (self.peek()) |token| {
        if (token.tag == .Eof) break;
        const stmt_idx = self.program() catch |err| {
            std.log.debug("Parse error: {}", .{err});

            if (err == LoxError.ExpectedSemiColon or
                err == LoxError.ExpectedExpression or
                err == LoxError.ExpectedClosingParen)
            {
                self.synchronize();
                continue;
            } else {
                return err;
            }
        };
        try statements.append(self.gpa, stmt_idx);
    }
    const block_stmt = Stmt{
        .Block = .{
            .statements = try statements.toOwnedSlice(self.gpa),
            .loc = self.src[0],
        },
    };

    return block_stmt;
}

// MARK: Error Handling
pub fn parseError(self: *Parser, err: LoxError, message: []const u8, token: Token) void {
    if (self.panic_mode) return;

    self.panic_mode = true;
    self.diagnostics.reportError(ErrorContext.init(message, err, token));
}

pub fn synchronize(self: *Parser) void {
    self.panic_mode = false;

    while (self.peek()) |token| {
        if (self.previous()) |prev| {
            if (prev.tag == .SemiColon) return;
        }

        switch (token.tag) {
            .Class, .Fun, .Var, .For, .If, .While, .Print, .Return => return,
            else => {},
        }
        self.advance();
    }
}

// MARK: Helpers
pub fn previous(self: *Parser) ?Token {
    if (self.current <= 0) return null;
    return self.src[self.current];
}

pub fn peek(self: *Parser) ?Token {
    if (self.current >= self.src
        .len) return null;
    return self.src[self.current];
}

pub fn advance(self: *Parser) void {
    if (self.current < self.src
        .len) self.current += 1;
}

pub fn check(self: *Parser, t_type: TokenType) bool {
    if (self.current >= self.src
        .len) return false;
    const curr_tok = self.src[self.current];
    return curr_tok.tag == t_type;
}

pub fn match(self: *Parser, types: []const TokenType) ?Token {
    const token = self.peek() orelse return null;

    for (types) |t| {
        if (token.tag == t) {
            self.advance();
            return token;
        }
    }

    return null;
}

pub fn consume(self: *Parser, t_type: TokenType) ?Token {
    const token = self.peek() orelse return null;
    if (token.tag == t_type) {
        self.advance();
        return token;
    } else return null;
}

pub fn expect(self: *Parser, t_type: TokenType, message: []const u8) !Token {
    if (self.consume(t_type)) |token|
        return token;
    const token = self.peek() orelse self.src[self.current - 1];
    self.parseError(LoxError.ExpectedToken, message, token);

    return LoxError.ExpectedToken;
}

// MARK: Statements
pub const Stmt = union(enum) {
    Block: ParseType(struct {
        statements: []const StmtIdx,
        loc: Token,
    }),
    Expression: ParseType(struct {
        value: ExprIdx,
    }),
    Function: ParseType(struct {
        name: Token,
        params: []Token,
        body: StmtIdx,
    }),
    If: ParseType(struct {
        condition: ExprIdx,
        then_branch: StmtIdx,
        else_branch: ?StmtIdx,
    }),
    Print: ParseType(struct {
        value: ExprIdx,
    }),
    Return: ParseType(struct {
        keyword: Token,
        value: ?ExprIdx,
    }),
    Variable: ParseType(struct {
        name: Token,
        value: ?ExprIdx,
    }),
    While: ParseType(struct {
        condition: ExprIdx,
        body: StmtIdx,
    }),
};
const StatementParser = union(enum) {
    simple: struct {
        token_type: TokenType,
        parser_fn: *const fn (*Parser) LoxError!StmtIdx,
    },
    with_string: struct {
        token_type: TokenType,
        parser_fn: *const fn (*Parser, []const u8) LoxError!StmtIdx,
    },
};

const statement_parsers = [_]StatementParser{
    .{ .simple = .{ .token_type = .For, .parser_fn = forStatement } },
    .{ .simple = .{ .token_type = .If, .parser_fn = ifStatement } },
    .{ .simple = .{ .token_type = .LeftBrace, .parser_fn = blockStatement } },
    .{ .simple = .{ .token_type = .Return, .parser_fn = returnStatement } },
    .{ .simple = .{ .token_type = .Print, .parser_fn = printStatement } },
    .{ .simple = .{ .token_type = .While, .parser_fn = whileStatement } },

    .{ .with_string = .{ .token_type = .Fun, .parser_fn = functionStatement } },
};

pub fn program(self: *Parser) LoxError!StmtIdx {
    return self.declaration();
}

fn declaration(self: *Parser) LoxError!StmtIdx {
    return self.varStatement();
}

fn varStatement(self: *Parser) LoxError!StmtIdx {
    if (self.match(&.{.Var})) |_| {
        if (self.match(&.{.Identifier})) |id| {
            return self.varDecl(id);
        } else {
            const err_token = self.previous() orelse self.src[self.current];
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

fn varDecl(self: *Parser, id: Token) LoxError!StmtIdx {
    var exprIdx: ?ExprIdx = null;

    if (self.match(&.{.Equal})) |_| {
        exprIdx = try self.expression();
    }

    if (self.match(&.{.SemiColon})) |_| {} else {
        const err_token = self.previous() orelse self.src[self.current];
        self.parseError(LoxError.ExpectedSemiColon, "Expected ';' after variable declaration", err_token);
        return LoxError.ExpectedSemiColon;
    }

    return self.createStmt(.{ .Variable = .{ .name = id, .value = exprIdx } });
}

fn varDeclNoSemiColon(self: *Parser, id: Token) LoxError!StmtIdx {
    var exprIdx: ?ExprIdx = null;

    if (self.match(&.{.Equal})) |_| {
        exprIdx = try self.expression();
    }

    return self.createStmt(.{ .Variable = .{ .name = id, .value = exprIdx } });
}

fn statement(self: *Parser) LoxError!StmtIdx {
    if (self.peek()) |token| {
        for (statement_parsers) |parser| {
            switch (parser) {
                .simple => |simple_parser| {
                    if (token.tag == simple_parser.token_type) {
                        self.advance();
                        return simple_parser.parser_fn(self);
                    }
                },
                .with_string => |string_parser| {
                    if (token.tag == string_parser.token_type) {
                        self.advance();
                        return string_parser.parser_fn(self, "function"); // or whatever string you need
                    }
                },
            }
        }
    }
    return self.exprStatement();
}

fn exprStatement(self: *Parser) LoxError!StmtIdx {
    const expr = try self.expression();

    if (self.consume(.SemiColon)) |_| {} else {
        const token = self.previous() orelse self.src[self.current];
        self.parseError(
            LoxError.ExpectedSemiColon,
            "Expected ';' to end an expression statement",
            token,
        );
        return LoxError.ExpectedSemiColon;
    }

    return self.createStmt(.{ .Expression = .{ .value = expr } });
}

fn blockStatement(self: *Parser) LoxError!StmtIdx {
    var statements: ArrayList(StmtIdx) = .empty;

    while (!self.check(.RightBrace)) {
        const new_stmt = try self.declaration();
        try statements.append(self.gpa, new_stmt);
    }

    _ = try self.expect(.RightBrace, "Expect '}' after block.");

    return self.createStmt(.{ .Block = .{
        .statements = try statements.toOwnedSlice(self.gpa),
        .loc = self.previous() orelse self.src[self.current],
    } });
}

fn forStatement(self: *Parser) LoxError!StmtIdx {
    const loc = try self.expect(.LeftParen, "Expect '(' after 'for'");

    const initializer = if (self.consume(.SemiColon)) |_|
        null
    else if (self.consume(.Var)) |_| blk: {
        const id = try self.expect(.Identifier, "Expected variable name after 'var'");
        break :blk try self.varDeclNoSemiColon(id);
    } else blk: {
        const expr = try self.expression();
        break :blk try self.createStmt(.{ .Expression = .{ .value = expr } });
    };

    _ = try self.expect(.SemiColon, "Expect ';' after for loop initializer");

    const condition = if (self.check(.SemiColon))
        try self.createLiteralExpr(.{ .Bool = true })
    else
        try self.expression();

    _ = try self.expect(.SemiColon, "Expect ';' after loop condition");

    const increment = if (self.check(.RightParen))
        null
    else
        try self.expression();

    _ = try self.expect(.RightParen, "Expect ')' after 'for' clauses");

    const body = try self.statement();

    const while_body = if (increment) |inc| blk: {
        const increment_stmt = try self.createStmt(.{
            .Expression = .{ .value = inc },
        });

        const combined_stmts = try self.gpa.alloc(StmtIdx, 2);
        errdefer self.gpa.free(combined_stmts);
        combined_stmts[0] = body;
        combined_stmts[1] = increment_stmt;

        break :blk try self.createStmt(.{
            .Block = .{ .loc = loc, .statements = combined_stmts },
        });
    } else body;

    const while_stmt = try self.createStmt(.{ .While = .{
        .condition = condition,
        .body = while_body,
    } });

    return if (initializer) |init_stmt| blk: {
        const combined_stmts = try self.gpa.alloc(StmtIdx, 2);
        errdefer self.gpa.free(combined_stmts);
        combined_stmts[0] = init_stmt;
        combined_stmts[1] = while_stmt;

        break :blk try self.createStmt(.{
            .Block = .{ .loc = loc, .statements = combined_stmts },
        });
    } else while_stmt;
}

fn ifStatement(self: *Parser) LoxError!StmtIdx {
    _ = try self.expect(.LeftParen, "Expect '(' after 'if'");
    const condition = try self.expression();
    _ = try self.expect(.RightParen, "Expect ')' after 'if' condition");

    const then_branch = try self.statement();
    const else_branch = if (self.match(&.{.Else})) |_| try self.statement() else null;

    return self.createStmt(.{ .If = .{
        .condition = condition,
        .then_branch = then_branch,
        .else_branch = else_branch,
    } });
}

fn functionStatement(self: *Parser, kind: []const u8) LoxError!StmtIdx {
    // TODO: Move to LoxError
    const msg1 = try std.fmt.allocPrint(self.gpa, "Expect {s} name", .{kind});
    const msg2 = try std.fmt.allocPrint(self.gpa, "Expect '(' after {s} name", .{kind});
    const msg3 = try std.fmt.allocPrint(self.gpa, "Expect {{ before {s} body", .{kind});
    errdefer {
        self.gpa.free(msg1);
        self.gpa.free(msg2);
        self.gpa.free(msg3);
    }

    const name = try self.expect(.Identifier, msg1);
    _ = try self.expect(.LeftParen, msg2);

    var params: ArrayList(Token) = .empty;
    errdefer params.deinit(self.gpa);

    while (true) {
        if (self.check(.RightParen)) {
            break;
        }

        if (params.items.len >= 255) {
            self.parseError(
                LoxError.TooManyArguments,
                "Cannot have more than 255 parameters.",
                self.previous() orelse self.src[self.current],
            );
            return LoxError.TooManyArguments; // TODO: rename/add TooManyParameters
        }

        const param = try self.expect(.Identifier, "Expect parameter name");
        try params.append(self.gpa, param);

        if (self.consume(.Comma)) |_| continue else break;
    }

    _ = try self.expect(.RightParen, "Expect ')' after parameters");

    _ = try self.expect(.LeftBrace, msg3);
    const body = try self.blockStatement();

    return self.createStmt(.{
        .Function = .{
            .name = name,
            .params = try params.toOwnedSlice(self.gpa),
            .body = body,
        },
    });
}

fn printStatement(self: *Parser) LoxError!StmtIdx {
    const exprIdx = try self.expression();

    if (self.match(&.{.SemiColon})) |_| {} else {
        const err_token = self.previous() orelse self.src[self.current];
        self.parseError(
            LoxError.ExpectedSemiColon,
            "Expected ';' to end an print statement",
            err_token,
        );
        return LoxError.ExpectedSemiColon;
    }

    return self.createStmt(.{ .Print = .{ .value = exprIdx } });
}

fn returnStatement(self: *Parser) LoxError!StmtIdx {
    const keyword = self.previous() orelse unreachable; // can only get here /w .RETURN
    // std.debug.assert(keyword.type == .RETURN);

    const value = if (!self.check(.SemiColon))
        try self.expression()
    else
        null;

    _ = try self.expect(.SemiColon, "Return statements expect ';' at end");

    return self.createStmt(.{ .Return = .{
        .keyword = keyword,
        .value = value,
    } });
}

fn whileStatement(self: *Parser) LoxError!StmtIdx {
    _ = try self.expect(.LeftParen, "Expect '(' after 'if'");
    const conditionIdx = try self.expression();
    _ = try self.expect(.RightParen, "Expect ')' after 'if' condition");

    const body = try self.statement();

    return self.createStmt(.{ .While = .{
        .condition = conditionIdx,
        .body = body,
    } });
}

fn createStmt(self: *Parser, stmt: Stmt) LoxError!StmtIdx {
    const idx = self.statements.items.len;
    const newPtr = try self.statements.addOne(self.gpa);
    newPtr.* = stmt;
    return @intCast(idx);
}

// MARK Expressions
pub const ExprValue = union(enum) {
    String: []const u8,
    Number: f64,
    Bool: bool,
    Nil: void,

    pub fn format(val: ExprValue, w: *std.Io.Writer) !void {
        switch (val) {
            .String => |s| try w.print("{s}", .{s}),
            .Number => |n| try w.print("{d}", .{n}),
            .Bool => |b| try w.print("{}", .{b}),
            .Nil => try w.print("nil"),
        }
    }
};

pub const Expr = union(enum) {
    Assign: ParseType(struct {
        name: Token,
        value: ExprIdx,
    }),
    Binary: ParseType(struct {
        left: ExprIdx,
        op: Token,
        right: ExprIdx,
    }),
    Call: ParseType(struct {
        callee: ExprIdx,
        paren: Token,
        args: []const ExprIdx,
    }),
    Group: ParseType(struct {
        expr: ExprIdx,
    }),
    Literal: ParseType(struct {
        value: ExprValue,
    }),
    Logical: ParseType(struct {
        left: ExprIdx,
        op: Token,
        right: ExprIdx,
    }),
    Unary: ParseType(struct {
        op: Token,
        expr: ExprIdx,
    }),
    Variable: ParseType(struct {
        name: Token,
    }),
};

pub fn expression(self: *Parser) LoxError!ExprIdx {
    return self.assignment();
}

fn assignment(self: *Parser) LoxError!ExprIdx {
    const eIdx = try self.logicalOr();
    const expr = self.expressions.items[eIdx];

    if (self.match(&.{.Equal})) |_| {
        _ = self.previous();
        const valueIdx = try self.assignment();

        if (expr == .Variable) {
            return self.createExpr(.{
                .Assign = .{
                    .name = expr.Variable.name,
                    .value = valueIdx,
                },
            });
        }
        self.parseError(
            LoxError.ExpectedLVal,
            "Expected LVal for assignment",
            self.previous() orelse self.src[self.current - 3],
        );
        return LoxError.ExpectedLVal;
    }

    return eIdx;
}

pub fn logicalOr(self: *Parser) LoxError!ExprIdx {
    return self.parseLogical(.Or, logicalAnd);
}
pub fn logicalAnd(self: *Parser) LoxError!ExprIdx {
    return self.parseLogical(.And, equality);
}

pub fn equality(self: *Parser) LoxError!ExprIdx {
    return self.parseBinary(&.{ .BangEqual, .EqualEqual }, comparison);
}
pub fn comparison(self: *Parser) LoxError!ExprIdx {
    return self.parseBinary(&.{ .Greater, .GreaterEqual, .Less, .LessEqual }, term);
}
pub fn term(self: *Parser) LoxError!ExprIdx {
    return self.parseBinary(&.{ .Minus, .Plus }, factor);
}
pub fn factor(self: *Parser) LoxError!ExprIdx {
    return self.parseBinary(&.{ .Slash, .Star }, unary);
}

pub fn unary(self: *Parser) LoxError!ExprIdx {
    if (self.match(&.{ .Bang, .Minus })) |op| {
        const rightIdx = try self.unary();

        return self.createExpr(.{
            .Unary = .{
                .op = op,
                .expr = rightIdx,
            },
        });
    }

    return self.call();
}

pub fn call(self: *Parser) LoxError!ExprIdx {
    var exprIdx = try self.primary();

    while (self.match(&.{.LeftParen})) |_| {
        const argsIdxs = try self.parseArguments();

        const paren = try self.expect(.RightParen, "Expected ')' after arguments");
        exprIdx = try self.createExpr(.{ .Call = .{
            .callee = exprIdx,
            .paren = paren,
            .args = argsIdxs,
        } });
    }

    return exprIdx;
}

fn parseArguments(self: *Parser) LoxError![]const ExprIdx {
    var arguments: ArrayList(ExprIdx) = .empty;
    errdefer arguments.deinit(self.gpa);

    if (self.check(.RightParen)) {
        return arguments.toOwnedSlice(self.gpa);
    }

    while (true) {
        if (arguments.items.len >= 255) {
            self.parseError(
                LoxError.TooManyArguments,
                "Cannot have more than 255 arguments.",
                self.previous() orelse self.src[self.current],
            );
            return LoxError.TooManyArguments;
        }

        const argIdx = try self.expression();
        try arguments.append(self.gpa, argIdx);

        if (self.consume(.Comma)) |_| continue else break;
    }

    return arguments.toOwnedSlice(self.gpa);
}

pub fn primary(self: *Parser) LoxError!ExprIdx {
    const token = self.peek() orelse return LoxError.ExpectedExpression;

    switch (token.tag) {
        .True, .False => return self.createLiteralExpr(.{ .Bool = token.literalValue(self.code).bool }),
        .Nil => return self.createLiteralExpr(.{ .Nil = {} }),
        .Number => return self.createLiteralExpr(.{ .Number = token.literalValue(self.code).number }),
        .String => return self.createLiteralExpr(.{ .String = token.literalValue(self.code).string }),
        .LeftParen => {
            self.advance();

            const exprIdx = try self.expression();

            if ((self.match(&.{.RightParen}))) |_| {} else {
                const err_token = self.previous() orelse self.src[self.current];
                self.parseError(
                    LoxError.ExpectedClosingParen,
                    "Expected ')' to close '('",
                    err_token,
                );
            }

            return self.createExpr(.{ .Group = .{ .expr = exprIdx } });
        },
        .Identifier => {
            self.advance();

            return self.createExpr(.{ .Variable = .{ .name = token } });
        },
        else => {
            const err_token = self.previous() orelse self.src[self.current];
            self.parseError(LoxError.ExpectedExpression, "Expected expression", err_token);
            return LoxError.ExpectedExpression;
        },
    }
}

fn createExpr(self: *Parser, expr: Expr) !ExprIdx {
    const idx = self.expressions.items.len;
    const newPtr = try self.expressions.addOne(self.gpa);
    newPtr.* = expr;
    return @intCast(idx);
}

fn binaryExpr(self: *Parser, left: ExprIdx, op: Token, right: ExprIdx) !ExprIdx {
    return self.createExpr(.{ .Binary = .{ .left = left, .op = op, .right = right } });
}

fn logicalExpr(self: *Parser, left: ExprIdx, op: Token, right: ExprIdx) !ExprIdx {
    return self.createExpr(.{ .Logical = .{ .left = left, .op = op, .right = right } });
}

pub fn createLiteralExpr(self: *Parser, expr_val: ExprValue) !ExprIdx {
    self.advance();
    return self.createExpr(.{ .Literal = .{ .value = expr_val } });
}

fn parseLogical(
    self: *Parser,
    op_type: TokenType,
    next_fn: *const fn (*Parser) LoxError!ExprIdx,
) LoxError!ExprIdx {
    var leftIdx = try next_fn(self);

    while (self.match(&.{op_type})) |op| {
        const rightIdx = try next_fn(self);

        leftIdx = try self.logicalExpr(leftIdx, op, rightIdx);
    }
    return leftIdx;
}

fn parseBinary(
    self: *Parser,
    comptime token_types: []const TokenType,
    next: fn (*Parser) LoxError!ExprIdx,
) LoxError!ExprIdx {
    var leftIdx = try next(self);

    while (true) {
        const op = self.match(token_types) orelse break;
        const rightIdx = try next(self);

        leftIdx = try self.binaryExpr(leftIdx, op, rightIdx);
    }
    return leftIdx;
}
