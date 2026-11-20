const std=@import("std");
const a=std.heap.page_allocator;
fn eq(x: []const u8,y: []const u8) bool { return std.mem.eql(u8,x,y); }
fn lower(s: []const u8) []const u8 { const b=a.dupe(u8,s) catch unreachable; for (b) |*c| c.*=std.ascii.toLower(c.*); return b; }
const Url=struct { scheme: []const u8, host: []const u8, user: ?[]const u8, port: []const u8, path: []const u8 };
fn parse(text: []const u8) ?Url {
    const colon=std.mem.indexOf(u8,text,"://") orelse return null;
    const scheme=lower(text[0..colon]); var rest=text[colon+3..];
    const slash=std.mem.indexOfAny(u8,rest,"/?#") orelse rest.len; var authority=rest[0..slash]; rest=rest[slash..];
    var user: ?[]const u8=null; if (std.mem.lastIndexOfScalar(u8,authority,'@')) |at| { user=authority[0..at]; authority=authority[at+1..]; }
    var host=authority; var port: []const u8=if (eq(scheme,"https")) "443" else if (eq(scheme,"http")) "80" else "";
    if (std.mem.lastIndexOfScalar(u8,authority,':')) |p| { if (std.mem.indexOfScalar(u8,authority,']')==null or authority[authority.len-1]!=']') { host=authority[0..p]; port=authority[p+1..]; } }
    if (host.len==0) return null;
    const end=std.mem.indexOfAny(u8,rest,"?#") orelse rest.len;
    const path=if (end==0) "/" else rest[0..end];
    return .{.scheme=scheme,.host=lower(host),.port=port,.user=user,.path=path};
}
pub fn score(pattern: []const u8,value: []const u8) ?u64 {
    const wanted=parse(pattern) orelse return null; const actual=parse(value) orelse return null;
    if (!eq(wanted.scheme,actual.scheme) or !eq(wanted.port,actual.port)) return null;
    var left=std.mem.splitScalar(u8,wanted.host,'.'); var right=std.mem.splitScalar(u8,actual.host,'.'); var hostlen: u64=0;
    while (left.next()) |part| { const other=right.next() orelse return null; if (!eq(part,"*")) { if (!eq(part,other)) return null; hostlen+=part.len+1; } }
    if (right.next()!=null) return null;
    if (wanted.user) |user| { if (actual.user==null or !eq(user,actual.user.?)) return null; }
    if (!std.mem.startsWith(u8,actual.path,wanted.path)) return null;
    if (actual.path.len>wanted.path.len and wanted.path[wanted.path.len-1]!='/' and actual.path[wanted.path.len]!='/') return null;
    // Host specificity outranks path specificity, which outranks user qualification.
    return (hostlen<<40)+(@as(u64,wanted.path.len)<<8)+@intFromBool(wanted.user!=null)+1;
}
test "URL selection respects component boundaries and specificity" {
    try std.testing.expect(score("https://*.example.com","https://a.example.com")!=null);
    try std.testing.expect(score("https://*.example.com","https://a.b.example.com")==null);
    try std.testing.expect(score("https://example.com/sub","https://example.com/submarine")==null);
    try std.testing.expect(score("https://example.com/sub","https://user@example.com/sub/file").?>score("https://user@example.com/","https://user@example.com/sub/file").?);
    try std.testing.expect(score("https://sub.example.com/","https://sub.example.com/path").?>score("https://*.example.com/path","https://sub.example.com/path").?);
    try std.testing.expect(score("https://EXAMPLE.com:443","https://example.com/")!=null);
}
