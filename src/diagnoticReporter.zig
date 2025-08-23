const DiagnosticReporter = @This();

const std = @import("std");
const lox = @import("lox.zig");

const Token = lox.Token;
const ErrorContext = lox.ErrorContext;

allocator: std.mem.Allocator,
errors: std.ArrayList(ErrorContext),

pub fn init(allocator: std.mem.Allocator) DiagnosticReporter {
    return .{
        .errors = .empty,
        .allocator = allocator,
    };
}

pub fn deinit(self: *DiagnosticReporter) void {
    self.errors.deinit(self.allocator);
}

pub fn reportError(self: *DiagnosticReporter, context: ErrorContext) void {
    self.errors.append(self.allocator, context) catch |err| {
        switch (err) {
            error.OutOfMemory => {
                std.log.err("SYSTEM ISSUE: Out of Memory", .{});
                std.debug.panic("DiagnosticReporter.reportError()", .{});
            },
        }
    };
}

pub fn hasErrors(self: DiagnosticReporter) bool {
    return self.errors.items.len > 0;
}

pub fn clearErrors(self: DiagnosticReporter) void {
    @constCast(&self).errors.clearRetainingCapacity();
}

pub fn printDiagnostics(self: DiagnosticReporter, w: *std.Io.Writer) !void {
    for (self.errors.items) |ctx| {
        try w.print("{f}", .{ctx});
    }
}
