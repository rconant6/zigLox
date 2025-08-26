const std = @import("std");
const ArrayList = std.ArrayList;

const lox = @import("../lox.zig");
const Expr = lox.Expr;
const ExprValue = lox.ExprValue;
const LoxError = lox.LoxError;
const Parser = lox.Parser;
const Stmt = lox.Stmt;
const Token = lox.Token;
const TokenType = lox.TokenType;

const StatementParser = union(enum) {
    simple: struct {
        token_type: TokenType,
        parser_fn: *const fn (*Parser) LoxError!*Stmt,
    },
    with_string: struct {
        token_type: TokenType,
        parser_fn: *const fn (*Parser, []const u8) LoxError!*Stmt,
    },
};

const statement_parsers = [_]StatementParser{
    .{ .simple = .{ .token_type = .IF, .parser_fn = ifStatement } },
    .{ .simple = .{ .token_type = .LEFT_BRACE, .parser_fn = blockStatement } },
    .{ .simple = .{ .token_type = .PRINT, .parser_fn = printStatement } },
    .{ .simple = .{ .token_type = .WHILE, .parser_fn = whileStatement } },
    .{ .simple = .{ .token_type = .FOR, .parser_fn = forStatement } },
    .{ .with_string = .{ .token_type = .FUN, .parser_fn = functionStatement } },
};

pub fn program(p: *Parser) LoxError!*Stmt {
    return declaration(p);
}

fn declaration(p: *Parser) LoxError!*Stmt {
    return varStatement(p);
}

fn varStatement(p: *Parser) LoxError!*Stmt {
    if (p.match(&.{.VAR})) |_| {
        if (p.match(&.{.IDENTIFIER})) |id| {
            return varDecl(p, id);
        } else {
            const err_token = p.previous() orelse p.source[p.current];
            p.parseError(
                LoxError.ExpectedIdentifier,
                "Expected variable name after 'var'",
                err_token,
            );
            return LoxError.ExpectedIdentifier;
        }
    }

    return statement(p);
}

fn varDecl(p: *Parser, id: Token) LoxError!*Stmt {
    var expr: ?*Expr = null;

    if (p.match(&.{.EQUAL})) |_| {
        expr = try p.expression();
    }

    if (p.match(&.{.SEMICOLON})) |_| {} else {
        const err_token = p.previous() orelse p.source[p.current];
        p.parseError(LoxError.ExpectedSemiColon, "Expected ';' after variable declaration", err_token);
        return LoxError.ExpectedSemiColon;
    }

    return createStmt(p, .{ .Variable = .{ .name = id, .value = expr } });
}

fn varDeclNoSemiColon(p: *Parser, id: Token) LoxError!*Stmt {
    var expr: ?*Expr = null;

    if (p.match(&.{.EQUAL})) |_| {
        expr = try p.expression();
    }

    return createStmt(p, .{ .Variable = .{ .name = id, .value = expr } });
}

fn statement(p: *Parser) LoxError!*Stmt {
    if (p.peek()) |token| {
        for (statement_parsers) |parser| {
            switch (parser) {
                .simple => |simple_parser| {
                    if (token.type == simple_parser.token_type) {
                        p.advance();
                        return simple_parser.parser_fn(p);
                    }
                },
                .with_string => |string_parser| {
                    if (token.type == string_parser.token_type) {
                        p.advance();
                        return string_parser.parser_fn(p, "function"); // or whatever string you need
                    }
                },
            }
        }
    }
    return exprStatement(p);
}

fn exprStatement(p: *Parser) LoxError!*Stmt {
    const expr = try p.expression();

    if (p.consume(.SEMICOLON)) |_| {} else {
        const token = p.previous() orelse p.source[p.current];
        p.parseError(
            LoxError.ExpectedSemiColon,
            "Expected ';' to end an expression statement",
            token,
        );
        return LoxError.ExpectedSemiColon;
    }

    return createStmt(p, .{ .Expression = .{ .value = expr } });
}

fn blockStatement(p: *Parser) LoxError!*Stmt {
    var statements: ArrayList(*Stmt) = .empty;

    while (!p.check(.RIGHT_BRACE)) {
        const new_stmt = try declaration(p);
        try statements.append(p.allocator, new_stmt);
    }

    _ = try p.expect(.RIGHT_BRACE, "Expect '}' after block.");

    return createStmt(p, .{ .Block = .{
        .statements = try statements.toOwnedSlice(p.allocator),
        .loc = p.previous() orelse p.source[p.current],
    } });
}

