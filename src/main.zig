const std = @import("std");
const lox = @import("lox.zig");
const Scanner = lox.Scanner;
const Token = lox.Token;

const out_writer = lox.out_writer;
const err_writer = lox.err_writer;
const in_reader = lox.in_reader;

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
    try out_writer.print("ZLox REPL - Type 'exit' to quit\n", .{});

    while (true) {
        try out_writer.print("zlox> ", .{});
        try out_writer.flush();

        const line = in_reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            error.StreamTooLong => {
                try err_writer.print("ERROR: Line too long\n", .{});
                try err_writer.flush();
                continue;
            },
            error.ReadFailed => |e| return e,
        };

        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (std.mem.eql(u8, trimmed, "exit")) break;

        processData(gpa, trimmed) catch |err| {
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
    try processData(gpa, data);
}

fn processData(gpa: std.mem.Allocator, data: []const u8) !void {
    var scanner: Scanner = try .init(gpa, data);
    const tokens = try scanner.scanTokens();

    std.log.info("Found {d} tokens", .{tokens.len});
    for (tokens) |token| {
        std.log.debug("{f}", .{token});
    }
}
