pub const Resolver = @This();

const std = @import("std");
const Scope = std.StringHashMap(bool);
const ScopeList = std.ArrayList(std.StringHashMap(bool));

const lox = @import("lox.zig");
const Expr = lox.Expr;
const Interpreter = lox.Interpreter;
const LoxError = lox.LoxError;
const Stmt = lox.Stmt;
const Token = lox.Token;

gpa: std.mem.Allocator,
interpreter: *Interpreter,
scopes: ScopeList,
statements: []const Stmt,
expressions: []const Expr,
curr_function: FunctionType = .None,

const FunctionType = enum {
    None,
    Function,
    Method,
};

pub fn init(allocator: std.mem.Allocator, interpreter: *Interpreter) Resolver {
    return .{
        .gpa = allocator,
        .interpreter = interpreter,
        .scopes = .empty,
        .statements = interpreter.statements,
        .expressions = interpreter.expressions,
    };
}

pub fn resolve(self: *Resolver, stmt: Stmt) LoxError!void {
    try self.resStmt(stmt);
}

fn resStmt(self: *Resolver, stmt: Stmt) LoxError!void {
    switch (stmt) {
        .Block => |b| {
            try self.beginScope();
            for (b.statements) |s| {
                try self.resStmt(self.statements[s]);
            }
            self.endScope();
        },
        .Class => |c| {
            try self.declare(c.name);
            try self.define(c.name);

            const enclosing_func = self.curr_function;
            self.curr_function = .Method;
            defer self.curr_function = enclosing_func;

            for (c.methods) |method| {
                try self.resStmt(self.statements[method]);
            }
        },
        .Expression => |e| {
            try self.resExpr(self.expressions[e.value]);
        },
        .Function => |f| {
            const enclosing_func = self.curr_function;
            self.curr_function = .Function;
            defer self.curr_function = enclosing_func;

            try self.beginScope();
            for (f.params) |param| {
                try self.declare(param);
                try self.define(param);
            }
            try self.resStmt(self.statements[f.body]);
            self.endScope();
        },
        .If => |i| {
            try self.resExpr(self.expressions[i.condition]);
            try self.resStmt(self.statements[i.then_branch]);
            if (i.else_branch) |eb| try self.resStmt(self.statements[eb]);
        },
        .Print => |p| {
            try self.resExpr(self.expressions[p.value]);
        },
        .Return => |r| {
            if (self.curr_function == .None)
                self.interpreter.diagnostics.reportError(
                    .init(
                        "Cannot return from top-level",
                        LoxError.ReturnFromTopLevel,
                        r.keyword,
                    ),
                );
            try if (r.value) |val| self.resExpr(self.expressions[val]);
        },
        .Variable => |v| {
            try self.declare(v.name);
            if (v.value) |val| try self.resExpr(self.expressions[val]);
            try self.define(v.name);
        },
        .While => |w| {
            try self.resExpr(self.expressions[w.condition]);
            try self.resStmt(self.statements[w.body]);
        },
    }
}

fn resExpr(self: *Resolver, expr: Expr) !void {
    switch (expr) {
        .Assign => |a| {
            try self.resExpr(self.expressions[a.value]);
            try self.resolveLocal(expr);
        },
        .Binary => |b| {
            try self.resExpr(self.expressions[b.left]);
            try self.resExpr(self.expressions[b.right]);
        },
        .Call => |c| {
            try self.resExpr(self.expressions[c.callee]);
            for (0..c.args.len) |idx| {
                try self.resExpr(self.expressions[c.args[idx]]);
            }
        },
        .Get => |g| {
            try self.resExpr(self.expressions[g.object]);
        },
        .Group => |g| {
            try self.resExpr(self.expressions[g.expr]);
        },
        .Literal => |_| {},
        .Logical => |l| {
            try self.resExpr(self.expressions[l.left]);
            try self.resExpr(self.expressions[l.right]);
        },
        .Set => |s| {
            try self.resExpr(self.expressions[s.value]);
            try self.resExpr(self.expressions[s.object]);
        },
        .Unary => |u| {
            try self.resExpr(self.expressions[u.expr]);
        },
        .Variable => |v| {
            const scope = self.scopes.getLastOrNull() orelse return;
            const name = self.getName(v.name);
            if (scope.get(name)) |defined| if (defined == false) {
                self.interpreter.diagnostics.reportError(
                    .init(
                        "Cannot read local variable in its initializer",
                        LoxError.SelfreferenceInitializer,
                        v.name,
                    ),
                );
            };

            try self.resolveLocal(expr);
        },
    }
}

// MARK: Scope stuff
fn resolveLocal(self: *Resolver, expr: Expr) !void {
    var idx = self.scopes.items.len - 1;
    const name = switch (expr) {
        .Assign => |a| self.getName(a.name),
        .Variable => |v| self.getName(v.name),
        else => return LoxError.UnexpectedToken,
    };

    while (idx > 0) {
        idx -= 1;
        if (self.scopes.items[idx].contains(name)) {
            try self.interpreter.resolve(expr, self.scopes.items.len - 1 - idx);
            return;
        }
    }
}
fn declare(self: *Resolver, tok: Token) !void {
    const name = self.getName(tok);
    if (self.scopes.items.len == 0) return;

    var scope = self.scopes.getLast();
    if (scope.contains(name)) {
        self.interpreter.diagnostics.reportError(.init(
            "Variable previously declared in this scope.",
            LoxError.VariableRedeclaration,
            tok,
        ));
    }
    try scope.put(name, false);
}
fn define(self: *Resolver, tok: Token) !void {
    const name = self.getName(tok);
    if (self.scopes.items.len == 0) return;

    var scope = self.scopes.getLast();
    try scope.put(name, true);
}

fn beginScope(self: *Resolver) LoxError!void {
    const new_scope = Scope.init(self.gpa);
    try self.scopes.append(self.gpa, new_scope);
}
fn endScope(self: *Resolver) void {
    _ = self.scopes.pop();
}

fn getName(self: *const Resolver, tok: Token) []const u8 {
    return tok.lexeme(self.interpreter.source_code);
}
