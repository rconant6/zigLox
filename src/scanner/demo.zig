
const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Token = struct {
    tag: Tag,
    loc: Loc,

    const Loc = struct {
        start: u32,
        end: u32,

        fn len(loc: Loc) u32 {
            return loc.end - loc.start;
        }

        fn slice(self: Loc, code: []const u8) []const u8 {
            return code[self.start..self.end];
        }
    };

    const Tag = enum {
        invalid,
        single_a,
        single_b,
        double_c,
        eof,

        fn lexeme(self: Tag) ?[]const u8 {
            return switch (self) {
                .invalid, .eof => null,
                .single_a => "a",
                .single_b => "b", 
                .double_c => "cc",
            };
        }
    };
};

const State = enum {
    invalid,
    start,
    expecting_second_c,
};

const MiniScanner = struct {
    idx: u32,

    fn init() MiniScanner {
        return .{ .idx = 0 };
    }

    fn char(self: *MiniScanner, src: []const u8) u8 {
        if (self.idx >= src.len) return 0;
        return src[self.idx];
    }

    // Main tokenization function using labeled switch pattern
    fn next(self: *MiniScanner, src: []const u8) ?Token {
        var tok: Token = .{
            .tag = .invalid,
            .loc = .{
                .start = self.idx,
                .end = undefined,
            },
        };

        state: switch (State.start) {
            .start => start: switch (self.char(src)) {
                0 => return null, // EOF
                
                // Skip whitespace
                ' ', '\n', '\t', '\r' => {
                    self.idx += 1;
                    tok.loc.start += 1;
                    continue :start self.char(src);
                },
                
                'a' => {
                    self.idx += 1;
                    tok.tag = .single_a;
                    tok.loc.end = self.idx;
                    break :state;
                },
                
                'b' => {
                    self.idx += 1;
                    tok.tag = .single_b;
                    tok.loc.end = self.idx;
                    break :state;
                },
                
                'c' => {
                    self.idx += 1;
                    continue :state .expecting_second_c;
                },
                
                else => continue :state .invalid,
            },
            
            .expecting_second_c => second_c: switch (self.char(src)) {
                0 => {
                    // EOF in middle of potential "cc" - invalid
                    tok.tag = .invalid;
                    tok.loc.end = self.idx;
                    break :state;
                },
                
                'c' => {
                    self.idx += 1;
                    tok.tag = .double_c;
                    tok.loc.end = self.idx;
                    break :state;
                },
                
                else => {
                    // First 'c' followed by non-'c' - invalid
                    continue :state .invalid;
                },
            },
            
            .invalid => invalid: switch (self.char(src)) {
                // Consume until we hit whitespace or EOF
                0, ' ', '\n', '\t', '\r' => {
                    tok.loc.end = self.idx;
                    break :state;
                },
                else => {
                    self.idx += 1;
                    continue :invalid self.char(src);
                },
            },
        }
        
        return tok;
    }

    // Scan entire input and return all tokens
    fn scanAll(self: *MiniScanner, allocator: Allocator, src: []const u8) ![]Token {
        var tokens = ArrayList(Token).init(allocator);
        
        while (self.next(src)) |token| {
            try tokens.append(token);
            
            // Debug output
            const lexeme = if (token.tag.lexeme()) |lex| 
                lex 
            else 
                token.loc.slice(src);
                
            std.debug.print("Token: {s} '{s}' [{}-{}]\n", 
                .{ @tagName(token.tag), lexeme, token.loc.start, token.loc.end });
        }
        
        return tokens.toOwnedSlice();
    }
};

// Test function
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_cases = [_][]const u8{
        "ab",           // Valid: a, b
        "a b cc",       // Valid: a, b, cc (with whitespace)
        "abcc",         // Valid: a, b, cc
        "ccab",         // Valid: cc, a, b  
        "abc",          // Invalid: c without second c
        "abx",          // Invalid: x is not allowed
        "c",            // Invalid: incomplete cc
        "ccccab",       // Valid: cc, cc, a, b
        "a  b   cc",    // Valid with extra whitespace
        "cx",           // Invalid: c followed by x
    };

    for (test_cases) |test_input| {
        std.debug.print("\n=== Testing input: '{s}' ===\n", .{test_input});
        
        var scanner = MiniScanner.init();
        const tokens = try scanner.scanAll(allocator, test_input);
        defer allocator.free(tokens);
        
        std.debug.print("Total tokens: {}\n", .{tokens.len});
        
        // Check if scan was successful (no invalid tokens)
        var valid = true;
        for (tokens) |token| {
            if (token.tag == .invalid) {
                valid = false;
                break;
            }
        }
        
        std.debug.print("Scan result: {s}\n", .{if (valid) "✓ VALID" else "✗ INVALID"});
    }
}
