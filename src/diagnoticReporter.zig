const std = @import("std");
const lox = @import("lox.zig");
const lerr = @import("loxError.zig");
const tok = @import("token.zig");

const Token = tok.Token;
const ErrorContext = lerr.ErrorContext;
const System = lerr.System;

pub const DiagnosticReporter = struct {
    errors: std.ArrayList(ErrorContext),
    warnings: std.ArrayList(ErrorContext),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiagnosticReporter {
        return .{
            .errors = std.ArrayList(ErrorContext).init(allocator),
            .warnings = std.ArrayList(ErrorContext).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DiagnosticReporter) void {
        self.errors.deinit();
        self.warnings.deinit();
    }

    pub fn reportError(self: *DiagnosticReporter, context: ErrorContext) void {
        self.errors.append(context) catch |err| {
            handleFatalError(err);
        };
    }

    pub fn reportWarning(self: *DiagnosticReporter, context: ErrorContext) void {
        self.warnings.append(context) catch {
            handleFatalError(lerr.System.OutOfMemory);
        };
    }

    pub fn hasErrors(self: DiagnosticReporter) bool {
        return self.errors.items.len > 0;
    }

    pub fn printDiagnostics(self: DiagnosticReporter, writer: anytype) !void {
        for (self.errors.items) |err| {
            try err.format(writer);
            try writer.writeByte('\n');
        }

        for (self.warnings.items) |warn| {
            try writer.writeAll("Warning: ");
            try warn.format(writer);
            try writer.writeByte('\n');
        }
    }

    pub fn handleFatalError(err: System) noreturn {
        switch (err) {
            error.OutOfMemory => std.debug.panic("Serious system issue: Out of Memory\n", .{}),
            error.IOError => std.debug.panic("Serious system issue: IO failure\n", .{}),
        }
    }
};
