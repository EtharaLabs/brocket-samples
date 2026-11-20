const std=@import("std");
const g=@import("main.zig").grepApi;
const exprlib=@import("grepexpr.zig");
const a=std.heap.page_allocator;
const Pattern=struct { text: []const u8, regex: ?*anyopaque=null };
const Span=struct { first: usize, last: usize };
const Options=struct { numbered: bool=false, column: bool=false, ignore: bool=false, fixed: bool=false, extended: bool=false, word: bool=false, invert: bool=false, list: bool=false, listnot: bool=false, count: bool=false, quiet: bool=false, filename: bool=true, cached: bool=false, nul: bool=false, noindex: bool=false, only: bool=false, full: bool=false, binary_ignore: bool=false, text: bool=false, all: bool=false, before: usize=0, after: usize=0, limit: usize=std.math.maxInt(usize), showfunc: bool=false, depth: usize=std.math.maxInt(usize), fullname: bool=false };
extern "c" fn regcomp(*anyopaque,[*:0]const u8,c_int) c_int;
extern "c" fn regexec(*const anyopaque,[*:0]const u8,usize,?*anyopaque,c_int) c_int;
extern "c" fn fnmatch([*:0]const u8,[*:0]const u8,c_int) c_int;
fn eq(x: []const u8,y: []const u8) bool { return std.mem.eql(u8,x,y); }
fn starts(x: []const u8,y: []const u8) bool { return std.mem.startsWith(u8,x,y); }
fn fmt(comptime f: []const u8,args: anytype) []const u8 { return std.fmt.allocPrint(a,f,args) catch unreachable; }
fn lower(s: []const u8) []const u8 { const b=a.dupe(u8,s) catch unreachable; for (b) |*c| c.*=std.ascii.toLower(c.*); return b; }
fn wordChar(c: u8) bool { return std.ascii.isAlphanumeric(c) or c=='_' or c>=128; }
fn addPattern(patterns: *std.ArrayList(Pattern),tokens: *std.ArrayList(exprlib.Token),text: []const u8) void {
    var lines=std.mem.splitScalar(u8,text,'\n');
    while (lines.next()) |l| { tokens.append(a,.{.pattern=patterns.items.len}) catch unreachable; patterns.append(a,.{.text=l}) catch unreachable; }
}
fn search(p: Pattern,l: []const u8,from: usize,o: Options) ?Span {
    var begin=from;
    while (begin<=l.len) {
        var first: usize=0; var last: usize=0;
        if (o.fixed) { const hay=if (o.ignore) lower(l[begin..]) else l[begin..]; const needle=if (o.ignore) lower(p.text) else p.text; const pos=std.mem.indexOf(u8,hay,needle) orelse return null; first=begin+pos; last=first+p.text.len; }
        else { const Offset=if (@import("builtin").os.tag==.macos) i64 else c_int; var offsets: [2]Offset=undefined; if (regexec(p.regex.?,g.terminated(l[begin..]),1,&offsets,if (begin>0) 1 else 0)!=0 or offsets[0]<0) return null; first=begin+@as(usize,@intCast(offsets[0])); last=begin+@as(usize,@intCast(offsets[1])); }
        if ((!o.word or ((first==0 or !wordChar(l[first-1])) and (last==l.len or !wordChar(l[last])))) and (!o.full or (first==0 and last==l.len))) return .{.first=first,.last=last};
        begin=first+1;
    }
    return null;
}
fn prefix(name: []const u8,number: usize,span: Span,sep: []const u8,o: Options) void {
    if (o.filename) { g.output(name); g.output(if (o.nul) "\x00" else sep); }
    if (o.numbered) g.output(fmt("{d}{s}",.{number,sep}));
    if (o.column and eq(sep,":")) g.output(fmt("{d}:",.{span.first+1}));
}
fn quote(path: []const u8) []const u8 {
    if (std.mem.indexOfAny(u8,path,"\"\\\n\r\t")==null) return path;
    var buf: std.ArrayList(u8)=.empty; buf.append(a,'"') catch unreachable;
    for (path) |c| { buf.appendSlice(a,switch (c) { '"'=>"\\\"", '\\'=>"\\\\", '\n'=>"\\n", '\r'=>"\\r", '\t'=>"\\t", else=>&.{c} }) catch unreachable; }
    buf.append(a,'"') catch unreachable; return buf.toOwnedSlice(a) catch unreachable;
}
pub fn run(args: []const []const u8) u8 {
    var patterns: std.ArrayList(Pattern)=.empty; var tokens: std.ArrayList(exprlib.Token)=.empty; var paths: std.ArrayList([]const u8)=.empty; var target: ?[]const u8=null;
    var o=Options{}; o.numbered=eq(g.config("grep.linenumber") orelse "false","true"); o.column=eq(g.config("grep.column") orelse "false","true");
    const configured=g.config("grep.patterntype") orelse "default"; o.fixed=eq(configured,"fixed"); o.extended=eq(configured,"extended") or (eq(configured,"default") and eq(g.config("grep.extendedregexp") orelse "false","true"));
    var after=false; var i: usize=0; var patternfile=false;
    while (i<args.len) : (i+=1) { const s=args[i];
        if (eq(s,"--")) { after=true; continue; }
        if (after) { if (patterns.items.len==0 and !patternfile) addPattern(&patterns,&tokens,s) else paths.append(a,s) catch unreachable; continue; }
        if (eq(s,"-e") or eq(s,"-f")) {
            i+=1; if (i==args.len) return 129;
            if (eq(s,"-f")) { patternfile=true; const data=if (eq(args[i],"-")) g.input() else g.readFile(args[i]) orelse return 128; var lines=std.mem.splitScalar(u8,data,'\n'); while (lines.next()) |l| { if (l.len>0) addPattern(&patterns,&tokens,l); } }
            else addPattern(&patterns,&tokens,args[i]);
        }
        else if (eq(s,"--and")) tokens.append(a,.conjunction) catch unreachable else if (eq(s,"--or")) tokens.append(a,.disjunction) catch unreachable else if (eq(s,"--not")) tokens.append(a,.negation) catch unreachable else if (eq(s,"(")) tokens.append(a,.open) catch unreachable else if (eq(s,")")) tokens.append(a,.close) catch unreachable
        else if (eq(s,"--cached")) o.cached=true else if (eq(s,"--no-index") or eq(s,"--untracked")) o.noindex=true else if (eq(s,"--column")) o.column=true else if (eq(s,"--no-column")) o.column=false else if (eq(s,"--line-number")) o.numbered=true else if (eq(s,"--no-line-number")) o.numbered=false
        else if (eq(s,"--fixed-strings")) { o.fixed=true; o.extended=false; } else if (eq(s,"--extended-regexp")) { o.extended=true; o.fixed=false; } else if (eq(s,"--basic-regexp")) { o.extended=false; o.fixed=false; }
        else if (eq(s,"--ignore-case")) o.ignore=true else if (eq(s,"--word-regexp")) o.word=true else if (eq(s,"--invert-match")) o.invert=true else if (eq(s,"--files-with-matches")) o.list=true else if (eq(s,"--files-without-match")) o.listnot=true else if (eq(s,"--count")) o.count=true else if (eq(s,"--quiet")) o.quiet=true else if (eq(s,"--no-filename")) o.filename=false else if (eq(s,"--full-name")) o.fullname=true else if (eq(s,"--all-match")) o.all=true else if (eq(s,"--text")) o.text=true else if (eq(s,"--show-function")) o.showfunc=true
        else if (eq(s,"--recursive")) o.depth=std.math.maxInt(usize) else if (eq(s,"--no-recursive")) o.depth=0
        else if (eq(s,"--max-depth") or starts(s,"--max-depth=")) { const val=if (starts(s,"--max-depth=")) s[12..] else blk: { i+=1; if (i==args.len) return 129; break :blk args[i]; }; const n=std.fmt.parseInt(i64,val,10) catch return 129; o.depth=if (n<0) std.math.maxInt(usize) else @intCast(n); }
        else if (eq(s,"--max-count") or starts(s,"--max-count=") or eq(s,"--context") or starts(s,"--context=") or eq(s,"--before-context") or starts(s,"--before-context=") or eq(s,"--after-context") or starts(s,"--after-context=")) {
            const equal=std.mem.indexOfScalar(u8,s,'='); const opt=if (equal) |p| s[0..p] else s;
            const val=if (equal) |p| s[p+1..] else blk: { i+=1; if (i==args.len) return 129; break :blk args[i]; };
            const n=std.fmt.parseInt(i64,val,10) catch return 129;
            if (eq(opt,"--max-count")) o.limit=if (n<0) std.math.maxInt(usize) else @intCast(n)
            else { if (n<0) return 129; if (!eq(opt,"--after-context")) o.before=@intCast(n); if (!eq(opt,"--before-context")) o.after=@intCast(n); }
        }
        else if (starts(s,"--")) { if (eq(s,"--threads")) i+=1 else if (!starts(s,"--color") and !starts(s,"--threads=")) return 129; }
        else if (starts(s,"-")) { var j: usize=1; while (j<s.len) : (j+=1) { switch (s[j]) {
            'n'=>o.numbered=true, 'i'=>o.ignore=true, 'w'=>o.word=true, 'v'=>o.invert=true, 'l'=>o.list=true, 'L'=>o.listnot=true, 'c'=>o.count=true, 'q'=>o.quiet=true, 'h'=>o.filename=false, 'H'=>o.filename=true, 'z'=>o.nul=true, 'o'=>o.only=true, 'x'=>o.full=true, 'I'=>o.binary_ignore=true, 'a'=>o.text=true, 'p'=>o.showfunc=true,
            'F'=>{ o.fixed=true; o.extended=false; }, 'E'=>{ o.extended=true; o.fixed=false; }, 'G'=>{ o.extended=false; o.fixed=false; },
            'A','B','C','m'=>|opt| { const val=if (j+1<s.len) s[j+1..] else blk: { i+=1; if (i==args.len) return 129; break :blk args[i]; }; const n=std.fmt.parseInt(usize,val,10) catch return 129; if (opt=='m') o.limit=n else { if (opt!='A') o.before=n; if (opt!='B') o.after=n; } break; },
            '0'...'9'=> { const n=std.fmt.parseInt(usize,s[j..],10) catch return 129; o.before=n; o.after=n; break; }, else=>return 129,
        } } }
        else if (patterns.items.len==0 and !patternfile) addPattern(&patterns,&tokens,s) else if (target==null and g.objectId(s)!=null) target=s else paths.append(a,s) catch unreachable;
    }
    if (patterns.items.len==0) return if (patternfile) 1 else 129;
    const expression=exprlib.Expression.parse(tokens.items) orelse return g.fail("invalid grep expression");
    for (patterns.items) |*p| { if (!o.fixed) { const storage=a.alignedAlloc(u8,.@"16",512) catch unreachable; @memset(storage,0); const regex=if (o.full) fmt("^{s}$",.{p.text}) else p.text; if (regcomp(storage.ptr,g.terminated(regex),@as(c_int,if (o.extended) 1 else 0)|@as(c_int,if (o.ignore) 2 else 0))!=0) return g.fail("invalid regular expression"); p.regex=storage.ptr; } }
    const root=if (g.repository()) |repo| std.fs.path.dirname(repo) orelse "." else g.directory();
    const cwd=g.directory(); const sub=if (cwd.len>root.len and starts(cwd,root)) cwd[root.len+1..] else "";
    var entries: std.ArrayList(g.EntryType)=.empty;
    if (target) |t| { if (!g.treeEntries(t,"",&entries)) return 128; } else if (o.noindex) g.files(".",&entries) else entries.appendSlice(a,g.index()) catch unreachable;
    std.mem.sort(g.EntryType,entries.items,{},struct { fn less(_: void,x: g.EntryType,y: g.EntryType) bool { return std.mem.lessThan(u8,x.path,y.path); } }.less);
    var found=false; var printed=false;
    for (entries.items) |e| {
        var matchpath=false;
        const requested=if (paths.items.len==0) &[_][]const u8{"."} else paths.items;
        for (requested) |p| {
            const absolute=std.fs.path.resolve(a,&.{"/",sub,p}) catch unreachable; const pattern=absolute[1..];
            const remainder=if (pattern.len==0) e.path else if (starts(e.path,fmt("{s}/",.{pattern}))) e.path[pattern.len+1..] else "";
            const wildcard=std.mem.indexOfAny(u8,pattern,"*?[")!=null;
            if ((pattern.len==0 or eq(e.path,pattern) or remainder.len>0 or fnmatch(g.terminated(pattern),g.terminated(e.path),0)==0) and (wildcard or std.mem.count(u8,remainder,"/")<=o.depth)) matchpath=true;
        }
        if (!matchpath) continue;
        const data=if (o.cached or target!=null) (g.object(e.oid) orelse continue).data else g.readFile(if (o.noindex) e.path else fmt("{s}/{s}",.{root,e.path})) orelse continue;
        const binary=std.mem.indexOfScalar(u8,data,0)!=null and !o.text; if (binary and o.binary_ignore) continue;
        const relative=if (!o.fullname and sub.len>0 and starts(e.path,fmt("{s}/",.{sub}))) e.path[sub.len+1..] else e.path;
        const display=if (o.nul) relative else quote(relative);
        const name=if (target) |t| fmt("{s}:{s}",.{t,display}) else display;
        var lines: std.ArrayList([]const u8)=.empty; var it=std.mem.splitScalar(u8,data,'\n'); var remaining=data.len;
        while (it.next()) |l| { if (remaining==0) break; remaining-=@min(remaining,l.len+1); lines.append(a,l) catch unreachable; }
        const rows=a.alloc([]bool,lines.items.len) catch unreachable;
        const selected=a.alloc(bool,lines.items.len) catch unreachable; @memset(selected,false);
        const spans=a.alloc(Span,lines.items.len) catch unreachable;
        var matches: usize=0;
        for (lines.items,0..) |l,n| {
            const values=a.alloc(bool,patterns.items.len) catch unreachable; @memset(values,false); rows[n]=values;
            var first=Span{.first=0,.last=0}; var any=false;
            for (patterns.items,0..) |p,k| { if (search(p,l,0,o)) |span| { values[k]=true; if (!any or span.first<first.first or (span.first==first.first and span.last>first.last)) first=span; any=true; } }
            spans[n]=first; const matched=expression.evaluate(expression.root,values)!=o.invert;
            if (matched and matches<o.limit) { selected[n]=true; matches+=1; }
        }
        if (o.all and !expression.allMatch(expression.root,rows)) matches=0;
        const accepted=if (o.listnot) matches==0 else matches>0;
        if (accepted) { found=true; if (o.quiet) return 0; }
        if (o.list or o.listnot) { if (accepted) { g.output(name); g.output(if (o.nul) "\x00" else "\n"); } continue; }
        if (matches==0) continue;
        if (o.count) { if (o.filename) { g.output(name); g.output(if (o.nul) "\x00" else ":"); } g.printLine(fmt("{d}",.{matches})); continue; }
        if (binary) { g.printLine(fmt("Binary file {s} matches",.{name})); continue; }
        const visible=a.alloc(bool,lines.items.len) catch unreachable; @memset(visible,false);
        const headers=a.alloc(bool,lines.items.len) catch unreachable; @memset(headers,false);
        for (selected,0..) |yes,n| { if (yes) {
            const begin=n-@min(n,o.before); const end=@min(lines.items.len,n+1+|o.after); @memset(visible[begin..end],true);
            if (o.showfunc) { var h=n; while (h>0) { h-=1; const l=lines.items[h]; if (l.len>0 and (std.ascii.isAlphabetic(l[0]) or l[0]=='_' or l[0]=='$')) { visible[h]=true; headers[h]=true; break; } } }
        } }
        var last: ?usize=null;
        for (lines.items,0..) |l,n| { if (!visible[n]) continue;
            if ((o.before>0 or o.after>0) and (if (last) |p| n>p+1 else printed)) g.printLine("--");
            const sep=if (selected[n]) ":" else if (headers[n]) "=" else "-";
            if (o.only and selected[n]) {
                var begin: usize=0; while (begin<=l.len) {
                    var best: ?Span=null; for (patterns.items) |p| { if (search(p,l,begin,o)) |span| { if (best==null or span.first<best.?.first or (span.first==best.?.first and span.last>best.?.last)) best=span; } }
                    const span=best orelse break; if (span.last>span.first) { prefix(name,n+1,span,sep,o); g.printLine(l[span.first..span.last]); }
                    begin=if (span.last>begin) span.last else begin+1;
                }
            } else { prefix(name,n+1,spans[n],sep,o); g.printLine(l); }
            printed=true; last=n;
        }
    }
    return if (found) 0 else 1;
}
