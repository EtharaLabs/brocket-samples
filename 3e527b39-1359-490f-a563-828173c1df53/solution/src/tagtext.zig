const std = @import("std");
pub fn clean(a: std.mem.Allocator, raw: []const u8, mode: []const u8) []const u8 {
    if (std.mem.eql(u8,mode,"verbatim")) return raw;
    var result: std.ArrayList(u8)=.empty; var blank=false; var lines=std.mem.splitScalar(u8,raw,'\n');
    while (lines.next()) |line| {
        const text=std.mem.trimEnd(u8,line," \t\r");
        if (std.mem.eql(u8,mode,"strip") and std.mem.startsWith(u8,text,"#")) continue;
        if (text.len==0) { if (result.items.len>0) blank=true; continue; }
        if (blank) result.append(a,'\n') catch unreachable;
        blank=false; result.appendSlice(a,text) catch unreachable; result.append(a,'\n') catch unreachable;
    }
    return result.toOwnedSlice(a) catch unreachable;
}
test "tag cleanup removes comments and collapses empty lines without stripping indentation" {
    // Given a message containing comments, indentation, and redundant whitespace.
    const raw="\n# header\n  first \t\n\n\t\n# middle\nsecond\n\n";
    // When default tag cleanup is applied.
    const actual=clean(std.testing.allocator,raw,"strip"); defer std.testing.allocator.free(actual);
    // Then the retained message has one blank separator and a terminating newline.
    try std.testing.expectEqualStrings("  first\n\nsecond\n",actual);
}
test "verbatim tag cleanup preserves all bytes" {
    const raw="\n# comment\n \t";
    try std.testing.expectEqualStrings(raw,clean(std.testing.allocator,raw,"verbatim"));
}
