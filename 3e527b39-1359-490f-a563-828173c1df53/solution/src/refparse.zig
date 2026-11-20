const std = @import("std");
const a = std.heap.page_allocator;
fn fmt(comptime f: []const u8, args: anytype) []const u8 { return std.fmt.allocPrint(a,f,args) catch unreachable; }

// update-ref's text protocol uses C-style quoting, not shell tokenization.
pub const Parser = struct {
    text: []const u8, pos: usize = 0, err: ?[]const u8 = null,
    pub fn next(self: *Parser) ?[]const u8 {
        while (self.pos < self.text.len and std.ascii.isWhitespace(self.text[self.pos])) : (self.pos += 1) {}
        if (self.pos == self.text.len) return null;
        const start = self.pos;
        if (self.text[self.pos] != '"') { while (self.pos < self.text.len and !std.ascii.isWhitespace(self.text[self.pos])) : (self.pos += 1) {} return self.text[start..self.pos]; }
        self.pos += 1;
        var buf: std.ArrayList(u8) = .empty;
        while (self.pos < self.text.len) {
            var c = self.text[self.pos]; self.pos += 1;
            if (c == '"') {
                if (self.pos < self.text.len and !std.ascii.isWhitespace(self.text[self.pos])) { self.err=fmt("unexpected character after quoted argument: {s}",.{self.text[start..]}); return null; }
                return buf.toOwnedSlice(a) catch unreachable;
            }
            if (c == '\\') {
                if (self.pos == self.text.len) break;
                c = self.text[self.pos]; self.pos += 1;
                if (c >= '0' and c <= '3' and self.pos+1 < self.text.len and self.text[self.pos] >= '0' and self.text[self.pos] <= '7' and self.text[self.pos+1] >= '0' and self.text[self.pos+1] <= '7') {
                    c = (c-'0')*64+(self.text[self.pos]-'0')*8+self.text[self.pos+1]-'0'; self.pos += 2;
                } else c = switch (c) { 'a' => 7, 'b' => 8, 't' => 9, 'n' => 10, 'v' => 11, 'f' => 12, 'r' => 13, '\\' => '\\', '"' => '"', else => break };
            }
            buf.append(a,c) catch unreachable;
        }
        self.err=fmt("badly quoted argument: {s}",.{self.text[start..]}); return null;
    }
};

test "text arguments preserve quoted whitespace and octal escapes" {
    var p=Parser{.text="refs/blobs/test \"HEAD:path with space\" \"ma\\151n\""};
    try std.testing.expectEqualStrings("refs/blobs/test",p.next().?);
    try std.testing.expectEqualStrings("HEAD:path with space",p.next().?);
    try std.testing.expectEqualStrings("main",p.next().?);
    try std.testing.expect(p.next()==null);
}

test "text arguments reject malformed quoting" {
    for ([_][]const u8{"\"unterminated", "\"bad\\z\"", "\"ref\"junk"}) |text| {
        var p=Parser{.text=text};
        try std.testing.expect(p.next()==null);
        try std.testing.expect(p.err!=null);
    }
}
