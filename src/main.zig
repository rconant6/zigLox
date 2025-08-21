const std = @import("std");
const lox = @import("lox.zig");
const Scanner = lox.Scanner;
const Token = lox.Token;

const std_out = std.io.getStdOut().writer();
const std_in = std.io.getStdIn().reader();
const std_err = std.io.getStdErr().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    switch (args.len) {
        1 => try runFromPrompt(allocator),
        2 => try runFromFile(allocator, args[1]),
        else => {
            try std_out.print("Usage: zlox [script]\n", .{});
            std.process.exit(64);
        },
    }

    std.process.cleanExit();
}

fn runFromPrompt(gpa: std.mem.Allocator) anyerror!void {
    const prompt = "zlox> ";
    var line_buf = std.ArrayList(u8).init(gpa);
    defer line_buf.deinit();

    try std_out.print("ZLox REPL - Type 'exit' to quit\n", .{});
    while (true) {
        try std_out.print("{s}", .{prompt});

        try std_in.streamUntilDelimiter(line_buf.writer(), '\n', null);
        const line = try line_buf.toOwnedSlice();
        defer gpa.free(line);

        if (std.mem.eql(u8, "quit", line) or line.len == 0) break;

        processData(gpa, line) catch |err| {
            // TODO: add the context to the error
            try std_err.print("ERROR: {any}\n", .{err});
        };
    }
}

fn runFromFile(gpa: std.mem.Allocator, file_name: []const u8) !void {
    const file: std.fs.File = std.fs.cwd().openFile(
        file_name,
        .{},
    ) catch |err| {
        try std_out.print("Unable to open file: {s}\n", .{file_name});
        return err;
    };
    const stats = try file.stat();

    const data: []const u8 = try gpa.alloc(u8, stats.size);
    defer gpa.free(data);

    try processData(gpa, data);
}

fn processData(gpa: std.mem.Allocator, data: []const u8) !void {
    // do the shared work here
    _ = gpa;
    _ = data;
}
