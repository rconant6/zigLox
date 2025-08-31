const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const DebugAllocator = std.heap.DebugAllocator;
const DebugAllocatorConfig = std.heap.DebugAllocatorConfig;
const lox = @import("lox.zig");
const DiagnosticReporter = lox.DiagnosticReporter;
const Environment = lox.Environment;
const Interpreter = lox.Interpreter;
const InterpreterConfig = lox.InterpreterConfig;
const Parser = lox.Parser;
const Resolver = lox.Resolver;
const Token = lox.Token;
const Tokenizer = lox.Tokenizer;

const out_writer = lox.out_writer;
const err_writer = lox.err_writer;
const in_reader = lox.in_reader;

const lex_parse_err = 65;
const runtime_err = 70;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(DebugAllocatorConfig{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena_alloc = std.heap.ArenaAllocator.init(allocator);
    const arena = arena_alloc.allocator();
    defer arena_alloc.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    switch (args.len) {
        1 => try runFromPrompt(arena),
        2 => try runFromFile(arena, args[1]),
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
    var history: ArrayList([]const u8) = .empty;
    defer history.deinit(gpa);

    const global_env = try gpa.create(Environment);
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
        try history.append(gpa, trimmed);

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

    const global_env = try gpa.create(Environment);
    defer {
        global_env.env.deinit();
        gpa.destroy(global_env);
    }
    global_env.* = .createGlobalEnv(gpa);

    const return_val = try processData(gpa, data, global_env);
    std.process.exit(return_val);
}

fn processData(gpa: std.mem.Allocator, data: []const u8, env: *Environment) !u8 {
    var diagnostics: DiagnosticReporter = .init(gpa);

    var scanner: Tokenizer = .init();
    const tokens = scanner.scanTokens(gpa, data, &diagnostics) catch {
        if (diagnostics.hasErrors()) {
            std.log.err(
                "FAILURE: Lexing failed with {d} Error(s)",
                .{diagnostics.errors.items.len},
            );
            try diagnostics.printDiagnostics(err_writer);
        }
        return lex_parse_err;
    };

    if (tokens.len <= 1) return 0;
    std.log.info("SUCCESS:  Lexing Complete with {d} tokens", .{tokens.len});
    diagnostics.clearErrors();

    var parser: Parser = .init(gpa, &diagnostics, tokens, data);

    const program = parser.parse(tokens) catch {
        std.log.err(
            "FAILURE: Parsing failed with {d} Error(s)",
            .{diagnostics.errors.items.len},
        );
        if (diagnostics.hasErrors()) {
            try diagnostics.printDiagnostics(err_writer);
        }
        return lex_parse_err;
    };
    std.log.info("SUCCESS:  Parsing Complete", .{});
    diagnostics.clearErrors();

    const config: InterpreterConfig = .{
        .diagnostic = &diagnostics,
        .expressions = try parser.expressions.toOwnedSlice(gpa),
        .statements = try parser.statements.toOwnedSlice(gpa),
        .source_code = data,
        .global_env = env,
    };

    var interpreter: Interpreter = try .init(gpa, config);
    var resolver: Resolver = .init(gpa, &interpreter);
    _ = try resolver.resolve(program);
    if (diagnostics.hasErrors()) {
        try diagnostics.printDiagnostics(err_writer);
        diagnostics.clearErrors();
        return lex_parse_err;
    }
    std.log.info("SUCCESS:  Resolving Complete", .{});

    _ = interpreter.interpret(program) catch |err| {
        std.log.err("Runtime exited with error {}", .{err});
        if (diagnostics.hasErrors()) {
            try diagnostics.printDiagnostics(err_writer);
            diagnostics.clearErrors();
        }
        return runtime_err;
    };

    return 0;
}
