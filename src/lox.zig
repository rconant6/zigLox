const std = @import("std");

const stdin = std.fs.File.stdin();
const stdout = std.fs.File.stdout();
const stderr = std.fs.File.stderr();

var stdin_buffer: [1024]u8 = undefined;
var stdout_buffer: [4096]u8 = undefined;
var stderr_buffer: [1024]u8 = undefined;

var stdin_reader = stdin.reader(&stdin_buffer);
var stdout_writer = stdout.writer(&stdout_buffer);
var stderr_writer = stderr.writer(&stderr_buffer);

pub const in_reader: *std.Io.Reader = &stdin_reader.interface;
pub const out_writer: *std.Io.Writer = &stdout_writer.interface;
pub const err_writer: *std.Io.Writer = &stderr_writer.interface;

const tok = @import("token.zig");
pub const Token = tok.Token;
pub const TokenType = tok.TokenType;

pub const Scanner = @import("Scanner.zig").Scanner;

pub const Location = struct {
    line: u32 = 0,
    col: u32 = 0,

    pub fn advance(loc: *Location) void {
        loc.col += 1;
    }
    pub fn advanceBy(loc: *Location, dist: u32) void {
        loc.col += dist;
    }
    pub fn nextLine(loc: *Location) void {
        loc.line += 1;
        loc.col = 1;
    }

    pub fn advanced(loc: Location) Location {
        return .{ .line = loc.line, .col = loc.col + 1 };
    }
    pub fn advancedBy(loc: Location, dist: u32) Location {
        return .{ .line = loc.line, .col = loc.col + dist };
    }

    pub fn format(loc: Location, w: *std.Io.Writer) !void {
        return w.print(
            "Location: [line:{d:4} col:{d:4}]",
            .{ loc.line, loc.col },
        );
    }
};

pub const LiteralValue = union(enum) {
    string: []const u8,
    number: f64,
    bool: bool,
    void: void,
};
