const std = @import("std");

const lox = @import("lox.zig");
const Location = lox.Location;
const Token = lox.Token;

pub const LoxError = error{
    // Scanning Errors
    UnexpectedCharacter,
    UnterminatedString,
    // Parsing Errors
    ExpectedBlockStatement,
    ExpectedClosingBrace,
    ExpectedClosingParen,
    ExpectedExpression,
    ExpectedIdentifier,
    ExpectedLVal,
    ExpectedOpeningParen,
    ExpectedSemiColon,
    ExpectedToken,
    TooManyArguments,
    UnexpectedToken,
    // Semantic Errors
    DivisionByZero,
    InvalidBinaryOperand,
    InvalidOperands,
    NotCallable,
    TypeMismatch,
    UndefinedVariable,
    WrongNumberOfArguments,
    // System Errors
    OutOfMemory,
    WriteFailed,
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
        copy.location = token.loc;
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

    pub fn format(ctx: ErrorContext, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("Error({t}): {s}", .{ ctx.errorType, ctx.message });
        if (ctx.location) |loc| {
            try w.print(" at {f}", .{loc});
        }
        if (ctx.token) |token| {
            try w.print(" near {s}", .{token.lexeme});
        }
    }
};
