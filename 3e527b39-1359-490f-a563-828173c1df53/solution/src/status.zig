const std=@import("std");
const api=@import("main.zig").statusApi;
const g=api.shared;
const ignores=@import("ignore.zig");
const a=std.heap.page_allocator;
fn eq(x: []const u8,y: []const u8) bool { return std.mem.eql(u8,x,y); }
fn starts(x: []const u8,y: []const u8) bool { return std.mem.startsWith(u8,x,y); }
fn fmt(comptime f: []const u8,args: anytype) []const u8 { return std.fmt.allocPrint(a,f,args) catch unreachable; }
const Change=struct { path: []const u8, x: u8=' ', y: u8=' ', source: ?[]const u8=null };
const Mode=enum { no, normal, all };
fn mode(s: []const u8) ?Mode { return if (eq(s,"no") or eq(s,"false") or eq(s,"0")) .no else if (eq(s,"all")) .all else if (eq(s,"normal") or eq(s,"true") or eq(s,"yes") or eq(s,"1")) .normal else null; }
fn applyIgnore(data: []const u8,path: []const u8,current: bool) bool {
    var result=current; var lines=std.mem.splitScalar(u8,data,'\n');
    while (lines.next()) |raw| { const p=std.mem.trimEnd(u8,raw," \r"); if (p.len==0 or p[0]=='#') continue; const negate=p[0]=='!'; if (ignores.matches(if (negate) p[1..] else p,path)) result=!negate; }
    return result;
}
fn ignored(root: []const u8,repo: []const u8,path: []const u8) bool {
    var result=false;
    if (g.config("core.excludesfile")) |file| { if (g.readFile(file)) |d| result=applyIgnore(d,path,result); }
    if (g.readFile(fmt("{s}/info/exclude",.{repo}))) |d| result=applyIgnore(d,path,result);
    if (g.readFile(fmt("{s}/.gitignore",.{root}))) |d| result=applyIgnore(d,path,result);
    var offset: usize=0;
    while (std.mem.indexOfScalarPos(u8,path,offset,'/')) |n| { if (g.readFile(fmt("{s}/{s}/.gitignore",.{root,path[0..n]}))) |d| result=applyIgnore(d,path[n+1..],result); offset=n+1; }
    return result;
}
fn quote(path: []const u8) []const u8 {
    if (std.mem.indexOfAny(u8,path," \"\\\n\r\t")==null) return path;
    var b: std.ArrayList(u8)=.empty; b.append(a,'"') catch unreachable;
    for (path) |c| b.appendSlice(a,switch (c) { '"'=>"\\\"", '\\'=>"\\\\", '\n'=>"\\n", '\r'=>"\\r", '\t'=>"\\t", else=>&.{c} }) catch unreachable;
    b.append(a,'"') catch unreachable; return b.toOwnedSlice(a) catch unreachable;
}
fn append(b: *std.ArrayList(u8),s: []const u8) void { b.appendSlice(a,s) catch unreachable; }
fn unique(paths: *std.ArrayList([]const u8),path: []const u8) void { for (paths.items) |p| { if (eq(p,path)) return; } paths.append(a,path) catch unreachable; }
fn less(_: void,x: []const u8,y: []const u8) bool { return std.mem.lessThan(u8,x,y); }
fn display(root: []const u8,path: []const u8,relative: bool,nul: bool) []const u8 {
    const p=if (relative) std.fs.path.relative(a,g.directory(),null,g.directory(),fmt("{s}/{s}",.{root,path})) catch path else path;
    const result=if (std.mem.endsWith(u8,path,"/") and !std.mem.endsWith(u8,p,"/")) fmt("{s}/",.{p}) else p;
    return if (nul) result else quote(result);
}
pub fn run(args: []const []const u8) u8 {
    const repo=g.repository() orelse return g.fail("not a git repository"); const root=std.fs.path.dirname(repo) orelse return 128;
    var short=eq(g.config("status.short") orelse "false","true"); var porcelain=false; var nul=false; var branch=eq(g.config("status.branch") orelse "false","true"); var brancharg=false; var showignored=false; var verbose: usize=0;
    var untracked=mode(g.config("status.showuntrackedfiles") orelse "normal") orelse return g.fail("Invalid untracked files mode");
    var paths: std.ArrayList([]const u8)=.empty; var after=false;
    for (args) |s| {
        if (eq(s,"--")) { after=true; continue; } if (after) { paths.append(a,s) catch unreachable; continue; }
        if (eq(s,"--short")) short=true else if (eq(s,"--long") or eq(s,"--no-short")) short=false else if (eq(s,"--porcelain") or eq(s,"--porcelain=v1") or eq(s,"--porcelain=1")) { porcelain=true; short=true; }
        else if (eq(s,"-z") or eq(s,"--null")) { nul=true; porcelain=true; short=true; }
        else if (eq(s,"--branch")) { branch=true; brancharg=true; } else if (eq(s,"--no-branch")) { branch=false; brancharg=true; } else if (eq(s,"--ignored") or starts(s,"--ignored=")) showignored=true
        else if (eq(s,"-u") or eq(s,"--untracked-files")) untracked=.all else if (starts(s,"-u")) untracked=mode(s[2..]) orelse return 129 else if (starts(s,"--untracked-files=")) untracked=mode(s[18..]) orelse return 129
        else if (starts(s,"--column") or starts(s,"--no-column") or starts(s,"--ignore-submodules") or eq(s,"--no-ahead-behind") or eq(s,"--ahead-behind")) {}
        else if (starts(s,"-")) { for (s[1..]) |c| { switch (c) { 's'=>short=true, 'b'=>{ branch=true; brancharg=true; }, 'v'=>verbose+=1, else=>return 129 } } }
        else paths.append(a,s) catch unreachable;
    }
    if (porcelain and !brancharg) branch=false;
    const index=g.index(); var head: std.ArrayList(g.EntryType)=.empty; const headid=g.objectId("HEAD"); if (headid) |id| { _=g.treeEntries(id,"",&head); }
    var changes: std.ArrayList(Change)=.empty;
    for (index) |e| {
        var c=Change{.path=e.path}; const baseline=api.entry(head.items,e.path);
        c.x=if (e.stage!=0) 'U' else if (baseline) |h| (if (!eq(e.oid,h.oid) or e.mode!=h.mode) 'M' else ' ') else 'A';
        if (g.readFile(fmt("{s}/{s}",.{root,e.path}))) |data| { const oid=api.hash("blob",api.filter(data,e.path,false),false) orelse return 1; if (!eq(oid,e.oid)) c.y='M'; } else c.y='D';
        if (c.x!=' ' or c.y!=' ') changes.append(a,c) catch unreachable;
    }
    for (head.items) |h| { if (api.entry(index,h.path)==null) changes.append(a,.{.path=h.path,.x='D'}) catch unreachable; }
    // Exact-content renames need no similarity heuristics.
    for (changes.items) |*c| { if (c.x!='A') continue; const new=api.entry(index,c.path).?;
        for (changes.items) |*old| { if (old.x!='D') continue; const baseline=api.entry(head.items,old.path).?; if (eq(new.oid,baseline.oid)) { c.x='R'; c.source=old.path; old.x=' '; break; } }
    }
    var untrackedpaths: std.ArrayList([]const u8)=.empty; var ignoredpaths: std.ArrayList([]const u8)=.empty; var files: std.ArrayList(g.EntryType)=.empty;
    if (untracked!=.no or showignored) g.files(root,&files);
    for (files.items) |f| {
        const path=if (starts(f.path,fmt("{s}/",.{root}))) f.path[root.len+1..] else f.path;
        if (api.entry(index,path)!=null) continue; const skip=ignored(root,repo,path);
        if (skip and !showignored) continue; if (!skip and untracked==.no) continue;
        var name=path;
        if (untracked!=.all) { var offset: usize=0; while (std.mem.indexOfScalarPos(u8,path,offset,'/')) |n| {
            const dir=path[0..n+1]; var tracked=false; for (index) |e| { if (starts(e.path,dir)) { tracked=true; break; } }
            if (!tracked) { name=dir; break; } offset=n+1;
        } }
        if (skip) unique(&ignoredpaths,name) else unique(&untrackedpaths,name);
    }
    std.mem.sort(Change,changes.items,{},struct { fn order(_: void,x: Change,y: Change) bool { return std.mem.lessThan(u8,x.path,y.path); } }.order);
    std.mem.sort([]const u8,untrackedpaths.items,{},less); std.mem.sort([]const u8,ignoredpaths.items,{},less);
    const rawhead=g.readFile(fmt("{s}/HEAD",.{repo})) orelse ""; const attached=starts(rawhead,"ref: refs/heads/"); const name=if (attached) std.mem.trim(u8,rawhead[16..],"\r\n") else "HEAD (no branch)";
    const upstream=if (attached) g.config(fmt("branch.{s}.merge",.{name})) else null; const upname=if (upstream) |u| (if (starts(u,"refs/heads/")) u[11..] else u) else "";
    var ahead: usize=0; var behind: usize=0;
    if (upstream) |u| { if (g.objectId(u)) |up| { if (headid) |id| {
        var local=std.StringHashMap(void).init(a); var remote=std.StringHashMap(void).init(a); api.ancestorsOf(&.{id},&local,false); api.ancestorsOf(&.{up},&remote,false);
        var left=local.keyIterator(); while (left.next()) |oid| { if (!remote.contains(oid.*)) ahead+=1; } var right=remote.keyIterator(); while (right.next()) |oid| { if (!local.contains(oid.*)) behind+=1; }
    } } }
    const relative=!porcelain and !eq(g.config("status.relativepaths") orelse "true","false");
    if (short) {
        if (branch) { g.output(fmt("## {s}",.{if (headid==null) fmt("No commits yet on {s}",.{name}) else name})); if (upstream!=null) { g.output(fmt("...{s}",.{upname})); if (ahead>0 or behind>0) g.output(if (ahead>0 and behind>0) fmt(" [ahead {d}, behind {d}]",.{ahead,behind}) else if (ahead>0) fmt(" [ahead {d}]",.{ahead}) else fmt(" [behind {d}]",.{behind})); } g.output(if (nul) "\x00" else "\n"); }
        for (changes.items) |c| { if (c.x==' ' and c.y==' ') continue; if (!matches(c.path,paths.items)) continue;
            g.output(fmt("{c}{c} {s}",.{c.x,c.y,if (c.source!=null and !nul) fmt("{s} -> {s}",.{display(root,c.source.?,relative,false),display(root,c.path,relative,false)}) else display(root,c.path,relative,nul)})); g.output(if (nul) "\x00" else "\n"); if (nul and c.source!=null) { g.output(c.source.?); g.output("\x00"); }
        }
        for (untrackedpaths.items) |p| { if (matches(p,paths.items)) { g.output(fmt("?? {s}",.{display(root,p,relative,nul)})); g.output(if (nul) "\x00" else "\n"); } }
        for (ignoredpaths.items) |p| { if (matches(p,paths.items)) { g.output(fmt("!! {s}",.{display(root,p,relative,nul)})); g.output(if (nul) "\x00" else "\n"); } }
        return 0;
    }
    var b: std.ArrayList(u8)=.empty; const hints=!eq(g.config("advice.statushints") orelse "true","false");
    append(&b,if (attached) fmt("On branch {s}\n",.{name}) else "HEAD detached\n");
    if (upstream!=null) {
        if (ahead>0 and behind>0) { append(&b,fmt("Your branch and '{s}' have diverged,\nand have {d} and {d} different commits each, respectively.\n",.{upname,ahead,behind})); if (hints) append(&b,"  (use \"git pull\" if you want to integrate the remote branch with yours)\n"); }
        else if (ahead>0) { append(&b,fmt("Your branch is ahead of '{s}' by {d} commit{s}.\n",.{upname,ahead,if (ahead==1) "" else "s"})); if (hints) append(&b,"  (use \"git push\" to publish your local commits)\n"); }
        else if (behind>0) { append(&b,fmt("Your branch is behind '{s}' by {d} commit{s}, and can be fast-forwarded.\n",.{upname,behind,if (behind==1) "" else "s"})); if (hints) append(&b,"  (use \"git pull\" to update your local branch)\n"); }
        else append(&b,fmt("Your branch is up to date with '{s}'.\n",.{upname})); append(&b,"\n");
    }
    if (headid==null) append(&b,"\nNo commits yet\n\n");
    var staged=false; var unstaged=false;
    for (changes.items) |c| { if (!matches(c.path,paths.items)) continue; if (c.x!=' ') staged=true; if (c.y!=' ') unstaged=true; }
    if (staged or unstaged or untrackedpaths.items.len>0 or ignoredpaths.items.len>0) { if (upstream==null and headid!=null) append(&b,"\n"); }
    for ([_]bool{true,false}) |indexside| {
        if (if (indexside) !staged else !unstaged) continue;
        append(&b,if (indexside) "Changes to be committed:\n" else "Changes not staged for commit:\n");
        if (hints) { if (indexside) append(&b,if (headid==null) "  (use \"git rm --cached <file>...\" to unstage)\n" else "  (use \"git restore --staged <file>...\" to unstage)\n") else append(&b,"  (use \"git add <file>...\" to update what will be committed)\n  (use \"git restore <file>...\" to discard changes in working directory)\n"); }
        for (changes.items) |c| { const code=if (indexside) c.x else c.y; if (code==' ' or !matches(c.path,paths.items)) continue;
            append(&b,fmt("\t{s}{s}\n",.{switch (code) { 'A'=>"new file:   ", 'D'=>"deleted:    ", 'R'=>"renamed:    ", 'U'=>"both modified:   ", else=>"modified:   " },if (c.source) |src| fmt("{s} -> {s}",.{display(root,src,relative,false),display(root,c.path,relative,false)}) else display(root,c.path,relative,false)}));
        } append(&b,"\n");
    }
    for ([_]bool{false,true}) |ignoredside| {
        const items=if (ignoredside) ignoredpaths.items else untrackedpaths.items; if (items.len==0) continue;
        append(&b,if (ignoredside) "Ignored files:\n" else "Untracked files:\n");
        if (hints) append(&b,if (ignoredside) "  (use \"git add -f <file>...\" to include in what will be committed)\n" else "  (use \"git add <file>...\" to include in what will be committed)\n");
        for (items) |p| { if (matches(p,paths.items)) append(&b,fmt("\t{s}\n",.{display(root,p,relative,false)})); } append(&b,"\n");
    }
    if (untracked==.no) append(&b,if (hints) "Untracked files not listed (use -u option to show untracked files)\n" else "Untracked files not listed\n")
    else if (!staged and !unstaged) append(&b,if (untrackedpaths.items.len>0) "nothing added to commit but untracked files present (use \"git add\" to track)\n" else "nothing to commit, working tree clean\n")
    else if (!staged) append(&b,"no changes added to commit (use \"git add\" and/or \"git commit -a\")\n");
    if (eq(g.config("status.displaycommentprefix") orelse "false","true")) {
        var lines=std.mem.splitScalar(u8,std.mem.trimEnd(u8,b.items,"\n"),'\n'); while (lines.next()) |l| { g.output(if (l.len==0 or l[0]=='\t') "#" else "# "); g.printLine(l); }
    } else g.output(b.items);
    if (verbose>0) { if (verbose>1) g.printLine("Changes to be committed:"); _=api.diff(&.{"--cached"},"diff"); if (verbose>1) { g.printLine("--------------------------------------------------\nChanges not staged for commit:"); _=api.diff(&.{},"diff"); } }
    return 0;
}
fn matches(path: []const u8,patterns: []const []const u8) bool {
    if (patterns.len==0) return true;
    for (patterns) |p| { if (eq(p,".") or eq(path,p) or starts(path,fmt("{s}/",.{p})) or ignores.matches(p,path)) return true; } return false;
}
