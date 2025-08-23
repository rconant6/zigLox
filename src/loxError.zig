const std = @import("std");

const lox = @import("lox.zig");
const Location = lox.Location;
const Token = lox.Token;

pub const LoxError = error{
    // Scanning Errors
    UnterminatedString,
    UnexpectedCharacter,
    // Parsing Errors
    ExpectedToken,
    ExpectedExpression,
    ExpectedSemiColon,
    ExpectedClosingParen,
    ExpectedOpeningParen,
    ExpectedClosingBrace,
    ExpectedIdentifier,
    ExpectedBlockStatement,
    ExpectedLVal,
    TooManyArguments,
    UnexpectedToken,
    // Semantic Errors
    UndefinedVariable,
    TypeMismatch,
    DivisionByZero,
    InvalidOperands,
    NotCallable,
    WrongNumberOfArguments,

    // Function Types
    Return, // Used for function return propagation
    Unimplemented,
};

pub const ReturnValue = error{
    Return,
};

pub const ErrorContext = struct {
    message: []const u8,
    token: ?Token = null,
    location: ?Location = null,
    sourceCode: ?[]const u8 = null,
    errorType: LoxError,

    pub fn init(message: []const u8, errType: LoxError) ErrorContext {
        return .{
            .message = message,
            .errorType = errType,
        };
    }

    pub fn withToken(self: ErrorContext, token: Token) ErrorContext {
        var copy = self;
        copy.token = token;
        copy.line = token.loc.line;
        copy.column = token.loc.col;
        return copy;
    }

    pub fn withLocation(self: ErrorContext, loc: Location) ErrorContext {
        var copy = self;
        copy.location = loc;
        return copy;
    }

    pub fn withSourceContext(self: ErrorContext, source: []const u8) ErrorContext {
        var copy = self;
        copy.sourceCode = source;
        return copy;
    }

    pub fn format(ctx: ErrorContext, w: *std.Io.Writer) !void {
        try w.print("Error({t}): {s}", .{ ctx.errorType, ctx.message });
        if (ctx.location) |loc| {
            try w.print(" at {f}", .{loc});
        }
        if (ctx.token) |token| {
            try w.print(" near '{f}'", .{token});
        }
    }
};
