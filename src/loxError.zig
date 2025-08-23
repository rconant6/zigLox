const std = @import("std");
const tok = @import("token.zig");

const Token = tok.Token;

pub const Lexing = error{
    UnterminatedString,
    UnexpectedCharacter,
};

pub const Parsing = error{
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
};

pub const Semantic = error{
    UndefinedVariable,
    TypeMismatch,
    DivisionByZero,
    InvalidOperands,
    NotCallable,
    WrongNumberOfArguments,
};

pub const System = error{
    IOError,
    OutOfMemory,
};

pub const Lox = error{
    Return, // Used for function return propagation
    Unimplemented,
};

pub const LoxCompilerError =
    Lexing || Parsing || Semantic || System || Lox;

pub const ReturnValue = error{
    Return,
};

pub const ErrorContext = struct {
    message: []const u8,
    token: ?Token = null,
    line: ?usize = null,
    column: ?usize = null,
    sourceCode: ?[]const u8 = null,
    errorType: LoxCompilerError = Lexing.UnexpectedCharacter,

    pub fn init(message: []const u8, errType: LoxCompilerError) ErrorContext {
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

    pub fn withLocation(self: ErrorContext, line: usize, column: usize) ErrorContext {
        var copy = self;
        copy.line = line;
        copy.column = column;
        return copy;
    }

    pub fn withSourceContext(self: ErrorContext, source: []const u8) ErrorContext {
        var copy = self;
        copy.sourceCode = source;
        return copy;
    }

    pub fn format(ctx: ErrorContext, writer: anytype) !void {
        try writer.print("Error({s}): {s}", .{ @errorName(ctx.errorType), ctx.message });

        if (ctx.line != null and ctx.column != null) {
            try writer.print(
                " at line {d}, column {d}",
                .{ ctx.line.?, ctx.column.? },
            );
        }

        if (ctx.token) |token| {
            try writer.print(" near '{s}'", .{token.getLexeme()});
        }
    }
};
