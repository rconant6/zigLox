const std = @import("std");
const ArrayList = std.ArrayList;

const lox = @import("../lox.zig");
const Expr = lox.Expr;
const ExprValue = lox.ExprValue;
const LoxError = lox.LoxError;
const Parser = lox.Parser;
const Token = lox.Token;
const TokenType = lox.TokenType;

pub fn expression(p: *Parser) LoxError!*Expr {
    return assignment(p);
}

fn assignment(p: *Parser) LoxError!*Expr {
    const expr = try logicalOr(p);
    errdefer p.freeExpr(expr);

    if (p.match(&.{.EQUAL})) |_| {
        _ = p.previous();
        const value = try assignment(p);
        errdefer p.freeExpr(value);

        if (expr.* == .Variable) {
            return createExpr(p, .{
                .Assign = .{
                    .name = expr.Variable.name,
                    .value = value,
                },
            });
        }
        p.parseError(
            LoxError.ExpectedLVal,
            "Expected LVal for assignment",
            p.previous() orelse p.source[p.current - 3],
        );
        return LoxError.ExpectedLVal;
    }

    return expr;
}

pub fn logicalOr(p: *Parser) LoxError!*Expr {
    return parseLogical(p, .OR, logicalAnd);
}
pub fn logicalAnd(p: *Parser) LoxError!*Expr {
    return parseLogical(p, .AND, equality);
}

pub fn equality(p: *Parser) LoxError!*Expr {
    return parseBinary(p, &.{ .BANG_EQUAL, .EQUAL_EQUAL }, comparison);
}
pub fn comparison(p: *Parser) LoxError!*Expr {
    return parseBinary(p, &.{ .GREATER, .GREATER_EQUAL, .LESS, .LESS_EQUAL }, term);
}
pub fn term(p: *Parser) LoxError!*Expr {
    return parseBinary(p, &.{ .MINUS, .PLUS }, factor);
}
pub fn factor(p: *Parser) LoxError!*Expr {
    return parseBinary(p, &.{ .SLASH, .STAR }, unary);
}

pub fn unary(p: *Parser) LoxError!*Expr {
    if (p.match(&.{ .BANG, .MINUS })) |op| {
        const right = try unary(p);
        errdefer p.freeExpr(right);

        return createExpr(p, .{
            .Unary = .{
                .op = op,
                .expr = right,
            },
        });
    }

    return call(p);
}

pub fn call(p: *Parser) LoxError!*Expr {
    var expr = try primary(p);

    while (p.match(&.{.LEFT_PAREN})) |_| {
        const args = try parseArguments(p);
        errdefer {
            for (args) |arg| p.freeExpr(arg);
            p.allocator.free(args);
        }

        const paren = try p.expect(.RIGHT_PAREN, "Expected ')' after arguments");
        expr = try createExpr(p, .{ .Call = .{
            .callee = expr,
            .paren = paren,
            .args = args,
        } });
    }

    return expr;
}

fn parseArguments(p: *Parser) LoxError![]const *Expr {
    var arguments: ArrayList(*Expr) = .empty;
    errdefer {
        for (arguments.items) |arg| p.freeExpr(arg);
        arguments.deinit(p.allocator);
    }

    if (p.check(.RIGHT_PAREN)) {
        return arguments.toOwnedSlice(p.allocator);
    }

    while (true) {
        if (arguments.items.len >= 255) {
            p.parseError(
                LoxError.TooManyArguments,
                "Cannot have more than 255 arguments.",
                p.previous() orelse p.source[p.current],
            );
            return LoxError.TooManyArguments;
        }

        const arg = try expression(p);
        try arguments.append(p.allocator, arg);

        if (!p.check(.COMMA)) break;
    }

    return arguments.toOwnedSlice(p.allocator);
}

pub fn primary(p: *Parser) LoxError!*Expr {
    const token = p.peek() orelse return LoxError.ExpectedExpression;

    switch (token.type) {
        .TRUE, .FALSE => return createLiteralExpr(p, .{ .Bool = token.literal.bool }),
        .NIL => return createLiteralExpr(p, .{ .Nil = {} }),
        .NUMBER => return createLiteralExpr(p, .{ .Number = token.literal.number }),
        .STRING => return createLiteralExpr(p, .{ .String = token.literal.string }),
        .LEFT_PAREN => {
            p.advance();

            const expr = try p.expression();
            errdefer p.freeExpr(expr);

            if ((p.match(&.{.RIGHT_PAREN}))) |_| {} else {
                const err_token = p.previous() orelse p.source[p.current];
                p.parseError(
                    LoxError.ExpectedClosingParen,
                    "Expected ')' to close '('",
                    err_token,
                );
            }

            return createExpr(p, .{ .Group = .{ .expr = expr } });
        },
        .IDENTIFIER => {
            p.advance();

            return createExpr(p, .{ .Variable = .{ .name = token } });
        },
        else => {
            const err_token = p.previous() orelse p.source[p.current];
            p.parseError(LoxError.ExpectedExpression, "Expected expression", err_token);
            return LoxError.ExpectedExpression;
        },
    }
}

fn createExpr(p: *Parser, expr: Expr) !*Expr {
    const node = try p.allocator.create(Expr);
    node.* = expr;
    return node;
}

fn binaryExpr(p: *Parser, left: *Expr, op: Token, right: *Expr) !*Expr {
    return createExpr(p, .{ .Binary = .{ .left = left, .op = op, .right = right } });
}

fn logicalExpr(p: *Parser, left: *Expr, op: Token, right: *Expr) !*Expr {
    return createExpr(p, .{ .Logical = .{ .left = left, .op = op, .right = right } });
}

pub fn createLiteralExpr(p: *Parser, expr_val: ExprValue) !*Expr {
    p.advance();
    return createExpr(p, .{ .Literal = .{ .value = expr_val } });
}

fn parseLogical(
    p: *Parser,
    op_type: TokenType,
    next_fn: *const fn (*Parser) LoxError!*Expr,
) LoxError!*Expr {
    var left = try next_fn(p);
    errdefer p.freeExpr(left);

    while (p.match(&.{op_type})) |op| {
        const right = try next_fn(p);
        errdefer p.freeExpr(right);

        left = try logicalExpr(p, left, op, right);
    }
    return left;
}

fn parseBinary(p: *Parser, comptime token_types: []const TokenType, next: fn (*Parser) LoxError!*Expr) LoxError!*Expr {
    var left = try next(p);
    errdefer p.freeExpr(left);

    while (true) {
        const op = p.match(token_types) orelse break;
        const right = try next(p);
        errdefer p.freeExpr(right);

        left = try binaryExpr(p, left, op, right);
    }
    return left;
}
