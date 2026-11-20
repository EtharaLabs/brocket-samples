const std=@import("std");
const a=std.heap.page_allocator;
const pathname: c_int=if (@import("builtin").os.tag==.macos) 2 else 1;
extern "c" fn fnmatch([*:0]const u8,[*:0]const u8,c_int) c_int;
fn z(s: []const u8) [:0]const u8 { const b=a.allocSentinel(u8,s.len,0) catch unreachable; @memcpy(b,s); return b; }
pub fn matches(pattern: []const u8,path: []const u8) bool {
    if (pattern.len==0) return false;
    var p=pattern; if (p[0]=='/') p=p[1..];
    const directory=std.mem.endsWith(u8,p,"/"); if (directory) p=p[0..p.len-1];
    if (std.mem.indexOfScalar(u8,p,'/')!=null or pattern[0]=='/') {
        if (fnmatch(z(p),z(path),pathname)==0) return true;
        if (directory and std.mem.startsWith(u8,path,p) and path.len>p.len and path[p.len]=='/') return true;
        var off: usize=0; while (std.mem.indexOfScalarPos(u8,path,off,'/')) |n| { if (fnmatch(z(p),z(path[0..n]),pathname)==0) return true; off=n+1; }
        return false;
    }
    var parts=std.mem.splitScalar(u8,path,'/'); while (parts.next()) |part| { if (fnmatch(z(p),z(part),0)==0 and (!directory or parts.index!=null)) return true; }
    return false;
}
test "ignore patterns distinguish anchored paths, basenames and directory prefixes" {
    try std.testing.expect(matches("output*","output.txt"));
    try std.testing.expect(matches("untracked","dir/untracked"));
    try std.testing.expect(!matches("/untracked","dir/untracked"));
    try std.testing.expect(matches("build/","build/nested/file"));
    try std.testing.expect(!matches("build/","build"));
    try std.testing.expect(matches("dir/*.tmp","dir/a.tmp"));
    try std.testing.expect(!matches("dir/*.tmp","dir/nested/a.tmp"));
}
