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
    UnmatchedClosingParen,
    UnexpectedToken,
    // Semantic Errors
    BrokenSuperLink,
    DivisionByZero,
    InitializerReturnedValue,
    InvalidBinaryOperand,
    InvalidOperands,
    MethodNotDefined,
    NoMethodInSuperClass,
    NotInSubClass,
    NoPropertyAvailable,
    NotCallable,
    NoSuperClassDefined,
    NoSuperClassEnvironment,
    SuperClassNotClass,
    TypeMismatch,
    UndefinedProperty,
    UndefinedVariable,
    WrongNumberOfArguments,
    // Static Analysis Errors
    InheritanceCylce,
    ReturnFromTopLevel,
    SelfreferenceInitializer,
    VariableRedeclaration,
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
    token: Token,
    error_type: LoxError,
    src_code: []const u8,

    pub fn format(ctx: ErrorContext, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("Error: {t} {s}\n  <src: {s}>", .{
            ctx.error_type,
            ctx.message,
            ctx.src_code,
        });
        try ctx.token.error_format(w);
    }
};
