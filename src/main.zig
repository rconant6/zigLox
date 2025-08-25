const std = @import("std");
const lox = @import("lox.zig");
const DiagnosticReporter = lox.DiagnosticReporter;
const Environment = lox.Environment;
const Interpreter = lox.Interpreter;
const Parser = lox.Parser;
const Scanner = lox.Scanner;
const Token = lox.Token;

const out_writer = lox.out_writer;
const err_writer = lox.err_writer;
const in_reader = lox.in_reader;

const lex_parse_err = 65;
const runtime_err = 70;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    switch (args.len) {
        1 => try runFromPrompt(allocator),
        2 => try runFromFile(allocator, args[1]),
        else => {
            try out_writer.print("Usage: zlox [script]\n", .{});
            try out_writer.flush();
            std.process.exit(64);
        },
    }

    std.process.cleanExit();
}

fn runFromPrompt(gpa: std.mem.Allocator) anyerror!void {
    try out_writer.print("ZLox REPL - Welcome! type 'exit' to quit\n", .{});

    const global_env = try gpa.create(Environment);
    defer gpa.destroy(global_env);
    global_env.* = .createGlobalEnv(gpa);

    while (true) {
        try out_writer.print("zlox> ", .{});
        try out_writer.flush();

        const line = in_reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            error.StreamTooLong => {
                try err_writer.print("ERROR: Line too long\n", .{});
                try err_writer.flush();
                continue;
            },
            error.ReadFailed => |e| return e,
        };

        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (std.mem.eql(u8, trimmed, "exit")) break;

        _ = processData(gpa, trimmed, global_env) catch |err| {
            try err_writer.print("ERROR: {any}\n", .{err});
            try err_writer.flush();
        };
    }

    try out_writer.print("Goodbye!\n", .{});
    try out_writer.flush();
}

fn runFromFile(gpa: std.mem.Allocator, file_name: []const u8) !void {
    const file: std.fs.File = std.fs.cwd().openFile(
        file_name,
        .{},
    ) catch |err| {
        try err_writer.print("Unable to open file: {s}\n", .{file_name});
        try err_writer.flush();
        return err;
    };
    const stats = try file.stat();

    const data: []u8 = try gpa.alloc(u8, stats.size);
    defer gpa.free(data);

    const bytes = try file.readAll(data);
    std.debug.assert(bytes == stats.size);

    var env: Environment = .createGlobalEnv(gpa);
    const return_val = try processData(gpa, data, &env);
    std.process.exit(return_val);
}

fn processData(gpa: std.mem.Allocator, data: []const u8, env: *Environment) !u8 {
    var diagnostics: DiagnosticReporter = .init(gpa);

    var scanner: Scanner = try .init(gpa, data, &diagnostics);
    var parser: Parser = .init(gpa, &diagnostics);
    var interpreter: Interpreter = .init(gpa, &diagnostics, env);

    const tokens = scanner.scanTokens() catch {
        std.log.err("Lexing Complete with Error(s)", .{});
        if (diagnostics.hasErrors()) {
            try diagnostics.printDiagnostics(err_writer);
        }
        return lex_parse_err;
    };

    if (tokens.len <= 1) return 0;
    diagnostics.clearErrors();
    std.log.info("Lexing Complete with {d} tokens", .{tokens.len});
    // for (tokens) |token| {
    //     std.log.debug("{f}", .{token});
    // }

    const statements = parser.parse(tokens) catch {
        std.log.err("Parsing Complete with Error(s)", .{});
        if (diagnostics.hasErrors()) {
            try diagnostics.printDiagnostics(err_writer);
        }
        return lex_parse_err;
    };

    if (statements.len == 0) return 0;
    std.log.info("Parsing complete", .{});
    diagnostics.clearErrors();

    _ = try interpreter.interpret(statements);

    if (diagnostics.hasErrors()) {
        try diagnostics.printDiagnostics(err_writer);
        return runtime_err;
    }

    return 0;
}
