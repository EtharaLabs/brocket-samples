const std = @import("std");
const api = @import("main.zig").tagApi;
const g = api.shared;
const a = std.heap.page_allocator;
const eq = g.equal;
const starts = g.startsWith;
const fmt = g.format;
extern "c" fn fnmatch([*:0]const u8, [*:0]const u8, c_int) c_int;
fn z(s: []const u8) [:0]const u8 { const b=a.allocSentinel(u8,s.len,0) catch unreachable; @memcpy(b,s); return b; }
fn folded(s: []const u8) []const u8 { const b=a.dupe(u8,s) catch unreachable; for (b) |*c| c.*=std.ascii.toLower(c.*); return b; }
const Mode = enum { create, list, delete, verify };
const FilterKind = enum { contains, excludes, merged, unmerged, points };
const Filter = struct { kind: FilterKind, oid: []const u8 };
const Options = struct {
    mode: Mode=.create, annotated: bool=false, force: bool=false, insensitive: bool=false,
    message: ?[]const u8=null, file: ?[]const u8=null, cleanup: []const u8="strip",
    lines: usize=0, format: ?[]const u8=null, sort: []const u8="refname", log: i8=0,
    omit: bool=false, column: bool=false, edit: bool=false, sign: bool=false,
    suffixes: std.ArrayList([]const u8)=.empty,
    names: std.ArrayList([]const u8)=.empty, filters: std.ArrayList(Filter)=.empty,
};
fn peel(id: []const u8) ?[]const u8 {
    var oid=id;
    for (0..32) |_| { const obj=g.object(oid) orelse return null; if (!eq(obj.typ,"tag")) return if (eq(obj.typ,"commit")) oid else null; oid=api.headerValue(obj.data,"object") orelse return null; }
    return null;
}
fn reachable(tip: []const u8, wanted: []const u8) bool {
    var seen=std.StringHashMap(void).init(a); api.ancestorsOf(&.{tip},&seen,false); return seen.contains(wanted);
}
fn accepts(ref: api.RefType, filters: []const Filter) bool {
    var points=false; var point_match=false; var contains=false; var contains_match=false;
    for (filters) |f| switch (f.kind) {
        .points => { points=true; const obj=g.object(ref.oid) orelse continue; if (eq(ref.oid,f.oid) or (eq(obj.typ,"tag") and eq(api.headerValue(obj.data,"object") orelse "",f.oid))) point_match=true; },
        .contains => { contains=true; const tip=peel(ref.oid) orelse continue; if (reachable(tip,f.oid)) contains_match=true; },
        .excludes => { const tip=peel(ref.oid) orelse return false; if (reachable(tip,f.oid)) return false; },
        .merged => { const tip=peel(ref.oid) orelse return false; if (!reachable(f.oid,tip)) return false; },
        .unmerged => { const tip=peel(ref.oid) orelse return false; if (reachable(f.oid,tip)) return false; },
    };
    return (!points or point_match) and (!contains or contains_match);
}
fn less(o: Options, x: api.RefType, y: api.RefType) bool {
    var key=o.sort; const reverse=starts(key,"-"); if (reverse) key=key[1..]; const version=starts(key,"version:") or starts(key,"v:"); if (version) key=key[(std.mem.indexOfScalar(u8,key,':') orelse 0)+1..];
    var xx=api.atom(x,key) orelse ""; var yy=api.atom(y,key) orelse "";
    if (o.insensitive) { xx=folded(xx); yy=folded(yy); }
    const order=if (version) @import("tagorder.zig").compare(xx,yy,o.suffixes.items) else std.mem.order(u8,xx,yy);
    if (order==.eq) return std.mem.lessThan(u8,x.name,y.name);
    return if (reverse) order==.gt else order==.lt;
}
fn render(ref: api.RefType, format: []const u8) ?[]const u8 {
    var b: std.ArrayList(u8)=.empty; var i: usize=0;
    while (i<format.len) {
        if (starts(format[i..],"%(")) { const end=std.mem.indexOfScalarPos(u8,format,i+2,')') orelse return null; const value=api.atom(ref,format[i+2..end]) orelse return null; b.appendSlice(a,value) catch unreachable; i=end+1; }
        else if (format[i]=='%' and i+2<format.len) { const c=std.fmt.parseInt(u8,format[i+1..i+3],16) catch { b.append(a,format[i]) catch unreachable; i+=1; continue; }; b.append(a,c) catch unreachable; i+=3; }
        else { b.append(a,format[i]) catch unreachable; i+=1; }
    }
    return b.items;
}
fn list(o: Options) u8 {
    var key=o.sort; if (starts(key,"-")) key=key[1..]; if (starts(key,"version:") or starts(key,"v:")) key=key[(std.mem.indexOfScalar(u8,key,':') orelse 0)+1..];
    if (!eq(key,"refname") and !eq(key,"tag") and !eq(key,"objecttype") and !eq(key,"taggerdate") and !eq(key,"creatordate")) return g.fail(fmt("unknown field name: {s}",.{key}));
    const refs=g.references(); std.mem.sort(api.RefType,refs,o,less);
    for (refs) |r| {
        if (!starts(r.name,"refs/tags/")) continue; const name=r.name[10..]; var matched=o.names.items.len==0;
        for (o.names.items) |p| { if (fnmatch(z(if (o.insensitive) folded(p) else p),z(if (o.insensitive) folded(name) else name),0)==0) matched=true; }
        if (!matched or !accepts(r,o.filters.items)) continue;
        if (o.format) |f| { const value=render(r,f) orelse return g.fail("unable to parse format"); if (!o.omit or value.len>0) g.printLine(value); }
        else if (o.lines==0) g.printLine(name)
        else { const obj=g.object(r.oid) orelse continue; const message=if (eq(obj.typ,"tag") or eq(obj.typ,"commit")) if (std.mem.indexOf(u8,obj.data,"\n\n")) |p| std.mem.trimEnd(u8,obj.data[p+2..],"\n") else "" else "";
            var lines=std.mem.splitScalar(u8,message,'\n'); var n: usize=0;
            while (lines.next()) |text| { if (n>=o.lines) break; if (n==0) { g.printError(1,name); for (0..if (name.len<16) 16-name.len else 1) |_| g.printError(1," "); } else g.printError(1,"    "); g.printLine(text); n+=1; }
        }
    }
    return 0;
}
pub fn run(args: []const []const u8) u8 {
    var o=Options{.sort=g.setting("tag.sort") orelse "refname"}; var i: usize=0; var positional=false;
    const config=api.configEntries(); var modern=false;
    for (config) |e| { if (eq(e.key,"versionsort.suffix") and !e.implicit) modern=true; }
    for ([_][]const u8{"versionsort.suffix","versionsort.prereleasesuffix"}) |key| {
        for (config) |e| { if (!eq(e.key,key)) continue; if (e.implicit) { g.printError(2,fmt("error: missing value for '{s}'\n",.{key})); continue; } if (eq(key,"versionsort.suffix") or !modern) o.suffixes.append(a,e.value) catch unreachable; }
    }
    while (i<args.len) : (i+=1) {
        const s=args[i];
        if (positional) { o.names.append(a,s) catch unreachable; continue; }
        if (eq(s,"--")) { positional=true; continue; }
        if (eq(s,"-l") or eq(s,"--list") or eq(s,"-d") or eq(s,"--delete") or eq(s,"-v") or eq(s,"--verify")) {
            const mode: Mode=if (eq(s,"-l") or eq(s,"--list")) .list else if (eq(s,"-d") or eq(s,"--delete")) .delete else .verify;
            if (o.mode!=.create and o.mode!=mode) return 129; o.mode=mode;
        } else if (eq(s,"-m") or eq(s,"--message") or eq(s,"-F") or eq(s,"--file")) {
            i+=1; if (i==args.len) return 129; o.annotated=true;
            if (eq(s,"-F") or eq(s,"--file")) { if (o.message!=null) return 129; o.file=args[i]; }
            else { if (o.file!=null) return 129; o.message=if (o.message) |m| fmt("{s}\n\n{s}",.{m,args[i]}) else args[i]; }
        } else if (eq(s,"-a") or eq(s,"--annotate")) o.annotated=true
        else if (eq(s,"-s") or eq(s,"--sign") or eq(s,"-u")) { o.sign=true; o.annotated=true; if (eq(s,"-u")) { i+=1; if (i==args.len) return 129; } }
        else if (eq(s,"--no-sign")) o.sign=false
        else if (eq(s,"-f") or eq(s,"--force")) o.force=true
        else if (eq(s,"-i") or eq(s,"--ignore-case")) o.insensitive=true
        else if (eq(s,"--create-reflog")) o.log=1
        else if (eq(s,"--omit-empty")) o.omit=true
        else if (eq(s,"--edit") or eq(s,"-e")) o.edit=true
        else if (starts(s,"--cleanup=")) o.cleanup=s[10..]
        else if (starts(s,"--column")) o.column=true
        else if (eq(s,"--no-column")) o.column=false
        else if (starts(s,"--color") or eq(s,"--no-color")) {}
        else if (starts(s,"--sort=")) o.sort=s[7..]
        else if (eq(s,"--no-sort")) o.sort="refname"
        else if (starts(s,"--format=")) { o.format=s[9..]; if (o.mode==.create) o.mode=.list; }
        else if (starts(s,"-n")) { if (o.mode!=.create and o.mode!=.list) return 129; o.mode=.list; o.lines=if (s.len==2) 1 else std.fmt.parseInt(usize,s[2..],10) catch return 129; }
        else if (starts(s,"--contains") or eq(s,"--with") or starts(s,"--no-contains") or eq(s,"--without") or starts(s,"--merged") or starts(s,"--no-merged") or starts(s,"--points-at")) {
            if (o.mode!=.create and o.mode!=.list) return 129; o.mode=.list;
            const kind: FilterKind=if (starts(s,"--points-at")) .points else if (starts(s,"--no-merged")) .unmerged else if (starts(s,"--merged")) .merged else if (starts(s,"--no-contains") or eq(s,"--without")) .excludes else .contains;
            var value: []const u8="HEAD";
            if (std.mem.indexOfScalar(u8,s,'=')) |pos| value=s[pos+1..] else if (i+1<args.len and !starts(args[i+1],"-")) { i+=1; value=args[i]; }
            const oid=g.objectId(value) orelse return g.fail(fmt("malformed object name {s}",.{value}));
            const target=if (kind==.points) oid else peel(oid) orelse return g.fail(fmt("object {s} is a non-commit",.{value})); o.filters.append(a,.{.kind=kind,.oid=target}) catch unreachable;
        } else if (starts(s,"-")) return 129 else o.names.append(a,s) catch unreachable;
    }
    if (o.filters.items.len>0 and o.mode!=.list) return 129;
    if (o.mode==.create and o.names.items.len==0) { if (o.annotated or o.force) return 129; o.mode=.list; }
    switch (o.mode) {
        .list => { if (o.annotated or o.force or (o.column and o.lines>0)) return 129; return list(o); },
        .delete, .verify => { if (o.annotated or o.force or o.lines>0) return 129; var rc: u8=0;
            for (o.names.items) |name| { const ref=fmt("refs/tags/{s}",.{name}); const oid=g.objectId(ref) orelse { g.printError(2,fmt("error: tag '{s}' not found.\n",.{name})); rc=1; continue; };
                if (o.mode==.verify) { g.printError(2,"error: no signature found\n"); rc=1; continue; }
                if (g.update(ref,null,null,false,"",0)!=0) rc=1 else g.printLine(fmt("Deleted tag '{s}' (was {s})",.{name,oid[0..7]}));
            } return rc;
        },
        .create => {},
    }
    if (o.names.items.len>2) return 129;
    const name=o.names.items[0]; const ref=fmt("refs/tags/{s}",.{name});
    if (eq(name,"HEAD") or !g.validName(ref,true)) return g.fail(fmt("'{s}' is not a valid tag name.",.{name}));
    const old=g.objectId(ref); if (!o.force and old!=null) return g.fail(fmt("tag '{s}' already exists",.{name}));
    const target=if (o.names.items.len>1) o.names.items[1] else "HEAD";
    var oid=g.objectId(target) orelse return g.fail(fmt("Failed to resolve '{s}' as a valid ref.",.{target}));
    if (o.sign) return g.fail("tag signing is not supported");
    if (o.edit or (o.annotated and o.message==null and o.file==null)) return g.fail("no editor is available");
    if (o.annotated) {
        const raw=o.message orelse if (o.file) |p| (if (eq(p,"-")) api.input() else g.readFile(p) orelse return g.fail(fmt("could not open '{s}'",.{p}))) else "";
        if (!eq(o.cleanup,"strip") and !eq(o.cleanup,"whitespace") and !eq(o.cleanup,"verbatim")) return g.fail("Invalid cleanup mode");
        const message=@import("tagtext.zig").clean(a,raw,o.cleanup);
        const obj=g.object(oid) orelse return 128; const data=fmt("object {s}\ntype {s}\ntag {s}\ntagger {s}\n\n{s}",.{oid,obj.typ,name,g.identity(true) orelse return 128,message});
        oid=api.hash("tag",data,true) orelse return 1;
        if (eq(obj.typ,"tag") and !eq(g.setting("advice.nestedtag") orelse "true","false")) g.printError(2,fmt("hint: You have created a nested tag. The object referred to by your new tag is\nhint: already a tag. If you meant to tag the object that it points to, use:\nhint:\nhint: \tgit tag -f {s} {s}^{{}}\nhint: Disable this message with \"git config set advice.nestedTag false\"\n",.{name,target}));
    }
    const commit=peel(oid); var logmessage: []const u8="tag: tagging";
    if (commit) |c| { const obj=g.object(c).?; const identity=api.headerValue(obj.data,"committer") orelse ""; const gt=std.mem.lastIndexOfScalar(u8,identity,'>') orelse identity.len;
        logmessage=fmt("tag: tagging {s} ({s}, {s})",.{c[0..7],api.atom(.{.name="",.oid=c},"subject") orelse "",api.date(std.mem.trim(u8,identity[@min(gt+1,identity.len)..]," "),"short")}); }
    const rc=g.update(ref,oid,null,false,logmessage,o.log);
    if (rc==0 and old!=null and !eq(old.?,oid)) g.printLine(fmt("Updated tag '{s}' (was {s})",.{name,old.?[0..7]}));
    return rc;
}
