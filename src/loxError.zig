const std = @import("std");

const lox = @import("lox.zig");
const Location = lox.Location;
const Token = lox.Token;

pub const LoxError = error{
    // Scanning Errors
    UnRecognizedCharacter,
    UnterminatedString,
    LexingError,
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
    InitializerReturnedValue,
    InvalidBinaryOperand,
    InvalidOperands,
    MethodNotDefined,
    NoPropertyAvailable,
    NotCallable,
    TypeMismatch,
    UndefinedProperty,
    UndefinedVariable,
    WrongNumberOfArguments,
    // Static Analysis Errors
    VariableRedeclaration,
    SelfreferenceInitializer,
    ReturnFromTopLevel,
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
    sourceCode: ?[]const u8 = null,
    errorType: LoxError,

    pub fn init(message: []const u8, errType: LoxError, token: ?Token) ErrorContext {
        return .{
            .message = message,
            .token = token,
            .errorType = errType,
        };
    }

    pub fn withSourceContext(self: ErrorContext, source: []const u8) ErrorContext {
        var copy = self;
        copy.sourceCode = source;
        return copy;
    }

    pub fn format(ctx: ErrorContext, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("Error({t}): {s} ", .{ ctx.errorType, ctx.message });
        if (ctx.token) |token| {
            try w.print(" {any}", .{token.error_format(w)});
        }
    }
};
