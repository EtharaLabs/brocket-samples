const std = @import("std");
const a = std.heap.page_allocator;
extern "c" fn regcomp(*anyopaque, [*:0]const u8, c_int) c_int;
extern "c" fn regexec(*const anyopaque, [*:0]const u8, usize, ?*anyopaque, c_int) c_int;
extern "c" fn regfree(*anyopaque) void;
pub const Space = enum { exact, eol, change, all };
pub const Options = struct { space: Space=.exact, cr: bool=false, blank: bool=false, ignore: ?[]const u8=null };
pub const Line = struct { kind: u8, text: []const u8, ignored: bool=false };
pub fn split(data: []const u8) [][]const u8 {
    var list: std.ArrayList([]const u8)=.empty; var off: usize=0;
    while (off<data.len) { const end=if (std.mem.indexOfScalarPos(u8,data,off,'\n')) |n| n+1 else data.len; list.append(a,data[off..end]) catch unreachable; off=end; }
    return list.toOwnedSlice(a) catch unreachable;
}
fn key(text: []const u8, o: Options) []const u8 {
    if (o.space==.exact and !o.cr) return text;
    var data=std.mem.trimEnd(u8,text,"\n");
    if (o.cr and data.len>0 and data[data.len-1]=='\r') data=data[0..data.len-1];
    switch (o.space) {
        .exact => return data,
        .eol => return std.mem.trimEnd(u8,data," \t\r\x0b\x0c"),
        .all, .change => {
            var result: std.ArrayList(u8)=.empty; var space=false;
            for (data) |c| { if (std.ascii.isWhitespace(c)) { space=true; continue; } if (space and o.space==.change) result.append(a,' ') catch unreachable; space=false; result.append(a,c) catch unreachable; }
            return result.items;
        },
    }
}
fn regexMatches(pattern: []const u8, text: []const u8) bool {
    var storage: [512]u64=undefined;
    const p=a.allocSentinel(u8,pattern.len,0) catch unreachable; @memcpy(p,pattern);
    if (regcomp(&storage,p.ptr,1|8)!=0) return false; defer regfree(&storage);
    const t=a.allocSentinel(u8,text.len,0) catch unreachable; @memcpy(t,text);
    return regexec(&storage,t.ptr,0,null,0)==0;
}
pub fn lines(before: []const u8, after: []const u8, o: Options) []Line {
    const old=split(before); const new=split(after); var result: std.ArrayList(Line)=.empty;
    if ((old.len+1)*(new.len+1)>2_000_000) { for (old) |l| result.append(a,.{.kind='-',.text=l}) catch unreachable; for (new) |l| result.append(a,.{.kind='+',.text=l}) catch unreachable; return result.items; }
    const oldkeys=a.alloc([]const u8,old.len) catch unreachable; for (old,0..) |l,i| oldkeys[i]=key(l,o);
    const newkeys=a.alloc([]const u8,new.len) catch unreachable; for (new,0..) |l,i| newkeys[i]=key(l,o);
    const width=new.len+1; const table=a.alloc(u32,(old.len+1)*width) catch unreachable; @memset(table,0);
    var i=old.len; while (i>0) { i-=1; var j=new.len; while (j>0) { j-=1; table[i*width+j]=if (std.mem.eql(u8,oldkeys[i],newkeys[j])) table[(i+1)*width+j+1]+1 else @max(table[(i+1)*width+j],table[i*width+j+1]); } }
    i=0; var j: usize=0;
    while (i<old.len or j<new.len) {
        if (i<old.len and j<new.len and std.mem.eql(u8,oldkeys[i],newkeys[j])) { result.append(a,.{.kind=' ',.text=new[j]}) catch unreachable; i+=1; j+=1; }
        else if (i<old.len and (j==new.len or table[(i+1)*width+j]>=table[i*width+j+1])) { result.append(a,.{.kind='-',.text=old[i]}) catch unreachable; i+=1; }
        else { result.append(a,.{.kind='+',.text=new[j]}) catch unreachable; j+=1; }
    }
    if (o.blank or o.ignore!=null) {
        var off: usize=0;
        while (off<result.items.len) {
            if (result.items[off].kind==' ') { off+=1; continue; }
            var end=off; var blank=true; var matched=true;
            while (end<result.items.len and result.items[end].kind!=' ') : (end+=1) {
                const l=result.items[end]; const text=key(l.text,o);
                if (std.mem.trim(u8,text,if (o.space==.all or o.space==.change) " \t\r\n" else "\n").len>0) blank=false;
                if (o.ignore) |pattern| { if (!regexMatches(pattern,l.text)) matched=false; } else matched=false;
            }
            if ((o.blank and blank) or matched) for (result.items[off..end]) |*l| { l.ignored=true; };
            off=end;
        }
    }
    return result.items;
}
pub fn changed(data: []const Line) bool { for (data) |l| { if (l.kind!=' ' and !l.ignored) return true; } return false; }

test "ignore-all-space equates inserted indentation and interword spaces" {
    try std.testing.expect(!changed(lines("white space\n"," \twhitespace \r\n",.{.space=.all})));
}
test "ignore-space-change preserves the distinction between whitespace and its absence" {
    try std.testing.expect(changed(lines("ab\n","a b\n",.{.space=.change})));
}
test "blank-line ignoring retains mixed nonblank changes" {
    try std.testing.expect(changed(lines("old\n","new\n\n",.{.blank=true})));
}
test "blank-only insertions are ignored" {
    try std.testing.expect(!changed(lines("a\nb\n","a\n\nb\n",.{.blank=true})));
}