fn forStatement(p: *Parser) LoxError!*Stmt {
    const loc = try p.expect(.LEFT_PAREN, "Expect '(' after 'for'");

    const initializer = if (p.consume(.SEMICOLON)) |_|
        null
    else if (p.consume(.VAR)) |_| blk: {
        const id = try p.expect(.IDENTIFIER, "Expected variable name after 'var'");
        break :blk try varDeclNoSemiColon(p, id);
    } else blk: {
        const expr = try p.expression();
        break :blk try createStmt(p, .{ .Expression = .{ .value = expr } });
    };

    _ = try p.expect(.SEMICOLON, "Expect ';' after for loop initializer");

    const condition = if (p.check(.SEMICOLON))
        try createLiteralExpr(p, .{ .Bool = true })
    else
        try p.expression();

    _ = try p.expect(.SEMICOLON, "Expect ';' after loop condition");

    const increment = if (p.check(.RIGHT_PAREN))
        null
    else
        try p.expression();

    _ = try p.expect(.RIGHT_PAREN, "Expect ')' after 'for' clauses");

    const body = try statement(p);

    const while_body = if (increment) |inc| blk: {
        const increment_stmt = try createStmt(p, .{
            .Expression = .{ .value = inc },
        });
        errdefer p.allocator.destroy(increment_stmt);

        const combined_stmts = try p.allocator.alloc(*Stmt, 2);
        errdefer p.allocator.free(combined_stmts);
        combined_stmts[0] = body;
        combined_stmts[1] = increment_stmt;

        break :blk try createStmt(p, .{
            .Block = .{ .loc = loc, .statements = combined_stmts },
        });
    } else body;

    const while_stmt = try createStmt(p, .{ .While = .{
        .condition = condition,
        .body = while_body,
    } });

    return if (initializer) |init_stmt| blk: {
        const combined_stmts = try p.allocator.alloc(*Stmt, 2);
        errdefer p.allocator.free(combined_stmts);
        combined_stmts[0] = init_stmt;
        combined_stmts[1] = while_stmt;

        break :blk try createStmt(p, .{
            .Block = .{ .loc = loc, .statements = combined_stmts },
        });
    } else while_stmt;
}

fn ifStatement(p: *Parser) LoxError!*Stmt {
    _ = try p.expect(.LEFT_PAREN, "Expect '(' after 'if'");
    const condition = try p.expression();
    errdefer p.freeExpr(condition);
    _ = try p.expect(.RIGHT_PAREN, "Expect ')' after 'if' condition");

    const then_branch = try statement(p);
    const else_branch = if (p.match(&.{.ELSE})) |_| try statement(p) else null;

    return createStmt(p, .{ .If = .{
        .condition = condition,
        .then_branch = then_branch,
        .else_branch = else_branch,
    } });
}

fn functionStatement(p: *Parser, kind: []const u8) LoxError!*Stmt {
    // TODO: Move to LoxError
    const msg1 = try std.fmt.allocPrint(p.allocator, "Expect {s} name", .{kind});
    const msg2 = try std.fmt.allocPrint(p.allocator, "Expect '(' after {s} name", .{kind});
    const msg3 = try std.fmt.allocPrint(p.allocator, "Expect {{ before {s} body", .{kind});

    const name = try p.expect(.IDENTIFIER, msg1);
    _ = try p.expect(.LEFT_PAREN, msg2);

    var params: ArrayList(Token) = .empty;
    errdefer {
        params.deinit(p.allocator);
    }
    while (true) {
        if (p.check(.RIGHT_PAREN)) {
            break;
        }

        if (params.items.len >= 255) {
            p.parseError(
                LoxError.TooManyArguments,
                "Cannot have more than 255 parameters.",
                p.previous() orelse p.source[p.current],
            );
            return LoxError.TooManyArguments; // TODO: rename/add TooManyParameters
        }

        const param = try p.expect(.IDENTIFIER, "Expect parameter name");
        try params.append(p.allocator, param);

        if (p.consume(.COMMA)) |_| continue else break;
    }

    _ = try p.expect(.RIGHT_PAREN, "Expect ')' after parameters");

    _ = try p.expect(.LEFT_BRACE, msg3);
    const body = try blockStatement(p);
    std.debug.assert(std.meta.activeTag(body.*) == .Block);

    return createStmt(p, .{
        .Function = .{
            .name = name,
            .params = try params.toOwnedSlice(p.allocator),
            .body = body,
        },
    });
}

fn printStatement(p: *Parser) LoxError!*Stmt {
    const expr = try p.expression();
    errdefer p.freeExpr(expr);

    if (p.match(&.{.SEMICOLON})) |_| {} else {
        const err_token = p.previous() orelse p.source[p.current];
        p.parseError(
            LoxError.ExpectedSemiColon,
            "Expected ';' to end an print statement",
            err_token,
        );
        return LoxError.ExpectedSemiColon;
    }

    return createStmt(p, .{ .Print = .{ .value = expr } });
}

fn whileStatement(p: *Parser) LoxError!*Stmt {
    _ = try p.expect(.LEFT_PAREN, "Expect '(' after 'if'");
    const condition = try p.expression();
    errdefer p.freeExpr(condition);
    _ = try p.expect(.RIGHT_PAREN, "Expect ')' after 'if' condition");

    const body = try statement(p);

    return createStmt(p, .{ .While = .{
        .condition = condition,
        .body = body,
    } });
}

fn createStmt(p: *Parser, stmt: Stmt) !*Stmt {
    const node = try p.allocator.create(Stmt);
    node.* = stmt;
    return node;
}

pub fn createLiteralExpr(p: *Parser, expr_val: ExprValue) !*Expr {
    p.advance();
    const node = try p.allocator.create(Expr);
    node.* = .{ .Literal = .{ .value = expr_val } };
    return node;
}
