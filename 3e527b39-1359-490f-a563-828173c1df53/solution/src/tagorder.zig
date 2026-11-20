const std = @import("std");
const Suffix = struct { start: usize, length: usize, rank: usize };
fn suffix(value: []const u8, suffixes: []const []const u8) ?Suffix {
    var best: ?Suffix=null;
    for (suffixes,0..) |s,rank| {
        if (s.len==0) continue;
        const start=std.mem.indexOf(u8,value,s) orelse continue;
        if (best==null or start<best.?.start or (start==best.?.start and s.len>best.?.length)) best=.{.start=start,.length=s.len,.rank=rank};
    }
    return best;
}
pub fn compare(x: []const u8, y: []const u8, suffixes: []const []const u8) std.math.Order {
    const sx=suffix(x,suffixes); const sy=suffix(y,suffixes);
    if (sx!=null or sy!=null) {
        const start=if (sx) |s| s.start else sy.?.start;
        if ((sy==null or sy.?.start==start) and x.len>=start and y.len>=start and std.mem.eql(u8,x[0..start],y[0..start])) {
            var fallback=suffixes.len; for (suffixes,0..) |s,i| { if (s.len==0) { fallback=i; break; } }
            const xr=if (sx) |s| s.rank else fallback; const yr=if (sy) |s| s.rank else fallback;
            if (xr!=yr) return std.math.order(xr,yr);
        }
    }
    var i: usize=0; var j: usize=0;
    while (i<x.len and j<y.len) {
        if (std.ascii.isDigit(x[i]) and std.ascii.isDigit(y[j])) {
            const xi=i; const yj=j; while (i<x.len and std.ascii.isDigit(x[i])) : (i+=1) {} while (j<y.len and std.ascii.isDigit(y[j])) : (j+=1) {}
            const xx=std.mem.trimStart(u8,x[xi..i],"0"); const yy=std.mem.trimStart(u8,y[yj..j],"0");
            if (xx.len!=yy.len) return std.math.order(xx.len,yy.len); const order=std.mem.order(u8,xx,yy); if (order!=.eq) return order;
        } else { if (x[i]!=y[j]) return std.math.order(x[i],y[j]); i+=1; j+=1; }
    }
    return std.math.order(x.len-i,y.len-j);
}
test "version ordering compares numeric components rather than lexical digits" {
    const order=compare("v1.9","v1.10",&.{});
    try std.testing.expectEqual(std.math.Order.lt,order);
}
test "configured suffix ordering prefers earliest and longest match" {
    const suffixes=&.{"-bar","-foo-baz","-foo-bar"};
    const order=compare("v1.8-foo-baz","v1.8-foo-bar",suffixes);
    try std.testing.expectEqual(std.math.Order.lt,order);
}
test "empty suffix places unlisted suffixes between configured prerelease and postrelease" {
    const suffixes=&.{"-alpha","","-gamma"};
    const order=compare("v1.10-unlisted","v1.10-gamma",suffixes);
    try std.testing.expectEqual(std.math.Order.lt,order);
}
