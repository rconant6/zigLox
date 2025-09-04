pub const Compiler = @This();

const std = @import("std");
const lox = @import("lox.zig");
const Scanner = lox.Scanner;

pub fn compile(src: []const u8) !void {
    var scanner: Scanner = .init(src[0..]);

    var line: u32 = 0;
    while (true) {
        const token = scanner.getToken() catch |err| {
            const err_data = scanner.scan_error.?;
            std.debug.print(
                "[SCANNER] exited with error {any} at {f}, and msg: {s}",
                .{ err, err_data.src, err_data.msg },
            );
            return err;
        };
        if (token.src_loc.line != line) {
            std.debug.print("{d:4} ", .{token.src_loc.line});
            line = token.src_loc.line;
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{t} '{s}'\n", .{ token.tag, token.lexeme(src) });

        if (token.tag == .Eof) break;
    }
}
