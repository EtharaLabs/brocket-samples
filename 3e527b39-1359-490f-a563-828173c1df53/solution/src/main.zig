const std = @import("std");
const packlib = @import("pack.zig");
const refstream = @import("refs.zig");
const difftext = @import("difftext.zig");
pub const tagApi = struct {
    pub const shared = refApi;
    pub const RefType = Ref;
    pub const atom = atomValue;
    pub const headerValue = header;
    pub const hash = objectHash;
    pub const input = stdin;
    pub const ancestorsOf = ancestors;
    pub const date = formatDate;
    pub const configEntries = allConfigEntries;
};
pub const refApi = struct {
    pub const allocator = a;
    pub const equal = eq;
    pub const startsWith = starts;
    pub const format = fmt;
    pub const repository = gitdir;
    pub const pathJoin = join;
    pub const readFile = load;
    pub const writeFile = put;
    pub const removeFile = remove;
    pub const makePath = mkpath;
    pub const record = inputRecord;
    pub const fail = fatal;
    pub const printLine = line;
    pub const printError = emit;
    pub const validName = validRef;
    pub const dereference = derefName;
    pub const objectId = resolve;
    pub const object = readObject;
    pub const update = updateRefValue;
    pub const append = appendFile;
    pub const identity = ident;
    pub const setting = configGet;
    pub const references = allRefs;
};
pub const grepApi = struct {
    pub const repository = gitdir;
    pub const directory = cwd;
    pub const config = configGet;
    pub const readFile = load;
    pub const input = stdin;
    pub const objectId = resolve;
    pub const object = readObject;
    pub const index = readIndex;
    pub const treeEntries = readTreeEntries;
    pub const files = collectFiles;
    pub const EntryType = IndexEntry;
    pub const output = out;
    pub const printLine = line;
    pub const fail = fatal;
    pub const terminated = z;
};
pub const statusApi = struct {
    pub const shared = grepApi;
    pub const entry = entryFor;
    pub const filter = filtered;
    pub const hash = objectHash;
    pub const ancestorsOf = ancestors;
    pub const diff = diffCommand;
};
const a = std.heap.page_allocator;
extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
extern "c" fn getcwd([*]u8, usize) ?[*:0]u8;
extern "c" fn chdir([*:0]const u8) c_int;
extern "c" fn mkdir([*:0]const u8, c_uint) c_int;
extern "c" fn access([*:0]const u8, c_int) c_int;
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
extern "c" fn fwrite([*]const u8, usize, usize, *anyopaque) usize;
extern "c" fn read(c_int, [*]u8, usize) isize;
extern "c" fn write(c_int, [*]const u8, usize) isize;
extern "c" fn compressBound(c_ulong) c_ulong;
extern "c" fn compress2([*]u8, *c_ulong, [*]const u8, c_ulong, c_int) c_int;
extern "c" fn uncompress([*]u8, *c_ulong, [*]const u8, c_ulong) c_int;
extern "c" fn time(?*i64) i64;
extern "c" fn fnmatch([*:0]const u8, [*:0]const u8, c_int) c_int;
extern "c" fn gmtime(*const i64) ?*anyopaque;
extern "c" fn strftime([*]u8, usize, [*:0]const u8, *const anyopaque) usize;
extern "c" fn regcomp(*anyopaque, [*:0]const u8, c_int) c_int;
extern "c" fn regexec(*const anyopaque, [*:0]const u8, usize, ?*anyopaque, c_int) c_int;
extern "c" fn regfree(*anyopaque) void;
extern "c" fn dup(c_int) c_int;
extern "c" fn dup2(c_int,c_int) c_int;
extern "c" fn close(c_int) c_int;
extern "c" fn fileno(*anyopaque) c_int;
extern "c" fn usleep(c_uint) c_int;

const Args = []const []const u8;
var overrides: std.StringHashMap([]const u8) = undefined;
var exec_path: []const u8 = "";
var git_dir_arg: ?[]const u8=null;
var work_tree_arg: ?[]const u8=null;
fn eq(x: []const u8, y: []const u8) bool { return std.mem.eql(u8, x, y); }
fn starts(x: []const u8, y: []const u8) bool { return std.mem.startsWith(u8, x, y); }
fn z(s: []const u8) [:0]const u8 { const b = a.allocSentinel(u8,s.len,0) catch unreachable; @memcpy(b,s); return b; }
fn fmt(comptime f: []const u8, v: anytype) []const u8 { return std.fmt.allocPrint(a, f, v) catch unreachable; }
fn env(s: []const u8) ?[]const u8 { return if (getenv(z(s))) |p| std.mem.span(p) else null; }
fn emit(fd: c_int, s: []const u8) void {
    var off: usize = 0;
    while (off < s.len) { const n = write(fd, s[off..].ptr, s.len-off); if (n <= 0) return; off += @intCast(n); }
}
fn out(s: []const u8) void { emit(1, s); }
fn line(s: []const u8) void { out(s); out("\n"); }
fn fatal(s: []const u8) u8 { emit(2, fmt("fatal: {s}\n", .{s})); return 128; }
fn cwd() []const u8 { const b = a.alloc(u8, 8192) catch unreachable; return if (getcwd(b.ptr, b.len)) |p| std.mem.span(p) else "."; }
fn join(x: []const u8, y: []const u8) []const u8 { return if (starts(y, "/")) y else fmt("{s}/{s}", .{x,y}); }
fn absolute(p: []const u8) []const u8 { return std.fs.path.resolve(a,&.{cwd(),p}) catch unreachable; }
fn exists(p: []const u8) bool { return access(z(p),0) == 0; }
fn mkpath(p: []const u8) void {
    if (p.len == 0 or eq(p,"/") or exists(p)) return;
    if (std.fs.path.dirname(p)) |d| mkpath(d);
    _ = mkdir(z(p), 0o777);
}
fn put(p: []const u8, s: []const u8) bool {
    if (std.fs.path.dirname(p)) |d| mkpath(d);
    const f = fopen(z(p), "wb") orelse return false;
    defer _ = fclose(f);
    return fwrite(s.ptr,1,s.len,f) == s.len;
}
fn load(p: []const u8) ?[]const u8 {
    const f = fopen(z(p),"rb") orelse return null;
    defer _ = fclose(f);
    var b: std.ArrayList(u8) = .empty;
    var chunk: [16384]u8 = undefined;
    while (true) { const n = fread(&chunk,1,chunk.len,f); if (n == 0) break; b.appendSlice(a,chunk[0..n]) catch unreachable; }
    return b.toOwnedSlice(a) catch unreachable;
}
fn stdin() []const u8 {
    var b: std.ArrayList(u8) = .empty;
    var chunk: [16384]u8 = undefined;
    while (true) { const n = read(0,&chunk,chunk.len); if (n <= 0) break; b.appendSlice(a,chunk[0..@intCast(n)]) catch unreachable; }
    return b.toOwnedSlice(a) catch unreachable;
}
fn inputRecord(delimiter: u8) ?[]const u8 {
    var b: std.ArrayList(u8)=.empty; var byte: [1]u8=undefined;
    while (read(0,&byte,1)>0) { if (byte[0]==delimiter) return b.toOwnedSlice(a) catch unreachable; b.append(a,byte[0]) catch unreachable; }
    return if (b.items.len>0) b.toOwnedSlice(a) catch unreachable else null;
}
fn trim(s: []const u8) []const u8 { return std.mem.trim(u8,s," \t\r\n"); }
fn lower(s: []const u8) []const u8 { const b = a.dupe(u8,s) catch unreachable; for (b) |*c| c.* = std.ascii.toLower(c.*); return b; }
fn gitdir() ?[]const u8 {
    if (git_dir_arg) |g| return absolute(g);
    if (env("GIT_DIR")) |g| return absolute(g);
    var dir = cwd();
    while (true) {
        const g = join(dir,".git");
        if (exists(join(g,"HEAD"))) return g;
        if (exists(join(dir,"HEAD")) and exists(join(dir,"objects"))) return dir;
        dir = std.fs.path.dirname(dir) orelse return null;
        if (eq(dir,"/")) return null;
    }
}
const Entry = struct { key: []const u8, value: []const u8, implicit: bool=false, start: usize=0, end: usize=0, origin: []const u8="", scope: []const u8="local", line_number: usize=1 };
const ConfigSection=struct { name: []const u8, start: usize, body: usize, end: usize };
const ConfigDoc=struct { data: []const u8, entries: []Entry, sections: []ConfigSection };
var config_error: ?[]const u8=null;
fn canonicalKey(key: []const u8) []const u8 {
    const first=std.mem.indexOfScalar(u8,key,'.') orelse return lower(key); const last=std.mem.lastIndexOfScalar(u8,key,'.').?;
    return if (first==last) lower(key) else fmt("{s}{s}{s}",.{lower(key[0..first]),key[first..last+1],lower(key[last+1..])});
}
fn validConfigKey(key: []const u8) bool {
    const first=std.mem.indexOfScalar(u8,key,'.') orelse return false; const last=std.mem.lastIndexOfScalar(u8,key,'.').?;
    if (first==0 or last+1==key.len or !std.ascii.isAlphabetic(key[last+1])) return false;
    for (key[0..first]) |c| { if (!std.ascii.isAlphanumeric(c) and c!='-') return false; }
    for (key[last+1..]) |c| { if (!std.ascii.isAlphanumeric(c) and c!='-') return false; } return true;
}
fn parseConfigValue(raw: []const u8) ?[]const u8 {
    var b: std.ArrayList(u8)=.empty; var quoted=false; var significant: usize=0; var i: usize=0;
    while (i<raw.len and (raw[i]==' ' or raw[i]=='\t')) : (i+=1) {}
    while (i<raw.len) : (i+=1) { const c=raw[i]; if (!quoted and (c=='#' or c==';')) break;
        if (c=='"') { quoted=!quoted; continue; }
        if (c=='\\') { i+=1; if (i>=raw.len) return null; const escaped: u8=switch (raw[i]) { 'n'=>'\n', 't'=>'\t', 'b'=>8, '\\'=>'\\', '"'=>'"', '\n'=>continue, else=>return null }; b.append(a,escaped) catch unreachable; significant=b.items.len; }
        else { b.append(a,c) catch unreachable; if (quoted or (c!=' ' and c!='\t' and c!='\r')) significant=b.items.len; }
    }
    if (quoted) return null; return b.items[0..significant];
}
fn configSectionName(raw: []const u8) ?[]const u8 {
    const text=trim(raw); if (text.len==0) return null; const quote=std.mem.indexOfScalar(u8,text,'"') orelse return lower(text);
    const end=std.mem.lastIndexOfScalar(u8,text,'"') orelse return null; if (end==quote or trim(text[end+1..]).len!=0) return null;
    const sub=parseConfigValue(text[quote..end+1]) orelse return null; return fmt("{s}.{s}",.{lower(trim(text[0..quote])),sub});
}
fn parseConfig(data: []const u8, origin: []const u8, scope: []const u8) ConfigDoc {
    var entries: std.ArrayList(Entry)=.empty; var sections: std.ArrayList(ConfigSection)=.empty; var section: []const u8=""; var off: usize=if (starts(data,"\xef\xbb\xbf")) 3 else 0;
    while (off<data.len) {
        var start=off; var end=(std.mem.indexOfScalarPos(u8,data,off,'\n') orelse data.len); var logical: std.ArrayList(u8)=.empty;
        while (true) { const raw=data[off..end]; logical.appendSlice(a,raw) catch unreachable; const continuation=raw.len>0 and raw[raw.len-1]=='\\'; off=if (end<data.len) end+1 else end;
            if (!continuation or off>=data.len) break; logical.items.len-=1; end=std.mem.indexOfScalarPos(u8,data,off,'\n') orelse data.len;
        }
        var text=std.mem.trimStart(u8,logical.items," \t\r"); if (text.len==0 or text[0]=='#' or text[0]==';') continue;
        if (text[0]=='[') {
            var quoted=false; var escaped=false; var stop: ?usize=null; for (text[1..],1..) |c,j| { if (escaped) { escaped=false; continue; } if (c=='\\') { escaped=true; continue; } if (c=='"') quoted=!quoted; if (c==']' and !quoted) { stop=j; break; } }
            const closepos=stop orelse { config_error=fmt("bad config line {d} in {s}",.{std.mem.count(u8,data[0..start],"\n")+1,origin}); break; };
            section=configSectionName(text[1..closepos]) orelse { config_error=fmt("bad config line {d} in {s}",.{std.mem.count(u8,data[0..start],"\n")+1,origin}); break; };
            if (sections.items.len>0) sections.items[sections.items.len-1].end=start;
            const header_end=start+(logical.items.len-text.len)+closepos+1;
            sections.append(a,.{.name=section,.start=start,.body=header_end,.end=data.len}) catch unreachable;
            text=std.mem.trimStart(u8,text[closepos+1..]," \t\r"); if (text.len==0 or text[0]=='#' or text[0]==';') continue; start=header_end;
        }
        var keyend: usize=0; while (keyend<text.len and text[keyend]!='=' and text[keyend]!=' ' and text[keyend]!='\t' and text[keyend]!='\r') : (keyend+=1) {}
        const key=fmt("{s}.{s}",.{section,lower(text[0..keyend])}); if (section.len==0 or !validConfigKey(key)) { config_error=fmt("bad config line {d} in {s}",.{std.mem.count(u8,data[0..start],"\n")+1,origin}); break; }
        const tail=std.mem.trimStart(u8,text[keyend..]," \t\r"); const implicit=tail.len==0 or tail[0]=='#' or tail[0]==';';
        if (!implicit and tail[0]!='=') { config_error=fmt("bad config line {d} in {s}",.{std.mem.count(u8,data[0..start],"\n")+1,origin}); break; }
        const value=if (implicit) "" else parseConfigValue(tail[1..]) orelse { config_error=fmt("bad config line {d} in {s}",.{std.mem.count(u8,data[0..start],"\n")+1,origin}); break; };
        entries.append(a,.{.key=key,.value=value,.implicit=implicit,.start=start,.end=off,.origin=origin,.scope=scope,.line_number=std.mem.count(u8,data[0..start],"\n")+1}) catch unreachable;
    }
    return .{.data=data,.entries=entries.toOwnedSlice(a) catch unreachable,.sections=sections.toOwnedSlice(a) catch unreachable};
}
fn configEntries(p: []const u8) []Entry { return parseConfig(load(p) orelse "",p,"local").entries; }
fn globalConfig() []const u8 { return env("GIT_CONFIG_GLOBAL") orelse join(env("HOME") orelse cwd(),".gitconfig"); }
fn localConfig() ?[]const u8 { const g=gitdir() orelse return null; return if (eq(g,join(cwd(),".git"))) ".git/config" else join(g,"config"); }
fn configGet(key: []const u8) ?[]const u8 {
    const k = canonicalKey(key);
    if (overrides.get(k)) |v| return v;
    var result: ?[]const u8 = null;
    for (allConfigEntries()) |e| { if (eq(k,e.key)) result=if (e.implicit) "true" else e.value; }
    return result;
}
fn configQuote(value: []const u8) []const u8 {
    var b: std.ArrayList(u8)=.empty; const quoted=value.len>0 and (value[0]==' ' or value[value.len-1]==' ' or value[0]=='\t' or value[value.len-1]=='\t' or std.mem.indexOfAny(u8,value,"#;\r")!=null);
    if (quoted) b.append(a,'"') catch unreachable;
    for (value) |c| { b.appendSlice(a,switch (c) { '\n'=>"\\n", '\t'=>"\\t", 8=>"\\b", '"'=>"\\\"", '\\'=>"\\\\", else=>&.{c} }) catch unreachable; }
    if (quoted) b.append(a,'"') catch unreachable; return b.toOwnedSlice(a) catch unreachable;
}
fn sectionHeader(name: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8,name,'.')) |dot| { const escaped=std.mem.replaceOwned(u8,a,name[dot+1..],"\\","\\\\") catch unreachable; const sub=std.mem.replaceOwned(u8,a,escaped,"\"","\\\"") catch unreachable; return fmt("[{s} \"{s}\"]",.{name[0..dot],sub}); } return fmt("[{s}]",.{name});
}
fn regexMatch(pattern: []const u8, value: []const u8) ?bool {
    var storage: [512]u8 align(16)=undefined; if (regcomp(&storage,z(pattern),1)!=0) return null; defer regfree(&storage); return regexec(&storage,z(value),0,null,0)==0;
}
fn valueMatches(pattern: ?[]const u8, value: []const u8, fixed: bool) ?bool {
    const p=pattern orelse return true; if (fixed) return eq(p,value); if (starts(p,"!")) return !(regexMatch(p[1..],value) orelse return null); return regexMatch(p,value);
}
fn configMutate(p: []const u8, key: []const u8, value: ?[]const u8, adding: bool, all: bool, pattern: ?[]const u8, fixed: bool, comment: ?[]const u8) u8 {
    if (!validConfigKey(key)) { emit(2,fmt("error: invalid key: {s}\n",.{key})); return 1; }
    if (eq(p,"-")) return fatal("writing to stdin is not supported");
    const lockpath=fmt("{s}.lock",.{p}); if (std.fs.path.dirname(p)) |parent| mkpath(parent);
    const timeout=std.fmt.parseInt(i64,configGet("core.configlocktimeout") orelse "100",10) catch 100; var elapsed: i64=0;
    while (true) { if (fopen(z(lockpath),"wx")) |lock| { _=fclose(lock); break; } if (timeout>=0 and elapsed>=timeout) return fatal(fmt("could not lock config file {s}: File exists",.{p})); _=usleep(20000); elapsed+=20; }
    defer remove(lockpath);
    if (comment) |c| { if (std.mem.indexOfScalar(u8,c,'\n')!=null) return 1; }
    const data=load(p) orelse ""; const doc=parseConfig(data,p,"local"); if (config_error!=null) return fatal(config_error.?);
    const canonical=canonicalKey(key); const dot=std.mem.lastIndexOfScalar(u8,key,'.').?; const section=canonical[0..dot]; const varname=key[dot+1..];
    const selected=a.alloc(bool,doc.entries.len) catch unreachable; @memset(selected,false); var count: usize=0; var insertion: usize=data.len; var foundsection=false;
    for (doc.sections) |s| { if (eq(s.name,section)) { insertion=s.end; foundsection=true; } }
    for (doc.entries,0..) |e,i| { if (!adding and eq(e.key,canonical) and (valueMatches(pattern,e.value,fixed) orelse return 6)) { selected[i]=true; if (count==0) insertion=e.start; count+=1; } }
    if (!all and count>1) { emit(2,fmt("warning: {s} has multiple values\n",.{key})); return 5; } if (value==null and count==0) return 5;
    const suffix=if (comment) |c| if (c.len>0 and (c[0]=='#' or c[0]==';' or c[0]==' ' or c[0]=='\t')) fmt(" {s}",.{c}) else fmt(" # {s}",.{c}) else "";
    const replacement=if (value) |v| fmt("\t{s} = {s}{s}\n",.{varname,configQuote(v),suffix}) else "";
    var b: std.ArrayList(u8)=.empty; var off: usize=0; var inserted=false;
    for (doc.entries,0..) |e,i| {
        if (!selected[i]) continue;
        if (e.start<off) continue; b.appendSlice(a,data[off..e.start]) catch unreachable;
        if (!inserted and value!=null) { if (b.items.len>0 and b.items[b.items.len-1]!='\n') b.append(a,'\n') catch unreachable; b.appendSlice(a,replacement) catch unreachable; inserted=true; }
        off=e.end;
    }
    if (count>0) b.appendSlice(a,data[off..]) catch unreachable
    else if (value!=null) {
        b.appendSlice(a,data[0..insertion]) catch unreachable;
        if (b.items.len>0 and b.items[b.items.len-1]!='\n') b.append(a,'\n') catch unreachable;
        if (!foundsection) b.appendSlice(a,fmt("{s}\n",.{sectionHeader(key[0..dot])})) catch unreachable;
        b.appendSlice(a,replacement) catch unreachable; b.appendSlice(a,data[insertion..]) catch unreachable;
    }
    var result: []const u8=b.items;
    if (value==null) {
        const cleaned=parseConfig(result,p,"local"); var output: std.ArrayList(u8)=.empty; var cursor: usize=0;
        for (cleaned.sections) |s| {
            if (!eq(s.name,section)) continue; var populated=false; for (cleaned.entries) |e| { if (e.start>=s.start and e.start<s.end) populated=true; }
            if (!populated and std.mem.indexOfAny(u8,result[s.body..s.end],"#;")==null) { output.appendSlice(a,result[cursor..s.start]) catch unreachable; cursor=s.end; }
        }
        output.appendSlice(a,result[cursor..]) catch unreachable; result=output.items;
    }
    if (!put(lockpath,result)) return 1;
    return if (std.c.rename(z(lockpath),z(p))==0) 0 else 1;
}
fn configSet(p: []const u8, key: []const u8, value: ?[]const u8, adding: bool) bool { return configMutate(p,key,value,adding,true,null,false,null)==0; }
fn appendConfigFile(entries: *std.ArrayList(Entry), p: []const u8, scope: []const u8, includes: bool, depth: usize) void {
    if (depth>10) { config_error="exceeded maximum include depth"; return; } const data=if (eq(p,"-")) stdin() else load(p) orelse return;
    for (parseConfig(data,if (eq(p,"-")) "standard input" else p,scope).entries) |e| { entries.append(a,e) catch unreachable;
        if (includes and (eq(e.key,"include.path") or starts(e.key,"includeif."))) {
            var follow=eq(e.key,"include.path");
            if (starts(e.key,"includeif.onbranch:") and std.mem.endsWith(u8,e.key,".path")) { const condition=e.key["includeif.onbranch:".len..e.key.len-5]; const pattern=if (std.mem.endsWith(u8,condition,"/")) fmt("{s}*",.{condition}) else condition; if (gitdir()) |g| { const head=trim(load(join(g,"HEAD")) orelse ""); if (starts(head,"ref: refs/heads/")) follow=fnmatch(z(pattern),z(head[16..]),0)==0; } }
            if ((starts(e.key,"includeif.gitdir:") or starts(e.key,"includeif.gitdir/i:")) and std.mem.endsWith(u8,e.key,".path")) {
                const insensitive=starts(e.key,"includeif.gitdir/i:"); const condition=e.key[if (insensitive) "includeif.gitdir/i:".len else "includeif.gitdir:".len..e.key.len-5];
                var pattern=if (starts(condition,"~/")) join(env("HOME") orelse "",condition[2..]) else if (starts(condition,"./")) join(std.fs.path.dirname(absolute(p)) orelse ".",condition[2..]) else if (!starts(condition,"/")) fmt("*/{s}",.{condition}) else condition;
                if (std.mem.endsWith(u8,pattern,"/")) pattern=fmt("{s}*",.{pattern});
                if (gitdir()) |g| follow=fnmatch(z(if (insensitive) lower(pattern) else pattern),z(if (insensitive) lower(g) else g),0)==0 or fnmatch(z(if (insensitive) lower(pattern) else pattern),z(if (insensitive) lower(fmt("{s}/",.{g})) else fmt("{s}/",.{g})),0)==0;
            }
            if (follow) { const expanded=if (starts(e.value,"~/")) join(env("HOME") orelse "",e.value[2..]) else e.value; const path=if (starts(expanded,"/")) expanded else join(std.fs.path.dirname(p) orelse ".",expanded); appendConfigFile(entries,path,scope,includes,depth+1); }
        }
    }
}
fn allConfigEntries() []Entry {
    var entries: std.ArrayList(Entry)=.empty;
    if (!eq(env("GIT_CONFIG_NOSYSTEM") orelse "0","1")) appendConfigFile(&entries,env("GIT_CONFIG_SYSTEM") orelse "/etc/gitconfig","system",true,0);
    if (env("GIT_CONFIG_GLOBAL")==null) appendConfigFile(&entries,join(env("XDG_CONFIG_HOME") orelse join(env("HOME") orelse "",".config"),"git/config"),"global",true,0);
    appendConfigFile(&entries,globalConfig(),"global",true,0);
    if (localConfig()) |path| appendConfigFile(&entries,path,"local",true,0);
    const count=std.fmt.parseInt(usize,env("GIT_CONFIG_COUNT") orelse "0",10) catch { config_error="bogus count in GIT_CONFIG_COUNT"; return entries.items; };
    if (count>100000) { config_error="too many environment config entries"; return entries.items; }
    for (0..count) |i| { const key=env(fmt("GIT_CONFIG_KEY_{d}",.{i})) orelse { config_error="missing config key"; break; }; const value=env(fmt("GIT_CONFIG_VALUE_{d}",.{i})) orelse { config_error="missing config value"; break; }; if (!validConfigKey(key)) { config_error="invalid config key"; break; } entries.append(a,.{.key=canonicalKey(key),.value=value,.origin="command line",.scope="command"}) catch unreachable; }
    for (command_config.items) |e| entries.append(a,e) catch unreachable;
    return entries.toOwnedSlice(a) catch unreachable;
}
var command_config: std.ArrayList(Entry)=.empty;
fn configTyped(value: []const u8, implicit: bool, kind: []const u8, writing: bool) ?[]const u8 {
    if (kind.len==0) return value;
    if (eq(kind,"bool") or eq(kind,"bool-or-int")) {
        const l=lower(value); if (implicit or eq(l,"true") or eq(l,"yes") or eq(l,"on")) return "true";
        if (eq(l,"false") or eq(l,"no") or eq(l,"off") or l.len==0) return "false";
        if (eq(kind,"bool")) { const n=std.fmt.parseInt(i64,value,10) catch return null; return if (n==0) "false" else "true"; }
    }
    if (eq(kind,"int") or eq(kind,"bool-or-int")) { if (value.len==0) return null; var num=value; var factor: i64=1; switch (std.ascii.toLower(value[value.len-1])) { 'k'=>{ factor=1024; num=value[0..value.len-1]; }, 'm'=>{ factor=1024*1024; num=value[0..value.len-1]; }, 'g'=>{ factor=1024*1024*1024; num=value[0..value.len-1]; }, else=>{} } const n=std.fmt.parseInt(i64,num,10) catch return null; const product=@mulWithOverflow(n,factor); if (product[1]!=0) return null; return fmt("{d}",.{product[0]}); }
    if (eq(kind,"path")) { if (implicit) return null; if (writing) return value; if (starts(value,"~/")) { const home=env("HOME") orelse return null; return join(home,value[2..]); } if (starts(value,"~")) return null; return value; }
    if (eq(kind,"expiry-date")) { if (eq(value,"never")) return "0"; return null; }
    if (eq(kind,"color")) { if (eq(value,"normal")) return if (writing) value else ""; const colors=[_][]const u8{"black","red","green","yellow","blue","magenta","cyan","white"}; var codes: std.ArrayList(u8)=.empty; var words=std.mem.tokenizeAny(u8,value," \t"); while (words.next()) |w| { var code: ?usize=null; for (colors,0..) |c,i| { if (eq(w,c)) code=30+i; } if (eq(w,"bold")) code=1; if (eq(w,"dim")) code=2; if (eq(w,"ul")) code=4; if (eq(w,"reverse")) code=7; const n=code orelse return null; if (codes.items.len>0) codes.append(a,';') catch unreachable; codes.appendSlice(a,fmt("{d}",.{n})) catch unreachable; } return if (writing) value else fmt("\x1b[{s}m",.{codes.items}); }
    return null;
}
fn config(args: Args) u8 {
    const Action=enum { automatic, get, list, set, unset, rename, remove_section }; var action: Action=.automatic; var mode_count: usize=0;
    var file: ?[]const u8=env("GIT_CONFIG"); var scope: []const u8="local"; var explicit=file!=null; var all=false; var adding=false; var regexp=false; var names=false; var nameonly=false; var nul=false; var fixed=false; var includes: ?bool=null; var origin=false; var showscope=false;
    var kind: []const u8=""; var default: ?[]const u8=null; var valuepattern: ?[]const u8=null; var comment: ?[]const u8=null; var url: ?[]const u8=null; var urlpos=false;
    var p: std.ArrayList([]const u8)=.empty; var i: usize=0;
    while (i<args.len) : (i+=1) { const s=args[i];
        if (eq(s,"get") or eq(s,"set") or eq(s,"unset") or eq(s,"list") or eq(s,"rename-section") or eq(s,"remove-section")) { if (p.items.len==0 and action==.automatic) { action=if (eq(s,"get")) .get else if (eq(s,"set")) .set else if (eq(s,"unset")) .unset else if (eq(s,"list")) .list else if (eq(s,"rename-section")) .rename else .remove_section; mode_count+=1; continue; } }
        if (eq(s,"--global") or eq(s,"--system") or eq(s,"--local") or eq(s,"--worktree")) { explicit=true; if (eq(s,"--global")) { file=globalConfig(); scope="global"; } else if (eq(s,"--system")) { file=env("GIT_CONFIG_SYSTEM") orelse "/etc/gitconfig"; scope="system"; } else { file=localConfig() orelse return fatal("--local can only be used inside a git repository"); scope="local"; } }
        else if (eq(s,"--file") or eq(s,"-f")) { i+=1; if (i==args.len) return 129; file=args[i]; explicit=true; }
        else if (starts(s,"--file=")) { file=s[7..]; explicit=true; }
        else if (eq(s,"--get") or eq(s,"--get-all") or eq(s,"--get-regexp") or eq(s,"--get-color")) {
            if (mode_count>0) { var previous: []const u8="--get"; for (args[0..i]) |arg| { if (starts(arg,"--get")) previous=arg; } emit(2,fmt("error: options '{s}' and '{s}' cannot be used together\n",.{s,previous})); return 129; }
            action=.get; mode_count+=1; if (eq(s,"--get-all") or eq(s,"--get-regexp")) all=true; if (eq(s,"--get-regexp")) { regexp=true; names=true; } if (eq(s,"--get-color")) kind="color";
        }
        else if (eq(s,"--get-urlmatch")) { action=.get; mode_count+=1; urlpos=true; }
        else if (starts(s,"--url=")) url=s[6..] else if (eq(s,"--url")) { i+=1; if (i==args.len) return 129; url=args[i]; }
        else if (eq(s,"--list") or eq(s,"-l")) { action=.list; mode_count+=1; }
        else if (eq(s,"--unset") or eq(s,"--unset-all")) { action=.unset; mode_count+=1; all=eq(s,"--unset-all"); }
        else if (eq(s,"--add") or eq(s,"--replace-all")) { action=.set; mode_count+=1; adding=eq(s,"--add"); all=true; }
        else if (eq(s,"--rename-section") or eq(s,"--remove-section")) { action=if (eq(s,"--rename-section")) .rename else .remove_section; mode_count+=1; }
        else if (eq(s,"--all")) all=true else if (eq(s,"--regexp")) regexp=true else if (eq(s,"--show-names")) names=true else if (eq(s,"--name-only")) nameonly=true else if (eq(s,"--null") or eq(s,"-z")) nul=true else if (eq(s,"--fixed-value")) fixed=true
        else if (eq(s,"--includes")) includes=true else if (eq(s,"--no-includes")) includes=false else if (eq(s,"--show-origin")) origin=true else if (eq(s,"--show-scope")) showscope=true
        else if (eq(s,"--default") or eq(s,"--value") or eq(s,"--comment") or eq(s,"--type")) { i+=1; if (i==args.len) return 129; if (eq(s,"--default")) default=args[i] else if (eq(s,"--value")) valuepattern=args[i] else if (eq(s,"--comment")) comment=args[i] else { if (kind.len>0 and !eq(kind,args[i])) return 129; kind=args[i]; } }
        else if (starts(s,"--default=")) default=s[10..] else if (starts(s,"--value=")) valuepattern=s[8..] else if (starts(s,"--comment=")) comment=s[10..]
        else if (starts(s,"--type=")) { if (kind.len>0 and !eq(kind,s[7..])) return 129; kind=s[7..]; }
        else if (eq(s,"--no-type")) kind=""
        else if (eq(s,"--bool") or eq(s,"--int") or eq(s,"--bool-or-int") or eq(s,"--path") or eq(s,"--expiry-date")) { if (kind.len>0 and !eq(kind,s[2..])) return 129; kind=s[2..]; }
        else if (eq(s,"--")) { p.appendSlice(a,args[i+1..]) catch unreachable; break; }
        else if (starts(s,"--")) { emit(2,fmt("error: unknown option `{s}'\n",.{s[2..]})); return 129; } else p.append(a,s) catch unreachable;
    }
    if (mode_count>1) return 129;
    if (urlpos) { if (p.items.len!=2) return 129; url=p.items[1]; p.items.len=1; }
    if (kind.len>0 and !eq(kind,"bool") and !eq(kind,"int") and !eq(kind,"bool-or-int") and !eq(kind,"path") and !eq(kind,"expiry-date") and !eq(kind,"color")) return 129;
    if (action==.automatic) action=if (p.items.len>=2) .set else .get;
    const writing=action==.set or action==.unset or action==.rename or action==.remove_section;
    if (writing and (origin or showscope or default!=null)) return 129;
    if (action==.rename or action==.remove_section) {
        if (p.items.len!=(if (action==.rename) @as(usize,2) else 1)) return 129; const path=file orelse if (gitdir()) |g| join(g,"config") else return 128;
        const data=load(path) orelse return 5; const doc=parseConfig(data,path,scope); var b: std.ArrayList(u8)=.empty; var offset: usize=0; var found=false;
        for (doc.sections) |s| { if (!eq(s.name,p.items[0])) continue; found=true; b.appendSlice(a,data[offset..s.start]) catch unreachable; if (action==.rename) { if (!validConfigKey(fmt("{s}.key",.{p.items[1]}))) return 1; b.appendSlice(a,sectionHeader(p.items[1])) catch unreachable; offset=s.body; } else offset=s.end; } if (!found) return 5; b.appendSlice(a,data[offset..]) catch unreachable; return if (put(path,b.items)) 0 else 1;
    }
    if (writing) {
        if (p.items.len<(if (action==.set) @as(usize,2) else 1) or p.items.len>3) return 129;
        const path=file orelse if (gitdir()) |g| join(g,"config") else return fatal("not in a git directory"); const key=p.items[0];
        const value=if (action==.unset) null else configTyped(p.items[1],false,kind,true) orelse return fatal(fmt("bad {s} config value '{s}' for '{s}'",.{kind,p.items[1],key}));
        const pattern=valuepattern orelse if (p.items.len>(if (action==.set) @as(usize,2) else 1)) p.items[if (action==.set) 2 else 1] else null;
        if (fixed and pattern==null) return 129;
        return configMutate(path,key,value,adding,all,pattern,fixed,comment);
    }
    if (action!=.list and (p.items.len==0 or p.items.len>2)) return 129;
    if (action==.list and p.items.len>0) return 129;
    var entries: std.ArrayList(Entry)=.empty;
    if (explicit) { const path=file orelse return 129; if (!eq(path,"-") and !exists(path)) { if (action==.list) return fatal(fmt("unable to read config file '{s}': No such file or directory",.{path})); return 1; } appendConfigFile(&entries,path,scope,includes orelse false,0); }
    else entries.appendSlice(a,allConfigEntries()) catch unreachable;
    if (config_error) |err| return fatal(err);
    const key=if (p.items.len>0) canonicalKey(p.items[0]) else "";
    if (action==.get and url==null and !regexp and !validConfigKey(key) and !(key.len==0 and (default!=null or eq(kind,"color")) )) return 1;
    const pattern=valuepattern orelse if (p.items.len>1 and !eq(kind,"color")) p.items[1] else null;
    if (fixed and pattern==null) return 129;
    var found: std.ArrayList(Entry)=.empty;
    if (url) |address| {
        const section=if (std.mem.indexOfScalar(u8,key,'.')) |dot| key[0..dot] else key;
        names=std.mem.indexOfScalar(u8,key,'.')==null; all=true;
        var scores=std.StringHashMap(u64).init(a);
        for (entries.items) |e| {
            if (!starts(e.key,fmt("{s}.",.{section}))) continue;
            const last=std.mem.lastIndexOfScalar(u8,e.key,'.').?; const itemkey=fmt("{s}.{s}",.{section,e.key[last+1..]});
            if (!names and !eq(itemkey,key)) continue;
            const score=if (last==section.len) @as(u64,0) else @import("urlmatch.zig").score(e.key[section.len+1..last],address) orelse continue;
            if (scores.get(itemkey)) |previous| { if (score<previous) continue; }
            scores.put(itemkey,score) catch unreachable; var replacement=e; replacement.key=itemkey; var replaced=false;
            for (found.items) |*item| { if (eq(item.key,itemkey)) { item.*=replacement; replaced=true; break; } }
            if (!replaced) found.append(a,replacement) catch unreachable;
        }
        std.mem.sort(Entry,found.items,{},struct { fn less(_: void,x: Entry,y: Entry) bool { return std.mem.lessThan(u8,x.key,y.key); } }.less);
    } else for (entries.items) |e| { if (action!=.list and !(if (regexp) regexMatch(p.items[0],e.key) orelse return 6 else eq(e.key,key))) continue; if (!(valueMatches(pattern,e.value,fixed) orelse return 6)) continue; found.append(a,e) catch unreachable; }
    if (found.items.len==0 and action!=.list) { const d=default orelse (if (eq(kind,"color") and p.items.len>1) p.items[1] else return 1); found.append(a,.{.key=key,.value=d,.origin="",.scope=""}) catch unreachable; }
    const values=if (action==.get and !all and found.items.len>0) found.items[found.items.len-1..] else found.items;
    for (values) |e| { const value=configTyped(e.value,e.implicit,kind,false) orelse { if (action==.list) continue;
        if (eq(kind,"path") and e.implicit) return fatal(fmt("missing value for '{s}' at line {d} in {s}",.{e.key,e.line_number,e.origin}));
        if (eq(kind,"path") and starts(e.value,"~")) return fatal(fmt("failed to expand user dir in: '{s}'",.{e.value}));
        if (eq(kind,"int") or eq(kind,"bool-or-int")) return fatal(fmt("bad numeric config value '{s}' for '{s}' in file {s}: invalid unit",.{e.value,e.key,e.origin}));
        return fatal(fmt("bad {s} config value '{s}' for '{s}'",.{if (eq(kind,"bool")) "boolean" else kind,e.value,e.key})); };
        if (showscope) { out(e.scope); out(if (nul) "\x00" else "\t"); }
        if (origin) { out(if (eq(e.origin,"command line")) "command line:" else if (eq(e.origin,"standard input")) "standard input:" else if (e.origin.len==0) "" else fmt("file:{s}",.{e.origin})); out(if (nul) "\x00" else "\t"); }
        if (nameonly) out(e.key) else if (action==.list or names) { out(e.key); if (!e.implicit or kind.len>0) { out(if (nul) "\n" else if (action==.list) "=" else " "); out(value); } } else out(value);
        out(if (nul) "\x00" else "\n");
    } return 0;
}
fn initRepo(args: Args, global_bare: bool) u8 {
    var bare = global_bare; var quiet = false;
    var dir: []const u8 = ".";
    var branch = configGet("init.defaultBranch") orelse env("GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME") orelse "master";
    var i: usize = 0;
    while (i < args.len) : (i+=1) {
        const s=args[i];
        if (eq(s,"--bare")) bare=true
        else if (eq(s,"-q") or eq(s,"--quiet")) quiet=true
        else if (eq(s,"-b") or eq(s,"--initial-branch")) { i+=1; if (i>=args.len) return 129; branch=args[i]; }
        else if (starts(s,"--initial-branch=")) branch=s[17..]
        else if (starts(s,"--template=")) {}
        else if (eq(s,"--template")) { i+=1; }
        else if (starts(s,"--object-format=")) { if (!eq(s[16..],"sha1")) return fatal("only sha1 object format is implemented"); }
        else if (starts(s,"-")) return 129
        else dir=s;
    }
    const root = absolute(dir);
    const g = if (env("GIT_DIR")) |v| absolute(v) else if (bare) root else join(root,".git");
    const reinit = exists(join(g,"HEAD"));
    for ([_][]const u8{"objects/info","objects/pack","refs/heads","refs/tags","hooks","info"}) |d| mkpath(join(g,d));
    if (!reinit) {
        if (!put(join(g,"HEAD"),fmt("ref: refs/heads/{s}\n",.{branch}))) return fatal("cannot write HEAD");
        if (!put(join(g,"config"),fmt("[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = {s}\n{s}",.{if (bare) "true" else "false",if (bare) "" else "\tlogallrefupdates = true\n"}))) return fatal("cannot write config");
        if (exists(join(g,"CoNfIg"))) _=configSet(join(g,"config"),"core.ignorecase","true",false);
    }
    if (!quiet) line(fmt("{s} Git repository in {s}/",.{if (reinit) "Reinitialized existing" else "Initialized empty",g}));
    return 0;
}
fn ident(committer: bool) ?[]const u8 {
    const prefix = if (committer) "GIT_COMMITTER" else "GIT_AUTHOR";
    if (!committer and explicit_author!=null) return fmt("{s} {s}",.{explicit_author.?,explicit_author_date orelse env("GIT_AUTHOR_DATE") orelse fmt("{d} +0000",.{time(null)})});
    const name = env(fmt("{s}_NAME",.{prefix})) orelse configGet("user.name") orelse return null;
    const email = env(fmt("{s}_EMAIL",.{prefix})) orelse configGet("user.email") orelse env("EMAIL") orelse return null;
    const date = (if (!committer) explicit_author_date else null) orelse env(fmt("{s}_DATE",.{prefix})) orelse fmt("{d} +0000",.{time(null)});
    return fmt("{s} <{s}> {s}",.{trim(name),trim(email),if (starts(date,"@")) date[1..] else date});
}
fn variable(args: Args) u8 {
    if (args.len!=1) return 129;
    const s=args[0];
    if (eq(s,"GIT_AUTHOR_IDENT") or eq(s,"GIT_COMMITTER_IDENT")) {
        line(ident(eq(s,"GIT_COMMITTER_IDENT")) orelse return fatal("unable to auto-detect email address"));
    } else if (eq(s,"GIT_DEFAULT_BRANCH")) line(configGet("init.defaultbranch") orelse env("GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME") orelse "master")
    else if (eq(s,"GIT_EDITOR")) line(env("GIT_EDITOR") orelse configGet("core.editor") orelse env("VISUAL") orelse env("EDITOR") orelse "vi")
    else if (eq(s,"GIT_SEQUENCE_EDITOR")) line(env("GIT_SEQUENCE_EDITOR") orelse configGet("sequence.editor") orelse env("GIT_EDITOR") orelse "vi")
    else if (eq(s,"GIT_PAGER")) line(env("GIT_PAGER") orelse configGet("core.pager") orelse env("PAGER") orelse "less")
    else if (eq(s,"GIT_SHELL_PATH")) line("/bin/sh")
    else return 129;
    return 0;
}
fn objectHash(typ: []const u8, data: []const u8, store: bool) ?[]const u8 {
    const raw=fmt("{s} {d}\x00{s}",.{typ,data.len,data});
    var digest: [20]u8=undefined;
    std.crypto.hash.Sha1.hash(raw,&digest,.{});
    const hex=std.fmt.bytesToHex(digest,.lower);
    const oid=a.dupe(u8,&hex) catch unreachable;
    if (store) {
        const g=objectDirectory() orelse return null;
        var len=compressBound(@intCast(raw.len));
        const compressed=a.alloc(u8,@intCast(len)) catch unreachable;
        if (compress2(compressed.ptr,&len,raw.ptr,@intCast(raw.len),1)!=0) return null;
        if (!put(join(g,fmt("{s}/{s}",.{oid[0..2],oid[2..]})),compressed[0..@intCast(len)])) return null;
    }
    return oid;
}
fn resolve(s: []const u8) ?[]const u8 {
    return resolveDepth(s,0);
}
fn resolveDepth(s: []const u8, depth: usize) ?[]const u8 {
    if (depth>16) return null;
    if (starts(s,":/")) { var seen=std.StringHashMap(void).init(a); var todo: std.ArrayList([]const u8)=.empty; for (allRefs()) |r| todo.append(a,r.oid) catch unreachable; if (resolveDepth("HEAD",depth+1)) |id| todo.append(a,id) catch unreachable;
        var best: ?[]const u8=null; var besttime: i64=std.math.minInt(i64);
        while (todo.pop()) |id| { if (seen.contains(id)) continue; seen.put(id,{}) catch unreachable; const obj=readObject(id) orelse continue; if (!eq(obj.typ,"commit")) continue;
            const message=if (std.mem.indexOf(u8,obj.data,"\n\n")) |p| obj.data[p+2..] else "";
            if ((regexMatch(s[2..],message) orelse return null) and commitTime(id)>besttime) { best=id; besttime=commitTime(id); } todo.appendSlice(a,commitParents(obj)) catch unreachable;
        } return best;
    }
    if (eq(s,"@")) return resolveDepth("HEAD",depth+1);
    if (std.mem.indexOf(u8,s,"@{")) |pos| {
        if (!std.mem.endsWith(u8,s,"}")) return null; const n=std.fmt.parseInt(usize,s[pos+2..s.len-1],10) catch return null; const name=if (pos==0) "HEAD" else s[0..pos]; const g=gitdir() orelse return null;
        const logfile=if (load(join(g,fmt("logs/{s}",.{name})))) |d| d else load(join(g,fmt("logs/refs/heads/{s}",.{name}))) orelse return null;
        var lines=std.mem.splitBackwardsScalar(u8,std.mem.trimEnd(u8,logfile,"\n"),'\n'); var count: usize=0; while (lines.next()) |l| { if (l.len<81) continue; if (count==n) return l[41..81]; count+=1; } return null;
    }
    if (std.mem.indexOfScalar(u8,s,':')) |pos| {
        const path=s[pos+1..]; if (pos==0) { for (readIndex()) |e| { if (eq(e.path,path)) return e.oid; } return null; }
        var oid=resolveDepth(s[0..pos],depth+1) orelse return null; var obj=readObject(oid) orelse return null;
        if (eq(obj.typ,"tag")) { oid=resolveDepth(fmt("{s}^{{}}",.{oid}),depth+1) orelse return null; obj=readObject(oid) orelse return null; }
        if (eq(obj.typ,"commit")) { oid=header(obj.data,"tree") orelse return null; obj=readObject(oid) orelse return null; }
        if (path.len==0) return oid; var parts=std.mem.splitScalar(u8,path,'/'); while (parts.next()) |part| { if (!eq(obj.typ,"tree")) return null; var offset: usize=0; var found=false;
            while (offset<obj.data.len) { const space=std.mem.indexOfScalarPos(u8,obj.data,offset,' ') orelse return null; const end=std.mem.indexOfScalarPos(u8,obj.data,space,0) orelse return null; if (end+21>obj.data.len) return null;
                if (eq(obj.data[space+1..end],part)) { const hex=std.fmt.bytesToHex(obj.data[end+1..][0..20].*,.lower); oid=a.dupe(u8,&hex) catch unreachable; obj=readObject(oid) orelse return null; found=true; break; } offset=end+21;
            } if (!found) return null;
        } return oid;
    }
    if (std.mem.indexOfAny(u8,s,"^~")) |pos| {
        var oid=resolveDepth(s[0..pos],depth+1) orelse return null;
        var tail=s[pos..];
        while (tail.len>0) {
            const op=tail[0]; tail=tail[1..];
            if (starts(tail,"{tree}")) { const obj=readObject(oid) orelse return null; return if (eq(obj.typ,"tree")) oid else header(obj.data,"tree"); }
            if (starts(tail,"{}") or (op=='^' and starts(tail,"0"))) { var obj=readObject(oid) orelse return null; var peel: usize=0; while (eq(obj.typ,"tag") and peel<16) : (peel+=1) { oid=header(obj.data,"object") orelse return null; obj=readObject(oid) orelse return null; } return oid; }
            var n: usize=0; while (n<tail.len and std.ascii.isDigit(tail[n])) : (n+=1) {}
            const count=if (n==0) 1 else std.fmt.parseInt(usize,tail[0..n],10) catch return null;
            tail=tail[n..];
            var steps: usize=if (op=='~') count else @intFromBool(count>0);
            while (steps>0) : (steps-=1) {
                const obj=readObject(oid) orelse return null;
                var lines=std.mem.splitScalar(u8,obj.data,'\n'); var parent: usize=0; var found=false;
                while (lines.next()) |l| { if (starts(l,"parent ")) { parent+=1; if (op=='~' or parent==count) { oid=l[7..]; found=true; break; } } }
                if (!found) return null;
            }
        }
        return oid;
    }
    if (s.len==40) { _=std.fmt.parseInt(u160,s,16) catch return null; return s; }
    const g=gitdir() orelse return null;
    const names=[_][]const u8{s,fmt("refs/{s}",.{s}),fmt("refs/heads/{s}",.{s}),fmt("refs/tags/{s}",.{s})};
    for (names) |n| {
        if (load(join(g,n))) |data| { const v=trim(data); if (starts(v,"ref: ")) return resolveDepth(v[5..],depth+1); if (v.len==40) return v; }
        if (load(join(g,"packed-refs"))) |data| { var lines=std.mem.splitScalar(u8,data,'\n'); while (lines.next()) |l| { if (l.len>41 and l[40]==' ' and eq(l[41..],n)) return l[0..40]; } }
    }
    if (s.len>=4 and s.len<40) {
        _=std.fmt.parseInt(u160,s,16) catch return null; var found: ?[]const u8=null;
        for (objectDirectories()) |objects| {
            if (std.c.opendir(z(join(objects,s[0..2])))) |dir| { defer _=std.c.closedir(dir);
                while (std.c.readdir(dir)) |e| { const name=std.mem.sliceTo(&e.name,0); if (name.len==38 and starts(name,s[2..])) { const id=fmt("{s}{s}",.{s[0..2],name}); if (found!=null and !eq(found.?,id)) return null; found=id; } }
            }
        }
        loadPacks(); for (pack_cache.items) |*cached| { if (cached.pack) |*p| { var it=p.by_oid.keyIterator(); while (it.next()) |id| { if (starts(id.*,s)) { if (found!=null and !eq(found.?,id.*)) return null; found=id.*; } } } }
        return found;
    }
    return null;
}
const Object=packlib.Object;
fn objectDirectory() ?[]const u8 { return if (env("GIT_OBJECT_DIRECTORY")) |d| absolute(d) else join(gitdir() orelse return null,"objects"); }
var object_dirs: ?Args=null;
fn appendObjectDirectory(dirs: *std.ArrayList([]const u8), path: []const u8, depth: usize) void {
    if (depth>5) return; const normalized=absolute(path); for (dirs.items) |d| { if (eq(d,normalized)) return; } dirs.append(a,normalized) catch unreachable;
    if (load(join(normalized,"info/alternates"))) |data| { var lines=std.mem.splitScalar(u8,data,'\n'); while (lines.next()) |l| { if (l.len>0) appendObjectDirectory(dirs,join(normalized,l),depth+1); } }
}
fn objectDirectories() Args {
    if (object_dirs) |dirs| return dirs; var dirs: std.ArrayList([]const u8)=.empty;
    if (objectDirectory()) |d| appendObjectDirectory(&dirs,d,0);
    if (env("GIT_ALTERNATE_OBJECT_DIRECTORIES")) |paths| { var it=std.mem.splitScalar(u8,paths,':'); while (it.next()) |d| { if (d.len>0) appendObjectDirectory(&dirs,d,0); } }
    object_dirs=dirs.toOwnedSlice(a) catch unreachable; return object_dirs.?;
}
const CachedPack=struct { path: []const u8, pack: ?packlib.Pack=null, resolving: bool=false, local: bool=true, virtual: bool=false };
var pack_cache: std.ArrayList(CachedPack)=.empty;
var packs_loaded=false;
fn loadPacks() void {
    if (packs_loaded) return; packs_loaded=true;
    for (objectDirectories(),0..) |objects,j| {
        const path=join(objects,"pack"); const dir=std.c.opendir(z(path)) orelse continue; defer _=std.c.closedir(dir);
        while (std.c.readdir(dir)) |entry| { const name=std.mem.sliceTo(&entry.name,0); if (!std.mem.endsWith(u8,name,".idx")) continue; const packpath=join(path,fmt("{s}.pack",.{name[0..name.len-4]})); const data=load(packpath) orelse continue; const pack=packlib.decode(data) catch continue;
            pack_cache.append(a,.{.path=packpath,.pack=pack,.local=j==0}) catch unreachable;
        }
    }
    for (pack_cache.items) |*cached| { cached.resolving=true; if (cached.pack) |*p| p.resolve(readExternalObject) catch {}; cached.resolving=false; }
    loadMidxCache();
}
fn readExternalObject(oid: []const u8) ?Object { return readObject(oid); }
fn readObject(name: []const u8) ?Object {
    const oid=resolve(name) orelse return null;
    for (objectDirectories()) |objects| {
        const compressed=load(join(objects,fmt("{s}/{s}",.{oid[0..2],oid[2..]}))) orelse continue;
        if (readLooseObject(compressed)) |obj| return obj;
    }
    loadPacks(); for (pack_cache.items) |*cached| { if (cached.resolving) continue; if (cached.pack) |*p| { if (p.by_oid.get(oid)) |i| return p.records[i].object; } } return null;
}
fn readLooseObject(compressed: []const u8) ?Object {
    var cap: usize=4096;
    while (cap<=128*1024*1024) : (cap*=2) {
        const b=a.alloc(u8,cap) catch unreachable;
        var len: c_ulong=@intCast(cap);
        const rc=uncompress(b.ptr,&len,compressed.ptr,@intCast(compressed.len));
        if (rc == -5) { a.free(b); continue; }
        if (rc!=0) return null;
        const end=std.mem.indexOfScalar(u8,b[0..@intCast(len)],0) orelse return null;
        const space=std.mem.indexOfScalar(u8,b[0..end],' ') orelse return null;
        return .{.typ=b[0..space],.data=b[end+1..@intCast(len)]};
    }
    return null;
}
const TextMode=enum { unspecified, binary, text, auto };
const Attributes=struct { text: TextMode=.unspecified, eol: ?[]const u8=null, ident: bool=false };
const TextStats=struct {
    lf: usize=0, crlf: usize=0, cr: usize=0, nul: usize=0, printable: usize=0, control: usize=0,
    fn binary(s: TextStats) bool { return s.cr>0 or s.nul>0 or s.printable/128<s.control; }
    fn label(s: TextStats) []const u8 { return if (s.binary()) "-text" else if (s.lf>0 and s.crlf>0) "mixed" else if (s.crlf>0) "crlf" else if (s.lf>0) "lf" else "none"; }
};
fn textStats(data: []const u8) TextStats {
    var s: TextStats=.{}; var i: usize=0;
    while (i<data.len) : (i+=1) { const c=data[i]; if (c=='\r') { if (i+1<data.len and data[i+1]=='\n') { s.crlf+=1; i+=1; } else s.cr+=1; }
        else if (c=='\n') s.lf+=1 else if (c==0) { s.nul+=1; s.control+=1; }
        else if (c==127 or (c<32 and c!=8 and c!=9 and c!=27 and c!=12)) s.control+=1 else s.printable+=1;
    }
    if (data.len>0 and data[data.len-1]==26 and s.control>0) s.control-=1; return s;
}
fn applyAttributes(result: *Attributes, source: []const u8, path: []const u8) void {
    var lines=std.mem.splitScalar(u8,source,'\n'); while (lines.next()) |l| {
        var words=std.mem.tokenizeAny(u8,l," \t\r"); var pat=words.next() orelse continue; if (pat[0]=='#' or pat[0]=='[') continue;
        if (pat[0]=='/') pat=pat[1..]; const subject=if (std.mem.indexOfScalar(u8,pat,'/')==null) std.fs.path.basename(path) else path;
        if (fnmatch(z(pat),z(subject),if (std.mem.indexOfScalar(u8,pat,'/')!=null) 1 else 0)!=0) continue;
        while (words.next()) |attr| {
            if (eq(attr,"text") or eq(attr,"crlf")) result.text=.text else if (eq(attr,"-text") or eq(attr,"-crlf") or eq(attr,"binary")) result.text=.binary
            else if (eq(attr,"text=auto")) result.text=.auto else if (eq(attr,"!text")) result.text=.unspecified
            else if (eq(attr,"eol=lf") or eq(attr,"eol=crlf")) result.eol=attr[4..] else if (eq(attr,"!eol")) result.eol=null
            else if (eq(attr,"crlf=input")) { result.text=.text; result.eol="lf"; }
            else if (eq(attr,"ident")) result.ident=true else if (eq(attr,"-ident") or eq(attr,"!ident")) result.ident=false;
        }
    }
}
fn attributes(path: []const u8) Attributes {
    var result: Attributes=.{}; const g=gitdir() orelse return result; const root=env("GIT_WORK_TREE") orelse std.fs.path.dirname(g) orelse ".";
    if (configGet("core.attributesfile")) |p| { if (load(p)) |data| applyAttributes(&result,data,path); }
    if (load(join(root,".gitattributes"))) |data| applyAttributes(&result,data,path);
    var pos: usize=0; while (std.mem.indexOfScalarPos(u8,path,pos,'/')) |slash| { const dir=path[0..slash]; if (load(join(root,fmt("{s}/.gitattributes",.{dir})))) |data| applyAttributes(&result,data,path[slash+1..]); pos=slash+1; }
    if (load(join(g,"info/attributes"))) |data| applyAttributes(&result,data,path); return result;
}
fn effectiveText(attr: Attributes) TextMode {
    if (attr.text!=.unspecified) return attr.text; if (attr.eol!=null) return .text;
    const autocrlf=configGet("core.autocrlf") orelse "false"; return if (eq(autocrlf,"true") or eq(autocrlf,"input")) .auto else .binary;
}
fn outputCrlf(attr: Attributes) bool {
    if (effectiveText(attr)==.binary) return false;
    if (attr.eol) |e| return eq(e,"crlf"); const autocrlf=configGet("core.autocrlf") orelse "false";
    if (eq(autocrlf,"true")) return true; if (eq(autocrlf,"input")) return false; return eq(configGet("core.eol") orelse "native","crlf");
}
fn convertOut(stats: TextStats, attr: Attributes) bool {
    if (!outputCrlf(attr) or stats.lf==0) return false;
    return effectiveText(attr)!=.auto or (!stats.binary() and stats.crlf==0);
}
fn identConvert(data: []const u8, oid: ?[]const u8) []const u8 {
    var b: std.ArrayList(u8)=.empty; var off: usize=0;
    while (off<data.len) { if (starts(data[off..],"$Id$")) { b.appendSlice(a,if (oid) |id| fmt("$Id: {s} $",.{id}) else "$Id$") catch unreachable; off+=4; }
        else if (starts(data[off..],"$Id:")) { const end=std.mem.indexOfScalarPos(u8,data,off+4,'$') orelse { b.appendSlice(a,data[off..]) catch unreachable; break; }; if (std.mem.indexOfScalar(u8,data[off..end],'\n')==null) { b.appendSlice(a,if (oid) |id| fmt("$Id: {s} $",.{id}) else "$Id$") catch unreachable; off=end+1; } else { b.append(a,data[off]) catch unreachable; off+=1; } }
        else { b.append(a,data[off]) catch unreachable; off+=1; }
    } return b.toOwnedSlice(a) catch unreachable;
}
var conversion_index: ?[]IndexEntry=null;
fn cleanData(data: []const u8, path: []const u8, warn: bool, renormalize: bool) ?[]const u8 {
    const attr=attributes(path); const mode=effectiveText(attr); const stats=textStats(data); var normalize=mode!=.binary and stats.crlf>0;
    if (mode==.auto) { if (stats.binary()) return if (attr.ident) identConvert(data,null) else data;
        if (!renormalize) { if (conversion_index==null) conversion_index=readIndex(); if (entryFor(conversion_index.?,path)) |e| { if (readObject(e.oid)) |old| { if (textStats(old.data).crlf>0) normalize=false; } } }
    }
    if (warn and mode!=.binary) {
        var roundtrip=stats; if (normalize) { roundtrip.lf+=roundtrip.crlf; roundtrip.crlf=0; }
        if (convertOut(roundtrip,attr)) { roundtrip.crlf+=roundtrip.lf; roundtrip.lf=0; }
        const change=if (stats.crlf>roundtrip.crlf) "CRLF will be replaced by LF" else if (stats.lf>roundtrip.lf) "LF will be replaced by CRLF" else "";
        if (change.len>0) { const safe=configGet("core.safecrlf") orelse "warn";
            if (eq(safe,"true")) { emit(2,fmt("fatal: {s} in {s}\n",.{change,path})); return null; }
            if (!eq(safe,"false")) emit(2,fmt("warning: in the working copy of '{s}', {s} the next time Git touches it\n",.{path,change}));
        }
    }
    const result=if (normalize) std.mem.replaceOwned(u8,a,data,"\r\n","\n") catch unreachable else data;
    return if (attr.ident) identConvert(result,null) else result;
}
fn filtered(data: []const u8, path: ?[]const u8, no_filters: bool) []const u8 {
    if (no_filters or path==null) return data; return cleanData(data,path.?,false,false) orelse data;
}
fn checkoutData(data: []const u8, path: []const u8, oid: []const u8) []const u8 {
    const attr=attributes(path); var result=data;
    if (convertOut(textStats(data),attr)) { var b: std.ArrayList(u8)=.empty; for (data,0..) |c,i| { if (c=='\n' and (i==0 or data[i-1]!='\r')) b.append(a,'\r') catch unreachable; b.append(a,c) catch unreachable; } result=b.toOwnedSlice(a) catch unreachable; }
    return if (attr.ident) identConvert(result,oid) else result;
}
fn hashOne(typ: []const u8, data: []const u8, path: ?[]const u8, no_filters: bool, store: bool, literally: bool) u8 {
    const bytes=filtered(data,path,no_filters);
    if (!eq(typ,"blob") and !eq(typ,"tree") and !eq(typ,"commit") and !eq(typ,"tag")) return fatal(fmt("invalid object type \"{s}\"",.{typ}));
    if (!literally) {
        if (eq(typ,"commit") and !starts(bytes,"tree ")) return fatal("corrupt commit");
        if (eq(typ,"tag") and !starts(bytes,"object ")) return fatal("corrupt tag");
        if (eq(typ,"tree") and bytes.len>0) {
            const nul=std.mem.indexOfScalar(u8,bytes,0) orelse return fatal("too-short tree object");
            const space=std.mem.indexOfScalar(u8,bytes[0..nul],' ') orelse return fatal("malformed mode in tree entry");
            const mode=bytes[0..space];
            if (!eq(mode,"100644") and !eq(mode,"100755") and !eq(mode,"40000") and !eq(mode,"120000") and !eq(mode,"160000")) return fatal("malformed mode in tree entry");
            if (space+1==nul) return fatal("empty filename in tree entry");
            if (bytes.len<nul+21) return fatal("too-short tree object");
            if (bytes.len>nul+21) { if (std.mem.indexOf(u8,bytes[nul+21..],bytes[0..nul])) |_| return fatal("duplicateEntries"); }
        }
    }
    line(objectHash(typ,bytes,store) orelse return fatal("not a git repository (or any of the parent directories): .git"));
    return 0;
}
fn hashObject(args: Args) u8 {
    var typ: []const u8="blob"; var store=false; var ins: usize=0; var paths=false; var no_filters=false; var literal=false; var path: ?[]const u8=null;
    var files: std.ArrayList([]const u8)=.empty;
    var i: usize=0; var options=true;
    while (i<args.len) : (i+=1) {
        const s=args[i];
        if (!options) files.append(a,s) catch unreachable
        else if (eq(s,"--")) options=false
        else if (eq(s,"-w")) store=true
        else if (eq(s,"--stdin")) ins+=1
        else if (eq(s,"--stdin-paths")) paths=true
        else if (eq(s,"--no-filters")) no_filters=true
        else if (eq(s,"--literally")) literal=true
        else if (starts(s,"--path=")) path=s[7..]
        else if (eq(s,"-t") or eq(s,"--path")) { i+=1; if (i>=args.len) return 129; if (eq(s,"-t")) typ=args[i] else path=args[i]; }
        else if (starts(s,"-")) return 129
        else files.append(a,s) catch unreachable;
    }
    if (ins>1 or (paths and (ins>0 or files.items.len>0 or path!=null)) or (path!=null and no_filters)) { emit(2,"error: incompatible hash-object arguments\n"); return 129; }
    if (store and gitdir()==null) return fatal("not a git repository (or any of the parent directories): .git");
    if (ins>0) { const rc=hashOne(typ,stdin(),path,no_filters,store,literal); if (rc!=0) return rc; }
    if (paths) {
        var it=std.mem.splitScalar(u8,stdin(),'\n');
        while (it.next()) |p| { if (p.len!=0) files.append(a,p) catch unreachable; }
    }
    for (files.items) |f| {
        const data=load(f) orelse return fatal(fmt("could not open '{s}' for reading: No such file or directory",.{f}));
        const rc=hashOne(typ,data,path orelse f,no_filters,store,literal); if (rc!=0) return rc;
    }
    return 0;
}
fn catFile(args: Args) u8 {
    if (args.len>0 and (starts(args[0],"--batch"))) {
        var all=false; for (args) |s| { if (eq(s,"--batch-all-objects")) all=true; }
        if (all) { var seen=std.StringHashMap(void).init(a); var names: std.ArrayList([]const u8)=.empty; for (objectDirectories()) |d| { for (looseObjectNames(d)) |id| { if (!seen.contains(id)) { seen.put(id,{}) catch unreachable; names.append(a,id) catch unreachable; } } } loadPacks(); for (pack_cache.items) |cached| { if (cached.pack) |p| { for (p.records) |r| { if (r.oid) |id| { if (!seen.contains(id)) { seen.put(id,{}) catch unreachable; names.append(a,id) catch unreachable; } } } } } std.mem.sort([]const u8,names.items,{},struct { fn less(_: void,x: []const u8,y: []const u8) bool { return std.mem.lessThan(u8,x,y); } }.less); for (names.items) |name| catBatchOne(args[0],name); }
        else { while (inputRecord('\n')) |name| { catBatchOne(args[0],name); } } return 0;
    }
    if (args.len!=2) return 129;
    const obj=readObject(args[1]) orelse return fatal(if (eq(args[0],"-e")) "Not a valid object name" else "Not a valid object name");
    if (eq(args[0],"-e")) return 0;
    if (eq(args[0],"-t")) line(obj.typ)
    else if (eq(args[0],"-s")) line(fmt("{d}",.{obj.data.len}))
    else if (eq(args[0],"-p") and eq(obj.typ,"tree")) { return lsTree(&.{args[1]}); }
    else if (eq(args[0],"-p") or eq(args[0],obj.typ)) out(obj.data)
    else return fatal("bad file");
    return 0;
}
fn catBatchOne(mode: []const u8, name: []const u8) void {
    const oid=resolve(name); const obj=readObject(name); if (obj==null or oid==null) { line(fmt("{s} missing",.{name})); return; }
    if (std.mem.indexOfScalar(u8,mode,'=')) |pos| {
        var value=mode[pos+1..]; value=std.mem.replaceOwned(u8,a,value,"%(objectname)",oid.?) catch unreachable; value=std.mem.replaceOwned(u8,a,value,"%(objecttype)",obj.?.typ) catch unreachable; value=std.mem.replaceOwned(u8,a,value,"%(objectsize)",fmt("{d}",.{obj.?.data.len})) catch unreachable; line(value);
    } else line(fmt("{s} {s} {d}",.{oid.?,obj.?.typ,obj.?.data.len}));
    if (!starts(mode,"--batch-check")) { out(obj.?.data); out("\n"); }
}
fn revParse(args: Args) u8 {
    const g=gitdir() orelse return fatal("not a git repository (or any of the parent directories): .git");
    var quiet=false; var verify=false; var short: usize=40;
    for (args) |s| {
        if (eq(s,"--git-dir")) line(if (eq(g,join(cwd(),".git"))) ".git" else g)
        else if (eq(s,"--absolute-git-dir") or eq(s,"--git-common-dir")) line(g)
        else if (eq(s,"--show-toplevel")) line(std.fs.path.dirname(g) orelse g)
        else if (eq(s,"--is-inside-work-tree")) line(if (eq(configGet("core.bare") orelse "false","true")) "false" else "true")
        else if (eq(s,"--is-bare-repository")) line(configGet("core.bare") orelse "false")
        else if (eq(s,"--show-object-format")) line("sha1")
        else if (eq(s,"--show-ref-format")) line("files")
        else if (eq(s,"--show-prefix")) line("")
        else if (eq(s,"--sq-quote")) {}
        else if (eq(s,"--verify")) verify=true
        else if (eq(s,"--quiet") or eq(s,"-q")) quiet=true
        else if (eq(s,"--short")) short=7
        else if (starts(s,"--short=")) short=@max(4,std.fmt.parseInt(usize,s[8..],10) catch 7)
        else if (starts(s,"--")) {}
        else if (resolve(s)) |oid| line(oid[0..@min(oid.len,short)])
        else { if (quiet) return 1; if (verify) return fatal("Needed a single revision"); line(s); return fatal(fmt("ambiguous argument '{s}': unknown revision or path not in the working tree.",.{s})); }
    }
    return 0;
}
const zeroOid="0000000000000000000000000000000000000000";
fn header(data: []const u8, key: []const u8) ?[]const u8 {
    var it=std.mem.splitScalar(u8,data,'\n');
    while (it.next()) |l| { if (l.len==0) break; if (starts(l,key) and l.len>key.len and l[key.len]==' ') return l[key.len+1..]; }
    return null;
}
fn remove(p: []const u8) void { _=std.c.unlink(z(p)); }
fn validRef(s: []const u8, single: bool) bool {
    if (s.len==0 or eq(s,"@") or s[0]=='/' or s[s.len-1]=='/' or s[s.len-1]=='.') return false;
    if (!single and std.mem.indexOfScalar(u8,s,'/')==null) return false;
    for (s) |c| { if (c<=32 or c==127 or std.mem.indexOfScalar(u8,"~^:?*[\\",c)!=null) return false; }
    if (std.mem.indexOf(u8,s,"..")!=null or std.mem.indexOf(u8,s,"@{")!=null or std.mem.indexOf(u8,s,"//")!=null) return false;
    var it=std.mem.splitScalar(u8,s,'/'); while (it.next()) |part| { if (part.len==0 or part[0]=='.' or std.mem.endsWith(u8,part,".lock")) return false; }
    return true;
}
fn derefName(g: []const u8, name: []const u8) ?[]const u8 {
    var n=name; var count: usize=0;
    while (count<16) : (count+=1) { const d=load(join(g,n)) orelse return n; if (!starts(d,"ref: ")) return n; n=trim(d[5..]); }
    return null;
}
fn appendFile(p: []const u8, data: []const u8) void { _=put(p,fmt("{s}{s}",.{load(p) orelse "",data})); }
fn updateRefValue(name: []const u8, value: ?[]const u8, old: ?[]const u8, no_deref: bool, message: []const u8, log_mode: i8) u8 {
    const g=gitdir() orelse return fatal("not a git repository");
    if (!validRef(name,true)) return fatal(fmt("update_ref failed for ref '{s}': refusing to update ref with bad name '{s}'",.{name,name}));
    const n=if (no_deref) name else derefName(g,name) orelse return fatal("cannot lock ref: unable to resolve reference");
    const previous=resolve(n) orelse zeroOid;
    if (old) |o| { if (!eq(o,previous)) return fatal(fmt("update_ref failed for ref '{s}': cannot lock ref '{s}': is at {s} but expected {s}",.{name,n,previous,o})); }
    const deleting=value==null or eq(value.?,zeroOid);
    if (!deleting) {
        const obj=readObject(value.?) orelse return fatal(fmt("update_ref failed for ref '{s}': cannot update ref '{s}': trying to write ref '{s}' with nonexistent object {s}",.{name,n,n,value.?}));
        if (starts(n,"refs/heads/") and !eq(obj.typ,"commit")) return fatal(fmt("update_ref failed for ref '{s}': cannot update ref '{s}': trying to write non-commit object {s} to branch '{s}'",.{name,n,value.?,n}));
        if (exists(join(g,fmt("{s}.lock",.{n}))) and !refstream.ownsLock(n)) return fatal(fmt("update_ref failed for ref '{s}': cannot lock ref '{s}': File exists",.{name,n}));
        const destination=join(g,n); const lockpath=fmt("{s}.lock",.{destination});
        if (!put(lockpath,fmt("{s}\n",.{value.?}))) return fatal(fmt("cannot lock ref '{s}'",.{n}));
        if (std.c.rename(z(lockpath),z(destination))!=0) { remove(lockpath); return fatal(fmt("cannot update ref '{s}'",.{n})); }
    } else {
        remove(join(g,n));
        if (load(join(g,"packed-refs"))) |data| { var b: std.ArrayList(u8)=.empty; var it=std.mem.splitScalar(u8,data,'\n'); while (it.next()) |l| { if (l.len>41 and eq(l[41..],n)) continue; if (l.len>0) { b.appendSlice(a,l) catch unreachable; b.append(a,'\n') catch unreachable; } } _=put(join(g,"packed-refs"),b.items); }
    }
    const logsetting=configGet("core.logallrefupdates") orelse "false";
    const should_log=log_mode==1 or (log_mode!=-1 and (eq(logsetting,"always") or (eq(logsetting,"true") and (starts(n,"refs/heads/") or starts(n,"refs/remotes/") or eq(n,"HEAD")))));
    const logpath=join(g,fmt("logs/{s}",.{n}));
    const entry=fmt("{s} {s} {s}\t{s}\n",.{previous,value orelse zeroOid,ident(true) orelse "unknown <unknown> 0 +0000",message});
    if (!deleting and (should_log or exists(logpath))) appendFile(logpath,entry);
    if (deleting) remove(logpath);
    if (load(join(g,"HEAD"))) |head| { if (!no_deref and starts(head,"ref: ") and eq(trim(head[5..]),n) and (should_log or exists(join(g,"logs/HEAD")))) appendFile(join(g,"logs/HEAD"),entry); }
    return 0;
}
fn updateRef(args: Args) u8 {
    var pos: std.ArrayList([]const u8)=.empty; var del=false; var noderef=false; var msg: []const u8=""; var logmode: i8=0; var input=false; var nul=false; var batch=false;
    var i: usize=0; while (i<args.len) : (i+=1) { const s=args[i];
        if (eq(s,"-d")) del=true else if (eq(s,"--no-deref")) noderef=true else if (eq(s,"--create-reflog")) logmode=1 else if (eq(s,"--no-create-reflog")) logmode=-1
        else if (eq(s,"-m")) { i+=1; if (i==args.len) return 129; msg=args[i]; }
        else if (eq(s,"--stdin")) input=true else if (eq(s,"-z")) nul=true else if (eq(s,"--batch-updates")) batch=true else if (starts(s,"-")) return 129 else pos.append(a,s) catch unreachable;
    }
    if (input) return refstream.run(.{.nul=nul,.noderef=noderef,.message=msg,.logmode=logmode,.batch=batch});
    if (nul) { emit(2,"usage: git update-ref\n"); return 129; }
    if (pos.items.len<1 or (!del and pos.items.len<2)) return 129;
    const p=pos.items; const val=if (del) null else resolve(p[1]) orelse return fatal(fmt("{s}: not a valid SHA1",.{p[1]}));
    const idx: usize=if (del) 1 else 2;
    const old=if (p.len>idx) resolve(p[idx]) orelse return fatal("not a valid old SHA1") else null;
    return updateRefValue(p[0],val,old,noderef,msg,logmode);
}
const Ref=struct { name: []const u8, oid: []const u8 };
fn walkRefs(g: []const u8, prefix: []const u8, refs: *std.ArrayList(Ref)) void {
    const dir=std.c.opendir(z(join(g,prefix))) orelse return; defer _=std.c.closedir(dir);
    while (std.c.readdir(dir)) |e| { const name=std.mem.sliceTo(&e.name,0); if (eq(name,".") or eq(name,"..")) continue; const n=join(prefix,name); if (e.type==4) walkRefs(g,n,refs) else if (resolve(n)) |oid| { refs.append(a,.{.name=n,.oid=oid}) catch unreachable; } }
}
fn allRefs() []Ref {
    const g=gitdir() orelse return &.{}; var refs: std.ArrayList(Ref)=.empty; walkRefs(g,"refs",&refs);
    if (load(join(g,"packed-refs"))) |data| { var it=std.mem.splitScalar(u8,data,'\n'); while (it.next()) |l| { if (l.len<42 or l[0]=='#' or l[0]=='^') continue; var found=false; for (refs.items) |r| { if (eq(r.name,l[41..])) found=true; } if (!found) refs.append(a,.{.name=l[41..],.oid=l[0..40]}) catch unreachable; } }
    std.mem.sort(Ref,refs.items,{},struct { fn less(_: void,x: Ref,y: Ref) bool { return std.mem.lessThan(u8,x.name,y.name); } }.less); return refs.toOwnedSlice(a) catch unreachable;
}
fn symbolicRef(args: Args) u8 {
    var p: std.ArrayList([]const u8)=.empty; var del=false; var short=false; var recurse=true; var i: usize=0;
    while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"-d") or eq(s,"--delete")) del=true else if (eq(s,"--short")) short=true else if (eq(s,"--no-recurse")) recurse=false else if (eq(s,"-m")) i+=1 else if (!starts(s,"-")) p.append(a,s) catch unreachable; }
    const g=gitdir() orelse return fatal("not a git repository"); if (p.items.len==0) return 129; const n=p.items[0];
    if (del) { if (!starts(load(join(g,n)) orelse "","ref: ")) return 1; remove(join(g,n)); return 0; }
    if (p.items.len==2) { const target=p.items[1]; if (!starts(target,"refs/") or !validRef(target,false)) return fatal("Refusing to point HEAD outside of refs/"); return if (put(join(g,n),fmt("ref: {s}\n",.{target}))) 0 else 1; }
    const data=load(join(g,n)) orelse return 1; if (!starts(data,"ref: ")) return 1;
    var target=trim(data[5..]); if (recurse) target=derefName(g,target) orelse return 1;
    if (short and starts(target,"refs/heads/")) target=target[11..]; line(target); return 0;
}
fn showRef(args: Args) u8 {
    var hash=false; var quiet=false; var verify=false; var head=false; var heads=false; var tags=false; var exist=false; var pats: std.ArrayList([]const u8)=.empty;
    for (args) |s| { if (eq(s,"-s") or eq(s,"--hash")) hash=true else if (eq(s,"-q") or eq(s,"--quiet")) quiet=true else if (eq(s,"--verify")) verify=true else if (eq(s,"--head")) head=true else if (eq(s,"--heads") or eq(s,"--branches")) heads=true else if (eq(s,"--tags")) tags=true else if (eq(s,"--exists")) exist=true else if (!starts(s,"-")) pats.append(a,s) catch unreachable; }
    if (verify or exist) { if (pats.items.len==0) return 1; for (pats.items) |n| { const oid=resolve(n) orelse { if (!quiet and !exist) return fatal(fmt("'{s}' - not a valid ref",.{n})); return if (exist) 2 else 1; }; if (!quiet and !exist) line(if (hash) oid else fmt("{s} {s}",.{oid,n})); } return 0; }
    var count: usize=0; if (head) { if (resolve("HEAD")) |oid| { if (!quiet) line(if (hash) oid else fmt("{s} HEAD",.{oid})); count+=1; } }
    for (allRefs()) |r| {
        if ((heads or tags) and !(heads and starts(r.name,"refs/heads/")) and !(tags and starts(r.name,"refs/tags/"))) continue;
        var matched=pats.items.len==0; for (pats.items) |p| { if (eq(r.name,p) or std.mem.endsWith(u8,r.name,fmt("/{s}",.{p}))) matched=true; } if (!matched) continue;
        if (!quiet) line(if (hash) r.oid else fmt("{s} {s}",.{r.oid,r.name})); count+=1;
    }
    return if (count>0) 0 else 1;
}
const IndexEntry=struct { path: []const u8, oid: []const u8, mode: u32=0o100644, stage: u16=0 };
fn indexPath() []const u8 { return env("GIT_INDEX_FILE") orelse join(gitdir() orelse ".git","index"); }
fn be32(b: []const u8) u32 { return std.mem.readInt(u32,b[0..4],.big); }
fn readIndex() []IndexEntry {
    const data=load(indexPath()) orelse return &.{}; if (data.len<12 or !eq(data[0..4],"DIRC")) return &.{};
    var list: std.ArrayList(IndexEntry)=.empty; var off: usize=12; const count=be32(data[8..12]);
    for (0..count) |_| { if (off+62>data.len) break; const end=std.mem.indexOfScalarPos(u8,data,off+62,0) orelse break; const hex=std.fmt.bytesToHex(data[off+40..][0..20].*,.lower); const flags=std.mem.readInt(u16,data[off+60..][0..2],.big); list.append(a,.{.path=data[off+62..end],.oid=a.dupe(u8,&hex) catch unreachable,.mode=be32(data[off+24..]),.stage=(flags>>12)&3}) catch unreachable; off+=(end-off+8)&~@as(usize,7); }
    return list.toOwnedSlice(a) catch unreachable;
}
fn oidBytes(oid: []const u8) [20]u8 { var bytes: [20]u8=undefined; _=std.fmt.hexToBytes(&bytes,oid) catch { @memset(&bytes,0); }; return bytes; }
fn writeIndex(entries: []IndexEntry) bool {
    std.mem.sort(IndexEntry,entries,{},struct { fn less(_: void,x: IndexEntry,y: IndexEntry) bool { if (eq(x.path,y.path)) return x.stage<y.stage; return std.mem.lessThan(u8,x.path,y.path); } }.less);
    var b: std.ArrayList(u8)=.empty; b.appendSlice(a,"DIRC\x00\x00\x00\x02") catch unreachable; var count: [4]u8=undefined; std.mem.writeInt(u32,&count,@intCast(entries.len),.big); b.appendSlice(a,&count) catch unreachable;
    for (entries) |e| { const start=b.items.len; var stat: [40]u8=@splat(0); std.mem.writeInt(u32,stat[24..28],e.mode,.big); b.appendSlice(a,&stat) catch unreachable; b.appendSlice(a,&oidBytes(e.oid)) catch unreachable; var flags: [2]u8=undefined; std.mem.writeInt(u16,&flags,@as(u16,@intCast(@min(e.path.len,4095)))|(e.stage<<12),.big); b.appendSlice(a,&flags) catch unreachable; b.appendSlice(a,e.path) catch unreachable; b.append(a,0) catch unreachable; while ((b.items.len-start)%8!=0) b.append(a,0) catch unreachable; }
    var digest: [20]u8=undefined; std.crypto.hash.Sha1.hash(b.items,&digest,.{}); b.appendSlice(a,&digest) catch unreachable; return put(indexPath(),b.items);
}
var renormalizing=false;
fn stageFile(entries: *std.ArrayList(IndexEntry), path: []const u8) bool {
    const data=load(path) orelse return false; const cleaned=cleanData(data,path,true,renormalizing) orelse return false; const oid=objectHash("blob",cleaned,true) orelse return false;
    var mode: u32=0o100644; if (access(z(path),1)==0) mode=0o100755;
    for (entries.items) |*e| { if (eq(e.path,path)) { e.oid=oid; e.mode=mode; return true; } }
    entries.append(a,.{.path=a.dupe(u8,path) catch unreachable,.oid=oid,.mode=mode}) catch unreachable; return true;
}
fn addPath(entries: *std.ArrayList(IndexEntry), path: []const u8) bool {
    if (std.c.opendir(z(path))) |dir| { defer _=std.c.closedir(dir); while (std.c.readdir(dir)) |e| { const name=std.mem.sliceTo(&e.name,0); if (eq(name,".git") or eq(name,".") or eq(name,"..")) continue; const p=if (eq(path,".")) name else join(path,name); if (!addPath(entries,p)) return false; } return true; }
    return stageFile(entries,path);
}
fn addCommand(args: Args) u8 {
    var entries: std.ArrayList(IndexEntry)=.empty; entries.appendSlice(a,readIndex()) catch unreachable; var any=false; var all=false;
    for (args) |s| { if (eq(s,"--renormalize")) renormalizing=true; }
    for (args) |s| { if (eq(s,"-A") or eq(s,"--all") or eq(s,"-u")) { all=true; continue; } if (starts(s,"-")) continue; any=true; if (!addPath(&entries,s)) return fatal(fmt("pathspec '{s}' did not match any files",.{s})); }
    if (all) { if (!addPath(&entries,".")) return 1; var i: usize=0; while (i<entries.items.len) { if (!exists(entries.items[i].path)) _=entries.orderedRemove(i) else i+=1; } }
    if (!any and !all) return 0; return if (writeIndex(entries.items)) 0 else 1;
}
fn treeFromIndex(entries: []const IndexEntry, prefix: []const u8) ?[]const u8 {
    var b: std.ArrayList(u8)=.empty; var i: usize=0;
    while (i<entries.len) { const e=entries[i]; if (!starts(e.path,prefix)) { i+=1; continue; } if (e.stage!=0) return null; const rest=e.path[prefix.len..];
        if (std.mem.indexOfScalar(u8,rest,'/')) |slash| { const sub=fmt("{s}{s}/",.{prefix,rest[0..slash]}); const oid=treeFromIndex(entries,sub) orelse return null; b.appendSlice(a,fmt("40000 {s}\x00",.{rest[0..slash]})) catch unreachable; b.appendSlice(a,&oidBytes(oid)) catch unreachable; while (i<entries.len and starts(entries[i].path,sub)) : (i+=1) {} }
        else { b.appendSlice(a,fmt("{o} {s}\x00",.{e.mode,rest})) catch unreachable; b.appendSlice(a,&oidBytes(e.oid)) catch unreachable; i+=1; }
    }
    return objectHash("tree",b.items,true);
}
fn commitTree(args: Args) u8 {
    if (args.len==0) return 129; const tree=resolve(args[0]) orelse return fatal("not a valid object name"); var b: std.ArrayList(u8)=.empty; b.appendSlice(a,fmt("tree {s}\n",.{tree})) catch unreachable; var message: ?[]const u8=null; var i: usize=1;
    while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"-p") or eq(s,"-m") or eq(s,"-F")) { i+=1; if (i==args.len) return 129; if (eq(s,"-p")) { const oid=resolve(args[i]) orelse return fatal("not a valid object name"); b.appendSlice(a,fmt("parent {s}\n",.{oid})) catch unreachable; } else if (eq(s,"-F")) message=if (eq(args[i],"-")) stdin() else load(args[i]) orelse return 1 else message=fmt("{s}{s}{s}",.{message orelse "",if (message!=null) "\n\n" else "",args[i]}); } }
    const author=ident(false) orelse return fatal("unable to auto-detect email address"); const committer=ident(true) orelse return fatal("unable to auto-detect email address"); const msg=message orelse stdin();
    b.appendSlice(a,fmt("author {s}\ncommitter {s}\n\n{s}{s}",.{author,committer,msg,if (msg.len>0 and msg[msg.len-1]!='\n') "\n" else ""})) catch unreachable;
    line(objectHash("commit",b.items,true) orelse return 1); return 0;
}
fn makeCommit(tree: []const u8, parent: ?[]const u8, msg: []const u8) ?[]const u8 {
    const data=fmt("tree {s}\n{s}author {s}\ncommitter {s}\n\n{s}{s}",.{tree,if (parent) |p| fmt("parent {s}\n",.{p}) else "",ident(false) orelse return null,ident(true) orelse return null,msg,if (msg.len>0 and msg[msg.len-1]!='\n') "\n" else ""}); return objectHash("commit",data,true);
}
var explicit_author: ?[]const u8=null;
var explicit_author_date: ?[]const u8=null;
fn commit(args: Args) u8 {
    var msg: ?[]const u8=null; var quiet=false; var all=false; var allow=false; var amend=false; var i: usize=0; var paths: std.ArrayList([]const u8)=.empty; var noedit=false;
    while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"--")) { paths.appendSlice(a,args[i+1..]) catch unreachable; break; }
        if (eq(s,"-m") or eq(s,"-F")) { i+=1; if (i==args.len) return 129; const text=if (eq(s,"-F")) (if (eq(args[i],"-")) stdin() else load(args[i]) orelse return 1) else args[i]; msg=if (msg) |previous| fmt("{s}\n\n{s}",.{previous,text}) else text; }
        else if (starts(s,"-m") and s.len>2) msg=s[2..] else if (eq(s,"-q") or eq(s,"--quiet")) quiet=true
        else if (eq(s,"-a") or eq(s,"-am") or eq(s,"-qam") or eq(s,"-qm")) { all=!eq(s,"-qm"); if (starts(s,"-q")) quiet=true; if (s[s.len-1]=='m') { i+=1; if (i==args.len) return 129; msg=args[i]; } }
        else if (starts(s,"--author=")) explicit_author=s[9..] else if (starts(s,"--date=")) explicit_author_date=s[7..]
        else if (eq(s,"--author") or eq(s,"--date")) { i+=1; if (i==args.len) return 129; if (eq(s,"--author")) explicit_author=args[i] else explicit_author_date=args[i]; }
        else if (eq(s,"--allow-empty")) allow=true else if (eq(s,"--amend")) amend=true else if (eq(s,"--no-edit")) noedit=true else if (!starts(s,"-")) paths.append(a,s) catch unreachable;
    }
    if (all or paths.items.len>0) { var entries: std.ArrayList(IndexEntry)=.empty; entries.appendSlice(a,readIndex()) catch unreachable; var n: usize=0;
        while (n<entries.items.len) { const path=entries.items[n].path; if (!all and !pathMatches(path,paths.items)) { n+=1; continue; } if (!exists(path)) { _=entries.orderedRemove(n); continue; } if (!stageFile(&entries,path)) return 1; n+=1; }
        if (!writeIndex(entries.items)) return 1;
    }
    if (amend and noedit and msg==null) { const obj=readObject("HEAD") orelse return 1; const pos=std.mem.indexOf(u8,obj.data,"\n\n") orelse return 1; msg=obj.data[pos+2..]; }
    const tree=treeFromIndex(readIndex(),"") orelse return 1; var parent=resolve("HEAD");
    if (parent) |p| { if (readObject(p)) |obj| { if (!allow and !amend and eq(header(obj.data,"tree") orelse "",tree)) { if (!quiet) line("nothing to commit, working tree clean"); return 1; } if (amend) parent=header(obj.data,"parent"); } }
    const oid=makeCommit(tree,parent,msg orelse return fatal("no commit message provided")) orelse return 1;
    const rc=updateRefValue("HEAD",oid,null,false,fmt("commit: {s}",.{msg.?}),0); if (rc!=0) return rc;
    if (!quiet) { const g=gitdir().?; const head=trim(load(join(g,"HEAD")) orelse ""); const branch=if (starts(head,"ref: refs/heads/")) head[16..] else "detached HEAD"; line(fmt("[{s}{s} {s}] {s}",.{branch,if (parent==null) " (root-commit)" else "",oid[0..7],trim(msg.?)})); }
    return 0;
}
fn readTreeEntries(oid: []const u8, prefix: []const u8, entries: *std.ArrayList(IndexEntry)) bool {
    const obj=readObject(oid) orelse return false; if (eq(obj.typ,"commit")) return readTreeEntries(header(obj.data,"tree") orelse return false,prefix,entries); if (!eq(obj.typ,"tree")) return false;
    var off: usize=0; while (off<obj.data.len) { const sp=std.mem.indexOfScalarPos(u8,obj.data,off,' ') orelse return false; const nul=std.mem.indexOfScalarPos(u8,obj.data,sp,0) orelse return false; if (nul+21>obj.data.len) return false;
        const mode=std.fmt.parseInt(u32,obj.data[off..sp],8) catch return false; const path=fmt("{s}{s}",.{prefix,obj.data[sp+1..nul]}); const hex=std.fmt.bytesToHex(obj.data[nul+1..][0..20].*,.lower); const id=a.dupe(u8,&hex) catch unreachable;
        if (mode==0o40000) { if (!readTreeEntries(id,fmt("{s}/",.{path}),entries)) return false; } else entries.append(a,.{.path=path,.oid=id,.mode=mode}) catch unreachable; off=nul+21;
    } return true;
}
fn checkout(args: Args) u8 {
    for (args,0..) |s,j| { if (eq(s,"--")) {
        var source: std.ArrayList(IndexEntry)=.empty; var tree: ?[]const u8=null;
        for (args[0..j]) |v| { if (!starts(v,"-")) tree=v; }
        if (tree) |t| { if (!readTreeEntries(t,"",&source)) return 128; } else source.appendSlice(a,readIndex()) catch unreachable;
        var count: usize=0; for (source.items) |e| { if (pathMatches(e.path,args[j+1..])) { if (!materialize(e)) return 1; count+=1; } }
        if (count==0) return 1; if (tree!=null) { var index: std.ArrayList(IndexEntry)=.empty; index.appendSlice(a,readIndex()) catch unreachable; for (source.items) |e| { if (!pathMatches(e.path,args[j+1..])) continue; var found=false; for (index.items) |*existing| { if (eq(existing.path,e.path)) { existing.*=e; found=true; } } if (!found) index.append(a,e) catch unreachable; } if (!writeIndex(index.items)) return 1; }
        return 0;
    } }
    var branch: ?[]const u8=null; var orphan=false; var create=false; var target: ?[]const u8=null; var i: usize=0;
    while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"--orphan") or eq(s,"-b") or eq(s,"-B") or eq(s,"-c") or eq(s,"-C")) { orphan=eq(s,"--orphan"); create=true; i+=1; if (i==args.len) return 129; branch=args[i]; } else if (!starts(s,"-")) target=s; }
    const g=gitdir() orelse return 128;
    if (orphan) { _=put(join(g,"HEAD"),fmt("ref: refs/heads/{s}\n",.{branch.?})); return 0; }
    const oid=resolve(target orelse "HEAD"); if (oid==null and !create) return 1;
    if (create) { if (oid) |id| { const rc=updateRefValue(fmt("refs/heads/{s}",.{branch.?}),id,null,false,"",0); if (rc!=0) return rc; } _=put(join(g,"HEAD"),fmt("ref: refs/heads/{s}\n",.{branch.?})); }
    else if (target) |t| { if (eq(t,"HEAD")) {} else if (resolve(fmt("refs/heads/{s}",.{t}))!=null) _=put(join(g,"HEAD"),fmt("ref: refs/heads/{s}\n",.{t})) else _=put(join(g,"HEAD"),fmt("{s}\n",.{oid.?})); }
    if (oid) |id| { var entries: std.ArrayList(IndexEntry)=.empty; if (!readTreeEntries(id,"",&entries)) return 1; for (readIndex()) |e| { if (entryFor(entries.items,e.path)==null) remove(e.path); } for (entries.items) |e| { if (!materialize(e)) return 1; } _=writeIndex(entries.items); }
    return 0;
}
fn pathMatches(path: []const u8, patterns: Args) bool {
    if (patterns.len==0) return true; for (patterns) |p| { if (eq(p,".") or eq(path,p) or starts(path,fmt("{s}/",.{p})) or fnmatch(z(p),z(path),0)==0) return true; } return false;
}
fn materialize(e: IndexEntry) bool {
    const obj=readObject(e.oid) orelse return false; if (!put(e.path,checkoutData(obj.data,e.path,e.oid))) return false;
    _=std.c.chmod(z(e.path),if (e.mode==0o100755) 0o755 else 0o644); return true;
}
fn resetCommand(args: Args) u8 {
    var hard=false; var soft=false; var target: []const u8="HEAD"; var paths: Args=&.{};
    for (args,0..) |s,i| { if (eq(s,"--hard")) hard=true else if (eq(s,"--soft")) soft=true else if (eq(s,"--")) { paths=args[i+1..]; break; } else if (!starts(s,"-")) target=s; }
    const oid=resolve(target) orelse return 1; var entries: std.ArrayList(IndexEntry)=.empty; if (!readTreeEntries(oid,"",&entries)) return 1;
    if (!soft) { if (hard) { for (readIndex()) |e| { if (entryFor(entries.items,e.path)==null) remove(e.path); } for (entries.items) |e| { if (!materialize(e)) return 1; } }
        if (paths.len>0) { var result: std.ArrayList(IndexEntry)=.empty; for (readIndex()) |e| { if (!pathMatches(e.path,paths)) result.append(a,e) catch unreachable; } for (entries.items) |e| { if (pathMatches(e.path,paths)) result.append(a,e) catch unreachable; } if (!writeIndex(result.items)) return 1; }
        else if (!writeIndex(entries.items)) return 1;
    }
    if (paths.len==0) { if (resolve("HEAD")) |previous| { _=updateRefValue("ORIG_HEAD",previous,null,true,"",0); } return updateRefValue("HEAD",oid,null,false,"reset: moving",0); } return 0;
}
fn lsFiles(args: Args) u8 {
    var stage=false; var nul=false; var eol=false; var others=false; var deleted=false; var modified=false; var cached=true; var patterns: std.ArrayList([]const u8)=.empty;
    for (args) |s| { if (eq(s,"--stage") or eq(s,"-s")) stage=true else if (eq(s,"-z")) nul=true else if (eq(s,"--eol")) eol=true else if (eq(s,"-o") or eq(s,"--others")) { others=true; cached=false; } else if (eq(s,"-d") or eq(s,"--deleted")) { deleted=true; cached=false; } else if (eq(s,"-m") or eq(s,"--modified")) { modified=true; cached=false; } else if (eq(s,"-c") or eq(s,"--cached")) cached=true else if (!starts(s,"-")) patterns.append(a,s) catch unreachable; }
    var entries: std.ArrayList(IndexEntry)=.empty; const index=readIndex(); if (others) collectFiles(".",&entries); if (cached or deleted or modified) entries.appendSlice(a,index) catch unreachable;
    std.mem.sort(IndexEntry,entries.items,{},struct { fn less(_: void,x: IndexEntry,y: IndexEntry) bool { return std.mem.lessThan(u8,x.path,y.path); } }.less);
    for (entries.items) |e| { if (!pathMatches(e.path,patterns.items)) continue; const tracked=entryFor(index,e.path)!=null; if (others and !cached and tracked) continue; const work=load(e.path); if (deleted and !cached and work!=null) continue;
        if (modified and !cached) { if (work) |data| { const oid=objectHash("blob",filtered(data,e.path,false),false) orelse continue; if (eq(oid,e.oid)) continue; } }
        if (eol) { const obj=if (tracked) readObject(e.oid) else null; const attr=attributes(e.path); const text=if (attr.text==.binary) "-text" else if (attr.text==.auto) "text=auto" else if (attr.text==.text or attr.eol!=null) "text" else "";
            const description=if (attr.eol) |v| fmt("{s}{s}eol={s}",.{text,if (text.len>0) " " else "",v}) else text;
            out(fmt("i/{s}    w/{s}    attr/{s}\t{s}",.{if (obj) |o| textStats(o.data).label() else "",if (work) |d| textStats(d).label() else "",if (attr.text==.binary) "-text" else description,e.path}));
        } else out(if (stage) fmt("{o} {s} {d}\t{s}",.{e.mode,e.oid,e.stage,e.path}) else e.path);
        out(if (nul) "\x00" else "\n");
    } return 0;
}
fn rmCommand(args: Args) u8 {
    var paths: std.ArrayList([]const u8)=.empty; var cached=false; var force=false; var quiet=false; var ignore=false; var recursive=false;
    for (args) |s| { if (eq(s,"--cached")) cached=true else if (eq(s,"-f") or eq(s,"--force")) force=true else if (eq(s,"-q") or eq(s,"--quiet")) quiet=true else if (eq(s,"--ignore-unmatch")) ignore=true else if (eq(s,"-r")) recursive=true else if (!starts(s,"-")) paths.append(a,s) catch unreachable; }
    if (paths.items.len==0) return 129; var kept: std.ArrayList(IndexEntry)=.empty; var removed: std.ArrayList(IndexEntry)=.empty;
    for (readIndex()) |e| { if (pathMatches(e.path,paths.items)) { if (!recursive) { for (paths.items) |p| { if (!eq(p,e.path) and starts(e.path,fmt("{s}/",.{p}))) return fatal("not removing recursively without -r"); } }
            if (!force and !cached) { if (load(e.path)) |data| { const oid=objectHash("blob",filtered(data,e.path,false),false) orelse return 1; if (!eq(oid,e.oid)) return fatal(fmt("the following file has local modifications: {s}",.{e.path})); } }
            removed.append(a,e) catch unreachable;
        } else kept.append(a,e) catch unreachable;
    }
    if (removed.items.len==0 and !ignore) return fatal("pathspec did not match any files");
    for (removed.items) |e| { if (!cached) remove(e.path); if (!quiet) line(fmt("rm '{s}'",.{e.path})); }
    return if (writeIndex(kept.items)) 0 else 1;
}
fn mvCommand(args: Args) u8 {
    var p: std.ArrayList([]const u8)=.empty; var force=false; for (args) |s| { if (eq(s,"-f")) force=true else if (!starts(s,"-")) p.append(a,s) catch unreachable; } if (p.items.len<2) return 129;
    const dest=p.items[p.items.len-1]; const d=std.c.opendir(z(dest)); const directory=d!=null; if (d) |dir| _=std.c.closedir(dir);
    const entries=readIndex(); for (p.items[0..p.items.len-1]) |source| { const target=if (directory) join(dest,std.fs.path.basename(source)) else dest; if (!force and exists(target)) return fatal("destination exists");
        var tracked=false; for (entries) |*e| { if (eq(e.path,source) or starts(e.path,fmt("{s}/",.{source}))) { tracked=true; e.path=fmt("{s}{s}",.{target,e.path[source.len..]}); } } if (!tracked) return fatal("not under version control"); if (std.c.rename(z(source),z(target))!=0) return fatal("renaming failed");
    } return if (writeIndex(entries)) 0 else 1;
}
fn branchCommand(args: Args) u8 {
    const g=gitdir() orelse return 128; var p: std.ArrayList([]const u8)=.empty; var del=false; var rename=false; var force=false;
    for (args,0..) |s,i| {
        if (starts(s,"--set-upstream-to=") or eq(s,"--set-upstream-to") or starts(s,"--set-upstream=")) {
            const value=if (std.mem.indexOfScalar(u8,s,'=')) |n| s[n+1..] else if (i+1<args.len) args[i+1] else return 129;
            const head=trim(load(join(g,"HEAD")) orelse return 1); if (!starts(head,"ref: refs/heads/")) return 1;
            const branch=if (std.mem.indexOfScalar(u8,s,'=')!=null and i+1<args.len) args[i+1] else head[16..];
            const target=if (starts(value,"refs/")) value else fmt("refs/heads/{s}",.{value}); if (resolve(target)==null) return 1;
            if (!configSet(join(g,"config"),fmt("branch.{s}.remote",.{branch}),".",false)) return 1;
            return if (configSet(join(g,"config"),fmt("branch.{s}.merge",.{branch}),target,false)) 0 else 1;
        }
    }
    for (args) |s| { if (eq(s,"-d") or eq(s,"-D")) del=true else if (eq(s,"-m") or eq(s,"-M")) rename=true else if (eq(s,"-f")) force=true else if (!starts(s,"-")) p.append(a,s) catch unreachable; }
    if (del) { for (p.items) |n| { const rc=updateRefValue(fmt("refs/heads/{s}",.{n}),null,null,false,"",0); if (rc!=0) return rc; } return 0; }
    if (rename) { const head=trim(load(join(g,"HEAD")) orelse return 1); const old=if (p.items.len==2) fmt("refs/heads/{s}",.{p.items[0]}) else if (starts(head,"ref: ")) head[5..] else return 1; const name=if (p.items.len>0) p.items[p.items.len-1] else return 129; const target=fmt("refs/heads/{s}",.{name}); const oid=resolve(old) orelse return 1; const rc=updateRefValue(target,oid,null,false,"",0); if (rc!=0) return rc; _=updateRefValue(old,null,null,false,"",0); if (eq(head,fmt("ref: {s}",.{old}))) _=put(join(g,"HEAD"),fmt("ref: {s}\n",.{target})); return 0; }
    if (p.items.len>0) { const n=fmt("refs/heads/{s}",.{p.items[0]}); if (!force and resolve(n)!=null) return fatal("a branch with that name already exists"); const oid=resolve(if (p.items.len>1) p.items[1] else "HEAD") orelse return 128; return updateRefValue(n,oid,null,false,"branch: Created",0); }
    const current=trim(load(join(g,"HEAD")) orelse ""); for (allRefs()) |r| { if (starts(r.name,"refs/heads/")) line(fmt("{s} {s}",.{if (eq(current,fmt("ref: {s}",.{r.name}))) "*" else " ",r.name[11..]})); } return 0;
}
fn tagCommand(args: Args) u8 {
    return @import("tag.zig").run(args);
}
fn lsTree(args: Args) u8 {
    var recursive=false; var names=false; var nul=false; var target: []const u8="HEAD";
    for (args) |s| { if (eq(s,"-r")) recursive=true else if (eq(s,"--name-only")) names=true else if (eq(s,"-z")) nul=true else if (!starts(s,"-")) target=s; }
    const obj=readObject(target) orelse return 128; const tree=if (eq(obj.typ,"commit")) readObject(header(obj.data,"tree") orelse return 1) orelse return 1 else obj;
    if (recursive) { var entries: std.ArrayList(IndexEntry)=.empty; if (!readTreeEntries(target,"",&entries)) return 1; for (entries.items) |e| { out(if (names) e.path else fmt("{o} blob {s}\t{s}",.{e.mode,e.oid,e.path})); out(if (nul) "\x00" else "\n"); } return 0; }
    var off: usize=0; while (off<tree.data.len) { const sp=std.mem.indexOfScalarPos(u8,tree.data,off,' ') orelse return 1; const end=std.mem.indexOfScalarPos(u8,tree.data,sp,0) orelse return 1; if (end+21>tree.data.len) return 1; const mode=std.fmt.parseInt(u32,tree.data[off..sp],8) catch return 1; const hex=std.fmt.bytesToHex(tree.data[end+1..][0..20].*,.lower); const name=tree.data[sp+1..end]; out(if (names) name else fmt("{s}{o} {s} {s}\t{s}",.{if (mode==0o40000) "0" else "",mode,if (mode==0o40000) "tree" else if (mode==0o160000) "commit" else "blob",hex,name})); out(if (nul) "\x00" else "\n"); off=end+21; } return 0;
}
fn stripRef(value: []const u8, modifier: []const u8) []const u8 {
    if (eq(modifier,"short")) { for ([_][]const u8{"refs/heads/","refs/tags/","refs/remotes/"}) |prefix| { if (starts(value,prefix)) return value[prefix.len..]; } return value; }
    const equal=std.mem.indexOfScalar(u8,modifier,'=') orelse return value; const n=std.fmt.parseInt(i32,modifier[equal+1..],10) catch return value;
    var components: usize=1; for (value) |c| { if (c=='/') components+=1; }
    const count: usize=if (n<0) components-@min(components,@as(usize,@intCast(-n))) else @min(components,@as(usize,@intCast(n)));
    var v=value; for (0..count) |_| { if (starts(modifier,"rstrip")) { v=v[0..std.mem.lastIndexOfScalar(u8,v,'/') orelse 0]; } else { v=if (std.mem.indexOfScalar(u8,v,'/')) |p| v[p+1..] else ""; } } return v;
}
fn atomValue(ref: Ref, atom: []const u8) ?[]const u8 {
    var key=atom; var oid=ref.oid; var obj=readObject(oid) orelse return "";
    if (starts(key,"*")) { key=key[1..]; if (!eq(obj.typ,"tag")) return ""; oid=header(obj.data,"object") orelse return ""; obj=readObject(oid) orelse return ""; }
    const colon=std.mem.indexOfScalar(u8,key,':') orelse key.len; const base=key[0..colon]; const mod=if (colon<key.len) key[colon+1..] else "";
    if (eq(base,"refname")) return stripRef(ref.name,mod);
    if (eq(base,"symref")) { const data=load(join(gitdir() orelse return "",ref.name)) orelse return ""; return if (starts(data,"ref: ")) stripRef(trim(data[5..]),mod) else ""; }
    if (eq(base,"upstream") or eq(base,"push")) { if (!starts(ref.name,"refs/heads/")) return ""; const branch=ref.name[11..]; const remote=if (eq(base,"push")) configGet("remote.pushdefault") orelse configGet(fmt("branch.{s}.remote",.{branch})) orelse return "" else configGet(fmt("branch.{s}.remote",.{branch})) orelse return ""; return stripRef(fmt("refs/remotes/{s}/{s}",.{remote,branch}),mod); }
    if (eq(base,"HEAD")) { const g=gitdir() orelse return " "; return if (eq(trim(load(join(g,"HEAD")) orelse ""),fmt("ref: {s}",.{ref.name}))) "*" else " "; }
    if (eq(base,"objecttype")) return obj.typ;
    if (eq(base,"deltabase")) return zeroOid;
    if (eq(base,"objectsize")) { if (eq(mod,"disk")) { const data=load(join(gitdir() orelse return "",fmt("objects/{s}/{s}",.{oid[0..2],oid[2..]}))) orelse return ""; return fmt("{d}",.{data.len}); } return fmt("{d}",.{obj.data.len}); }
    if (eq(base,"objectname") or eq(base,"tree") or eq(base,"object") or eq(base,"parent")) { const value=if (eq(base,"objectname")) oid else header(obj.data,base) orelse ""; if (starts(mod,"short") and value.len>=40) { const len=if (starts(mod,"short=")) @max(4,std.fmt.parseInt(usize,mod[6..],10) catch 7) else 7; return value[0..@min(len,40)]; } return value; }
    if (eq(base,"numparent")) { if (!eq(obj.typ,"commit")) return ""; var n: usize=0; var it=std.mem.splitScalar(u8,obj.data,'\n'); while (it.next()) |l| { if (starts(l,"parent ")) n+=1; } return fmt("{d}",.{n}); }
    if (eq(base,"raw")) return if (eq(mod,"size")) fmt("{d}",.{obj.data.len}) else obj.data;
    if (eq(base,"type") or eq(base,"tag")) return header(obj.data,base) orelse "";
    if (eq(base,"subject") or eq(base,"body") or eq(base,"contents")) { const start=std.mem.indexOf(u8,obj.data,"\n\n") orelse return ""; const contents=obj.data[start+2..]; const end=std.mem.indexOfScalar(u8,contents,'\n') orelse contents.len;
        if (eq(mod,"size")) return fmt("{d}",.{contents.len}); if (eq(mod,"signature")) return ""; if (eq(base,"body") or eq(mod,"body")) return if (end<contents.len) std.mem.trimStart(u8,contents[end+1..],"\n") else "";
        if (eq(base,"subject") or eq(mod,"subject")) { const subject=contents[0..end]; return if (eq(mod,"sanitize")) std.mem.replaceOwned(u8,a,subject," ","-") catch unreachable else subject; } return contents;
    }
    for ([_][]const u8{"author","committer","tagger","creator"}) |who| { if (starts(base,who)) {
        const identity=header(obj.data,if (eq(who,"creator")) (if (eq(obj.typ,"tag")) "tagger" else "committer") else who) orelse return "";
        const suffix=base[who.len..]; if (suffix.len==0) return identity;
        const lt=std.mem.indexOfScalar(u8,identity,'<') orelse return ""; const gt=std.mem.indexOfScalar(u8,identity,'>') orelse return "";
        var name=trim(identity[0..lt]); var email=identity[lt+1..gt];
        if (std.mem.indexOf(u8,mod,"mailmap")!=null) { if (load(".mailmap")) |map| { var it=std.mem.splitScalar(u8,map,'\n'); while (it.next()) |l| { if (std.mem.indexOf(u8,l,fmt("<{s}>",.{email}))) |_| { const ml=std.mem.indexOfScalar(u8,l,'<') orelse continue; const mg=std.mem.indexOfScalar(u8,l,'>') orelse continue; name=trim(l[0..ml]); email=l[ml+1..mg]; break; } } } }
        if (eq(suffix,"name")) return name;
        if (eq(suffix,"email")) { if (std.mem.indexOf(u8,mod,"localpart")!=null) return email[0..std.mem.indexOfScalar(u8,email,'@') orelse email.len]; if (std.mem.indexOf(u8,mod,"trim")!=null) return email; return fmt("<{s}>",.{email}); }
        if (eq(suffix,"date")) { if (eq(mod,"raw")) return trim(identity[gt+1..]); if (eq(mod,"unix")) { const date=trim(identity[gt+1..]); return date[0..std.mem.indexOfScalar(u8,date,' ') orelse date.len]; } return formatDate(trim(identity[gt+1..]),mod); }
    } }
    if (starts(base,"color")) return "";
    return null;
}
fn formatDate(date: []const u8, modifier: []const u8) []const u8 {
    var words=std.mem.tokenizeScalar(u8,date,' '); const timestamp=std.fmt.parseInt(i64,words.next() orelse return "",10) catch return ""; const zone=words.next() orelse "+0000";
    const offset=if (zone.len==5) (std.fmt.parseInt(i64,zone[1..3],10) catch 0)*3600+(std.fmt.parseInt(i64,zone[3..5],10) catch 0)*60 else 0;
    var seconds: i64=timestamp+(if (zone.len>0 and zone[0]=='-') -offset else offset); const tm=gmtime(&seconds) orelse return "";
    var buffer: [128]u8=undefined; const pattern: [:0]const u8=if (eq(modifier,"short")) "%Y-%m-%d" else if (eq(modifier,"iso8601") or eq(modifier,"iso")) "%Y-%m-%d %H:%M:%S" else "%a %b %e %H:%M:%S %Y";
    const len=strftime(&buffer,buffer.len,pattern,tm); const value=std.mem.replaceOwned(u8,a,buffer[0..len],"  "," ") catch unreachable; return if (eq(modifier,"short")) value else fmt("{s} {s}",.{value,zone});
}
fn forEachRef(args: Args) u8 {
    var format: []const u8="%(objectname) %(objecttype)\t%(refname)"; var patterns: std.ArrayList([]const u8)=.empty; var max: usize=std.math.maxInt(usize); var quote: ?u8=null; var reverse=false;
    for (args) |s| { if (starts(s,"--format=")) format=s[9..] else if (starts(s,"--count=")) max=std.fmt.parseInt(usize,s[8..],10) catch return 129 else if (eq(s,"--shell") or eq(s,"--python") or eq(s,"--perl")) quote='\'' else if (eq(s,"--tcl")) quote='"' else if (starts(s,"--sort=-")) reverse=true else if (!starts(s,"-")) patterns.append(a,s) catch unreachable; }
    const refs=allRefs(); if (reverse) std.mem.reverse(Ref,refs); var count: usize=0;
    for (refs) |ref| { if (count>=max) break; var matched=patterns.items.len==0; for (patterns.items) |p| { if (eq(ref.name,p) or starts(ref.name,fmt("{s}/",.{p})) or fnmatch(z(p),z(ref.name),0)==0) matched=true; } if (!matched) continue;
        var b: std.ArrayList(u8)=.empty; var off: usize=0;
        while (off<format.len) { if (starts(format[off..],"%(")) { const end=std.mem.indexOfScalarPos(u8,format,off+2,')') orelse return fatal("malformed format string"); const atom=format[off+2..end]; const value=atomValue(ref,atom) orelse return fatal(fmt("unknown field name: {s}",.{atom})); if (quote) |q| b.append(a,q) catch unreachable; b.appendSlice(a,value) catch unreachable; if (quote) |q| b.append(a,q) catch unreachable; off=end+1; }
            else if (format[off]=='%' and off+2<format.len) { const byte=std.fmt.parseInt(u8,format[off+1..off+3],16) catch { b.append(a,format[off]) catch unreachable; off+=1; continue; }; b.append(a,byte) catch unreachable; off+=3; }
            else { b.append(a,format[off]) catch unreachable; off+=1; }
        } line(b.items); count+=1;
    } return 0;
}
fn updateIndex(args: Args) u8 {
    var entries: std.ArrayList(IndexEntry)=.empty; entries.appendSlice(a,readIndex()) catch unreachable;
    var removing=false; var input=false; var info=false; var nul=false; var chmod: ?bool=null; var i: usize=0;
    while (i<args.len) : (i+=1) { const s=args[i];
        if (eq(s,"--force-remove") or eq(s,"--remove")) removing=true else if (eq(s,"--stdin")) input=true else if (eq(s,"--index-info")) { input=true; info=true; } else if (eq(s,"-z")) nul=true
        else if (starts(s,"--chmod=")) chmod=eq(s[8..],"+x")
        else if (eq(s,"--cacheinfo")) { i+=1; if (i==args.len) return 129; var mode: []const u8=undefined; var oid: []const u8=undefined; var path: []const u8=undefined;
            if (std.mem.indexOfScalar(u8,args[i],',')) |_| { var parts=std.mem.splitScalar(u8,args[i],','); mode=parts.next() orelse return 129; oid=parts.next() orelse return 129; path=parts.next() orelse return 129; }
            else { if (i+2>=args.len) return 129; mode=args[i]; oid=args[i+1]; path=args[i+2]; i+=2; }
            var found=false; const m=std.fmt.parseInt(u32,mode,8) catch return 129; for (entries.items) |*e| { if (eq(e.path,path)) { e.oid=oid; e.mode=m; found=true; } } if (!found) entries.append(a,.{.path=path,.oid=oid,.mode=m}) catch unreachable;
        } else if (!starts(s,"-")) {
            if (removing) { var n: usize=0; while (n<entries.items.len) { if (eq(entries.items[n].path,s)) _=entries.orderedRemove(n) else n+=1; } }
            else if (chmod) |executable| { for (entries.items) |*e| { if (eq(e.path,s)) e.mode=if (executable) 0o100755 else 0o100644; } }
            else if (!stageFile(&entries,s)) return 1;
        }
    }
    if (input) { while (inputRecord(if (nul) 0 else '\n')) |l| { if (info) { const tab=std.mem.indexOfScalar(u8,l,'\t') orelse return 128; const path=l[tab+1..]; var words=std.mem.tokenizeScalar(u8,l[0..tab],' '); const mode=std.fmt.parseInt(u32,words.next() orelse return 128,8) catch return 128; const oid=words.next() orelse return 128; const stage=std.fmt.parseInt(u16,words.next() orelse "0",10) catch return 128; var n: usize=0; while (n<entries.items.len) { if (eq(entries.items[n].path,path) and (mode==0 or entries.items[n].stage==stage)) _=entries.orderedRemove(n) else n+=1; } if (mode!=0) entries.append(a,.{.path=path,.oid=oid,.mode=mode,.stage=stage}) catch unreachable; } else if (!stageFile(&entries,l)) return 1; } }
    return if (writeIndex(entries.items)) 0 else 1;
}
fn mkTree(args: Args) u8 {
    var nul=false; for (args) |s| { if (eq(s,"-z")) nul=true; }
    const TreeEnt=struct { name: []const u8, oid: []const u8, mode: []const u8 }; var entries: std.ArrayList(TreeEnt)=.empty;
    while (inputRecord(if (nul) 0 else '\n')) |l| { if (l.len==0) continue; const tab=std.mem.indexOfScalar(u8,l,'\t') orelse return fatal("input format error"); var words=std.mem.tokenizeScalar(u8,l[0..tab],' '); const mode=words.next() orelse return 128; _=words.next() orelse return 128; const oid=words.next() orelse return 128; if (oid.len!=40) return 128; entries.append(a,.{.name=l[tab+1..],.oid=oid,.mode=mode}) catch unreachable; }
    std.mem.sort(TreeEnt,entries.items,{},struct { fn less(_: void,x: TreeEnt,y: TreeEnt) bool { return std.mem.lessThan(u8,x.name,y.name); } }.less);
    var b: std.ArrayList(u8)=.empty; for (entries.items) |e| { const mode=std.fmt.parseInt(u32,e.mode,8) catch return 128; b.appendSlice(a,fmt("{o} {s}\x00",.{mode,e.name})) catch unreachable; b.appendSlice(a,&oidBytes(e.oid)) catch unreachable; } line(objectHash("tree",b.items,true) orelse return 1); return 0;
}
fn grepCommand(args: Args) u8 {
    return @import("grep.zig").run(args);
}
fn collectFiles(path: []const u8, entries: *std.ArrayList(IndexEntry)) void {
    if (std.c.opendir(z(path))) |dir| { defer _=std.c.closedir(dir); while (std.c.readdir(dir)) |e| { const name=std.mem.sliceTo(&e.name,0); if (eq(name,".") or eq(name,"..") or eq(name,".git")) continue; collectFiles(if (eq(path,".")) name else join(path,name),entries); } }
    else entries.append(a,.{.path=a.dupe(u8,path) catch unreachable,.oid=zeroOid}) catch unreachable;
}
fn entryFor(entries: []const IndexEntry, path: []const u8) ?IndexEntry { for (entries) |e| { if (eq(e.path,path)) return e; } return null; }
const Change=struct { path: []const u8, old: ?IndexEntry, new: ?IndexEntry, before: []const u8, after: []const u8 };
fn splitLines(data: []const u8) [][]const u8 {
    return difftext.split(data);
}
fn rangeText(start: usize, count: usize) []const u8 { return if (count==1) fmt("{d}",.{start}) else fmt("{d},{d}",.{if (count==0 and start>0) start-1 else start,count}); }
fn printPatch(change: Change, lines: []const difftext.Line, context: usize) void {
    const p=change.path; const oldmode=if (change.old) |e| e.mode else 0; const newmode=if (change.new) |e| e.mode else 0;
    line(fmt("diff --git a/{s} b/{s}",.{p,p}));
    if (oldmode==0) line(fmt("new file mode {o}",.{newmode})) else if (newmode==0) line(fmt("deleted file mode {o}",.{oldmode})) else if (oldmode!=newmode) { line(fmt("old mode {o}",.{oldmode})); line(fmt("new mode {o}",.{newmode})); }
    if (eq(change.before,change.after)) return;
    line(fmt("index {s}..{s}{s}",.{if (change.old) |e| e.oid[0..7] else "0000000",if (change.new) |e| e.oid[0..7] else "0000000",if (oldmode==newmode and oldmode!=0) fmt(" {o}",.{oldmode}) else ""}));
    if (std.mem.indexOfScalar(u8,change.before,0)!=null or std.mem.indexOfScalar(u8,change.after,0)!=null) { line(fmt("Binary files {s} and {s} differ",.{if (oldmode==0) "/dev/null" else fmt("a/{s}",.{p}),if (newmode==0) "/dev/null" else fmt("b/{s}",.{p})})); return; }
    line(fmt("--- {s}",.{if (oldmode==0) "/dev/null" else fmt("a/{s}",.{p})})); line(fmt("+++ {s}",.{if (newmode==0) "/dev/null" else fmt("b/{s}",.{p})}));
    var off: usize=0; var oldline: usize=1; var newline: usize=1;
    while (off<lines.len) { var change_at=off; while (change_at<lines.len and (lines[change_at].kind==' ' or lines[change_at].ignored)) : (change_at+=1) {} if (change_at==lines.len) break;
        const start=@max(off,change_at-@min(change_at,context)); while (off<start) : (off+=1) { if (lines[off].kind!='+') oldline+=1; if (lines[off].kind!='-') newline+=1; }
        var end=change_at+1; var last=change_at;
        while (end<lines.len) : (end+=1) { if (lines[end].kind!=' ' and !lines[end].ignored) last=end; if (end-last>context*2) break; }
        end=@min(lines.len,last+context+1); var oldcount: usize=0; var newcount: usize=0;
        for (lines[start..end]) |l| { if (l.kind!='+') oldcount+=1; if (l.kind!='-') newcount+=1; }
        line(fmt("@@ -{s} +{s} @@",.{rangeText(oldline,oldcount),rangeText(newline,newcount)}));
        for (lines[start..end]) |l| { out(&.{l.kind}); out(l.text); if (l.text.len==0 or l.text[l.text.len-1]!='\n') out("\n\\ No newline at end of file\n"); }
        oldline+=oldcount; newline+=newcount; off=end;
    }
}
fn diffCommand(args: Args, command: []const u8) u8 {
    var cached=false; var names=false; var namestatus=false; var raw=false; var numstat=false; var check=false; var exitcode=false; var quiet=false; var noindex=false; var context: usize=3;
    var options=difftext.Options{}; var reverse=false; var silent=false;
    const rules=@import("whitespace.zig").Rules.parse(configGet("core.whitespace") orelse "");
    if (rules.tab and rules.indent) return fatal("cannot enforce both tab-in-indent and indent-with-non-tab");
    var revisions: std.ArrayList([]const u8)=.empty; var paths: std.ArrayList([]const u8)=.empty; var after=false; var orderfile: ?[]const u8=configGet("diff.orderfile"); var output: ?[]const u8=null;
    var i: usize=0; while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"--")) after=true else if (after) paths.append(a,s) catch unreachable
        else if (eq(s,"--cached") or eq(s,"--staged")) cached=true else if (eq(s,"--name-only")) names=true else if (eq(s,"--name-status")) namestatus=true else if (eq(s,"--raw")) raw=true else if (eq(s,"--numstat")) numstat=true else if (eq(s,"--check")) check=true else if (eq(s,"--exit-code")) exitcode=true else if (eq(s,"--quiet")) { quiet=true; exitcode=true; } else if (eq(s,"--no-index")) noindex=true
        else if (eq(s,"-O") or eq(s,"--output")) { i+=1; if (i==args.len) return 129; if (eq(s,"-O")) orderfile=args[i] else output=args[i]; }
        else if (starts(s,"-O")) orderfile=s[2..] else if (starts(s,"-U")) context=std.fmt.parseInt(usize,s[2..],10) catch 3
        else if (eq(s,"-w") or eq(s,"--ignore-all-space")) options.space=.all
        else if (eq(s,"-b") or eq(s,"--ignore-space-change")) { if (options.space!=.all) options.space=.change; }
        else if (eq(s,"--ignore-space-at-eol")) { if (options.space==.exact) options.space=.eol; }
        else if (eq(s,"--ignore-cr-at-eol")) options.cr=true
        else if (eq(s,"--ignore-blank-lines")) options.blank=true
        else if (starts(s,"-I")) { if (s.len>2) options.ignore=s[2..] else { i+=1; if (i==args.len) return 129; options.ignore=args[i]; } }
        else if (eq(s,"-R")) reverse=true else if (eq(s,"-s") or eq(s,"--no-patch")) silent=true
        else if (!starts(s,"-")) { if (std.mem.indexOf(u8,s,"..")) |p| { revisions.append(a,s[0..p]) catch unreachable; revisions.append(a,s[p+2..]) catch unreachable; } else if (resolve(s)!=null) revisions.append(a,s) catch unreachable else paths.append(a,s) catch unreachable; }
    }
    const order=if (orderfile) |f| load(f) orelse return fatal(fmt("failed to read orderfile '{s}'",.{f})) else "";
    var left: std.ArrayList(IndexEntry)=.empty; var right: std.ArrayList(IndexEntry)=.empty; var worktree=!cached;
    if (eq(command,"diff-tree")) worktree=false;
    if (revisions.items.len>=2) { if (!readTreeEntries(revisions.items[0],"",&left) or !readTreeEntries(revisions.items[1],"",&right)) return 128; worktree=false; }
    else if (revisions.items.len==1) { if (!readTreeEntries(revisions.items[0],"",&left)) return 128; right.appendSlice(a,readIndex()) catch unreachable; }
    else if (cached) { if (resolve("HEAD")) |id| { if (!readTreeEntries(id,"",&left)) return 128; } right.appendSlice(a,readIndex()) catch unreachable; }
    else { left.appendSlice(a,readIndex()) catch unreachable; right.appendSlice(a,left.items) catch unreachable; }
    if (noindex) return 1;
    if (worktree) { var n: usize=0; while (n<right.items.len) { const e=&right.items[n]; if (load(e.path)) |data| { e.oid=objectHash("blob",filtered(data,e.path,false),false) orelse return 1; n+=1; } else _=right.orderedRemove(n); } }
    var unionpaths: std.ArrayList([]const u8)=.empty; for (left.items) |e| unionpaths.append(a,e.path) catch unreachable; for (right.items) |e| { if (entryFor(left.items,e.path)==null) unionpaths.append(a,e.path) catch unreachable; }
    std.mem.sort([]const u8,unionpaths.items,order,struct { fn rank(data: []const u8,p: []const u8) usize { var it=std.mem.splitScalar(u8,data,'\n'); var n: usize=0; while (it.next()) |pat| : (n+=1) { if (pat.len>0 and fnmatch(z(pat),z(p),0)==0) return n; } return n; } fn less(data: []const u8,x: []const u8,y: []const u8) bool { const rx=rank(data,x); const ry=rank(data,y); return if (rx==ry) std.mem.lessThan(u8,x,y) else rx<ry; } }.less);
    var changed=false; var badspace=false; const saved=if (output!=null) dup(1) else -1;
    defer { if (saved>=0) { _=dup2(saved,1); _=close(saved); } }
    if (output) |p| { const f=fopen(z(p),"wb") orelse return 1; _=dup2(fileno(f),1); _=fclose(f); }
    for (unionpaths.items) |p| { var matched=paths.items.len==0; for (paths.items) |pat| { if (eq(p,pat) or starts(p,fmt("{s}/",.{pat})) or fnmatch(z(pat),z(p),0)==0) matched=true; } if (!matched) continue;
        var old=entryFor(left.items,p); var new=entryFor(right.items,p); if (old!=null and new!=null and eq(old.?.oid,new.?.oid) and old.?.mode==new.?.mode) continue;
        var before=if (old) |e| (readObject(e.oid) orelse return 1).data else ""; var afterdata=if (new) |e| (if (worktree) load(e.path) orelse "" else (readObject(e.oid) orelse return 1).data) else "";
        if (reverse) { std.mem.swap(?IndexEntry,&old,&new); std.mem.swap([]const u8,&before,&afterdata); }
        const lines=difftext.lines(before,afterdata,options);
        if (old!=null and new!=null and old.?.mode==new.?.mode and !difftext.changed(lines)) continue;
        changed=true; if (quiet or silent) continue;
        const status=if (old==null) "A" else if (new==null) "D" else "M";
        if (names) line(p) else if (namestatus) line(fmt("{s}\t{s}",.{status,p})) else if (raw) line(fmt(":{s}{o} {s}{o} {s} {s} {s}\t{s}",.{if (old==null) "00000" else "",if (old) |e| e.mode else 0,if (new==null) "00000" else "",if (new) |e| e.mode else 0,if (old) |e| e.oid[0..7] else "0000000",if (new) |e| e.oid[0..7] else "0000000",status,p}))
        else if (numstat) { var added: usize=0; var deleted: usize=0; for (lines) |l| { if (l.kind=='+') added+=1; if (l.kind=='-') deleted+=1; } line(fmt("{d}\t{d}\t{s}",.{added,deleted,p})); }
        else if (check) { var n: usize=0; var eof_added: ?usize=null;
            for (lines) |l| { if (l.kind!='-') n+=1; if (l.kind==' ' and std.mem.trim(u8,l.text," \t\r\n").len>0) eof_added=null;
                if (l.kind=='+') {
                    if (std.mem.trim(u8,l.text," \t\r\n").len==0) { if (eof_added==null) eof_added=n; } else eof_added=null;
                    if (rules.errorMessage(l.text)) |message| { line(fmt("{s}:{d}: {s}",.{p,n,message})); out("+"); out(l.text); badspace=true; }
                    if (rules.incomplete and l.text.len>0 and l.text[l.text.len-1]!='\n') { line(fmt("{s}:{d}: no newline at the end of file.",.{p,n})); badspace=true; }
                }
            }
            if (rules.eof and eof_added!=null) { line(fmt("{s}:{d}: new blank line at EOF.",.{p,eof_added.?})); badspace=true; }
        }
        else printPatch(.{.path=p,.old=old,.new=new,.before=before,.after=afterdata},lines,context);
    }
    return if (badspace) 2 else if (exitcode and changed) 1 else 0;
}
// Minimal independent Zig test helper: only boolean environment parsing is supported.
// Unknown helper commands fail, rather than pretending that prerequisites succeeded.
const ImportStream=struct {
    byte: ?u8=null, pending: ?[]const u8=null,
    fn nextByte(self: *ImportStream) ?u8 { if (self.byte) |c| { self.byte=null; return c; } var b: [1]u8=undefined; return if (read(0,&b,1)==1) b[0] else null; }
    fn next(self: *ImportStream) ?[]const u8 { if (self.pending) |l| { self.pending=null; return l; } var b: std.ArrayList(u8)=.empty; while (self.nextByte()) |c| { if (c=='\n') return b.toOwnedSlice(a) catch unreachable; b.append(a,c) catch unreachable; } return if (b.items.len>0) b.toOwnedSlice(a) catch unreachable else null; }
    fn data(self: *ImportStream, command: []const u8) ?[]const u8 {
        if (!starts(command,"data ")) return null;
        if (starts(command,"data <<")) { const terminator=command[7..]; var b: std.ArrayList(u8)=.empty; while (self.next()) |l| { if (eq(l,terminator)) return b.toOwnedSlice(a) catch unreachable; b.appendSlice(a,l) catch unreachable; b.append(a,'\n') catch unreachable; } return null; }
        const n=std.fmt.parseInt(usize,command[5..],10) catch return null; if (n>1024*1024*1024) return null; const b=a.alloc(u8,n) catch unreachable; var off: usize=0;
        if (self.byte) |c| { if (n>0) { b[0]=c; off=1; self.byte=null; } }
        while (off<n) { const got=read(0,b[off..].ptr,n-off); if (got<=0) return null; off+=@intCast(got); }
        if (self.nextByte()) |c| { if (c!='\n') self.byte=c; } return b;
    }
};
fn importResolve(name: []const u8, marks: *std.StringHashMap([]const u8)) ?[]const u8 { return if (starts(name,":")) marks.get(name[1..]) else resolve(name); }
fn importPath(path: []const u8) ?[]const u8 {
    if (!starts(path,"\"")) return path; if (path.len<2 or path[path.len-1]!='"') return null;
    var b: std.ArrayList(u8)=.empty; var i: usize=1; while (i<path.len-1) : (i+=1) { var c=path[i]; if (c=='\\') { i+=1; if (i>=path.len-1) return null; c=path[i]; if (c>='0' and c<='7') { if (i+2>=path.len-1) return null; c=std.fmt.parseInt(u8,path[i..i+3],8) catch return null; i+=2; } else c=switch (c) { 'n'=>'\n', 't'=>'\t', 'r'=>'\r', '\\'=>'\\', '"'=>'"', else=>return null }; } b.append(a,c) catch unreachable; } return b.toOwnedSlice(a) catch unreachable;
}
fn sortIndex(entries: []IndexEntry) void { std.mem.sort(IndexEntry,entries,{},struct { fn less(_: void,x: IndexEntry,y: IndexEntry) bool { return std.mem.lessThan(u8,x.path,y.path); } }.less); }
fn importSetFile(entries: *std.ArrayList(IndexEntry), path: []const u8, oid: []const u8, mode: u32) void {
    var i: usize=0; while (i<entries.items.len) { const p=entries.items[i].path; if (eq(p,path) or starts(p,fmt("{s}/",.{path})) or starts(path,fmt("{s}/",.{p}))) _=entries.orderedRemove(i) else i+=1; }
    entries.append(a,.{.path=path,.oid=oid,.mode=mode}) catch unreachable;
}
fn fastImport(args: Args) u8 {
    var stream: ImportStream=.{}; var marks=std.StringHashMap([]const u8).init(a); var imported: std.ArrayList(Object)=.empty; var imported_seen=std.StringHashMap(void).init(a); var exportfile: ?[]const u8=null;
    var unsafe=false; var export_cli=false; var import_cli=false; var feature_imported=false; var started=false; var require_done=false; var done=false; var query_fd: c_int=1;
    for (args) |s| { if (starts(s,"--cat-blob-fd=")) { query_fd=std.fmt.parseInt(c_int,s[14..],10) catch return 129; if (query_fd<0) return 129; const fd=dup(query_fd); if (fd<0) return fatal("invalid cat-blob descriptor"); _=close(fd); } }
    for (args) |s| { if (eq(s,"--allow-unsafe-features")) unsafe=true; if (starts(s,"--export-marks=")) export_cli=true; if (starts(s,"--import-marks=" ) or starts(s,"--import-marks-if-exists=")) import_cli=true; }
    for (args) |s| { if (starts(s,"--export-marks=")) exportfile=s[15..] else if (starts(s,"--import-marks=") or starts(s,"--import-marks-if-exists=")) { const pos=std.mem.indexOfScalar(u8,s,'=').?; if (load(s[pos+1..])) |data| { var lines=std.mem.splitScalar(u8,data,'\n'); while (lines.next()) |l| { const space=std.mem.indexOfScalar(u8,l,' ') orelse continue; if (l.len>space+1 and starts(l,":")) marks.put(l[1..space],l[space+1..]) catch unreachable; } } else if (starts(s,"--import-marks=")) return fatal("cannot read marks"); } }
    while (stream.next()) |command| {
        if (command.len==0 or command[0]=='#') continue;
        if (eq(command,"done")) { done=true; break; }
        if (eq(command,"blob")) {
            started=true;
            var mark: ?[]const u8=null; var data: ?[]const u8=null;
            while (stream.next()) |l| { if (starts(l,"mark :")) mark=l[6..] else if (starts(l,"original-oid ")) {} else if (starts(l,"data ")) { data=stream.data(l) orelse return fatal("invalid blob data"); break; } else return fatal("expected blob data"); }
            const bytes=data orelse return fatal("missing blob data"); const oid=objectHash("blob",bytes,true) orelse return 1; if (mark) |m| marks.put(m,oid) catch unreachable;
            if (!imported_seen.contains(oid)) { imported_seen.put(oid,{}) catch unreachable; imported.append(a,.{.typ="blob",.data=bytes}) catch unreachable; }
        } else if (starts(command,"commit ")) {
            started=true;
            const ref=command[7..]; var mark: ?[]const u8=null; var author: ?[]const u8=null; var committer: ?[]const u8=null; var message: ?[]const u8=null; var parent=resolve(ref); var merges: std.ArrayList([]const u8)=.empty; var entries: std.ArrayList(IndexEntry)=.empty; var initialized=false;
            while (stream.next()) |l| {
                if (l.len==0 or l[0]=='#') continue;
                if (starts(l,"mark :")) mark=l[6..] else if (starts(l,"author ")) author=l[7..] else if (starts(l,"committer ")) committer=l[10..] else if (starts(l,"encoding ") or starts(l,"original-oid ")) {}
                else if (starts(l,"data ") and message==null) message=stream.data(l) orelse return fatal("invalid commit data")
                else if (starts(l,"from ")) { const name=l[5..]; if (eq(name,zeroOid)) parent=null else parent=importResolve(name,&marks) orelse return fatal(fmt("invalid ref {s}",.{name})); }
                else if (starts(l,"merge ")) { merges.append(a,importResolve(l[6..],&marks) orelse return fatal("invalid merge parent")) catch unreachable; }
                else if (starts(l,"ls ")) { const path=importPath(l[3..]) orelse return 128; if (!initialized) { if (parent) |p| { if (!readTreeEntries(p,"",&entries)) return 128; } initialized=true; } emit(query_fd,if (entryFor(entries.items,path)) |e| fmt("{o} blob {s}\t{s}\n",.{e.mode,e.oid,path}) else fmt("missing {s}\n",.{path})); }
                else if (starts(l,"N ")) { if (!initialized) { if (parent) |p| { if (!readTreeEntries(p,"",&entries)) return 128; } initialized=true; }
                    const space=std.mem.indexOfScalarPos(u8,l,2,' ') orelse return 128; const dataref=l[2..space]; const target=importResolve(l[space+1..],&marks) orelse return 128;
                    if (eq(dataref,"0") or eq(dataref,zeroOid)) { var n: usize=0; while (n<entries.items.len) { if (eq(entries.items[n].path,target)) _=entries.orderedRemove(n) else n+=1; } }
                    else { const oid=if (eq(dataref,"inline")) blk: { const bytes=stream.data(stream.next() orelse return 128) orelse return 128; break :blk objectHash("blob",bytes,true) orelse return 1; } else importResolve(dataref,&marks) orelse return 128; importSetFile(&entries,target,oid,0o100644); }
                }
                else if (starts(l,"M ") or starts(l,"D ") or eq(l,"deleteall") or starts(l,"C ") or starts(l,"R ")) {
                    if (!initialized) { if (parent) |p| { if (!readTreeEntries(p,"",&entries)) return fatal("invalid parent tree"); } initialized=true; }
                    if (eq(l,"deleteall")) { entries.clearRetainingCapacity(); continue; }
                    if (starts(l,"D ")) { const path=importPath(l[2..]) orelse return fatal("invalid path"); var n: usize=0; while (n<entries.items.len) { if (eq(entries.items[n].path,path) or starts(entries.items[n].path,fmt("{s}/",.{path}))) _=entries.orderedRemove(n) else n+=1; } continue; }
                    if (starts(l,"C ") or starts(l,"R ")) { const space=std.mem.indexOfScalarPos(u8,l,2,' ') orelse return fatal("invalid copy command"); const source=importPath(l[2..space]) orelse return 128; const dest=importPath(l[space+1..]) orelse return 128; const old=entryFor(entries.items,source) orelse return fatal("copy source not found"); if (l[0]=='R') { var n: usize=0; while (n<entries.items.len) { if (eq(entries.items[n].path,source)) { _=entries.orderedRemove(n); break; } n+=1; } } importSetFile(&entries,dest,old.oid,old.mode); continue; }
                    const space=std.mem.indexOfScalarPos(u8,l,2,' ') orelse return fatal("invalid filemodify"); const second=std.mem.indexOfScalarPos(u8,l,space+1,' ') orelse return fatal("invalid filemodify"); var mode=std.fmt.parseInt(u32,l[2..space],8) catch return fatal("invalid mode"); if (mode==0o644 or mode==0o755) mode|=0o100000;
                    const name=l[space+1..second]; const path=importPath(l[second+1..]) orelse return fatal("invalid path"); var oid: []const u8=undefined;
                    if (eq(name,"inline")) { const data=stream.data(stream.next() orelse return 128) orelse return fatal("invalid inline data"); oid=objectHash("blob",data,true) orelse return 1; if (!imported_seen.contains(oid)) { imported_seen.put(oid,{}) catch unreachable; imported.append(a,.{.typ="blob",.data=data}) catch unreachable; } }
                    else oid=importResolve(name,&marks) orelse return fatal("invalid dataref");
                    if (mode==0o40000) { var subtree: std.ArrayList(IndexEntry)=.empty; if (!readTreeEntries(oid,fmt("{s}/",.{path}),&subtree)) return 128; for (subtree.items) |e| importSetFile(&entries,e.path,e.oid,e.mode); }
                    else importSetFile(&entries,path,oid,mode);
                } else { stream.pending=l; break; }
            }
            if (!initialized) { if (parent) |p| { if (!readTreeEntries(p,"",&entries)) return 1; } }
            sortIndex(entries.items); const tree=treeFromIndex(entries.items,"") orelse return 1;
            var data: std.ArrayList(u8)=.empty; data.appendSlice(a,fmt("tree {s}\n",.{tree})) catch unreachable; if (parent) |p| data.appendSlice(a,fmt("parent {s}\n",.{p})) catch unreachable; for (merges.items) |p| data.appendSlice(a,fmt("parent {s}\n",.{p})) catch unreachable;
            const who=committer orelse return fatal("missing committer"); data.appendSlice(a,fmt("author {s}\ncommitter {s}\n\n{s}",.{author orelse who,who,message orelse return fatal("missing commit message")})) catch unreachable;
            const oid=objectHash("commit",data.items,true) orelse return 1; if (mark) |m| marks.put(m,oid) catch unreachable; const rc=updateRefValue(ref,oid,null,false,"fast-import",0); if (rc!=0) return rc;
            var seen=std.StringHashMap(void).init(a); var graph: std.ArrayList(NamedObject)=.empty; if (!collectObjectGraph(oid,"",false,&seen,&graph,0)) return 1;
            if (!imported_seen.contains(oid)) { imported_seen.put(oid,{}) catch unreachable; imported.append(a,.{.typ="commit",.data=data.items}) catch unreachable; }
            var treegraph: std.ArrayList(NamedObject)=.empty; if (!collectObjectGraph(tree,"",true,&seen,&treegraph,0)) return 1; for (treegraph.items) |named| { if (!imported_seen.contains(named.oid)) { imported_seen.put(named.oid,{}) catch unreachable; imported.append(a,named.obj) catch unreachable; } }
        } else if (starts(command,"reset ")) {
            const ref=command[6..]; var oid: ?[]const u8=null; if (stream.next()) |l| { if (starts(l,"from ")) oid=importResolve(l[5..],&marks) orelse return fatal("invalid reset") else if (l.len>0) stream.pending=l; }
            const rc=updateRefValue(ref,oid,null,false,"fast-import",0); if (rc!=0) return rc;
        } else if (starts(command,"tag ")) {
            const name=command[4..]; var target: ?[]const u8=null; var tagger: ?[]const u8=null; var message: ?[]const u8=null; var mark: ?[]const u8=null;
            while (stream.next()) |l| { if (starts(l,"from ")) target=importResolve(l[5..],&marks) orelse return 128 else if (starts(l,"tagger ")) tagger=l[7..] else if (starts(l,"mark :")) mark=l[6..] else if (starts(l,"data ")) { message=stream.data(l) orelse return 128; break; } else if (starts(l,"original-oid ")) {} else return fatal("invalid tag command"); }
            const id=target orelse return 128; const obj=readObject(id) orelse return 128; const bytes=fmt("object {s}\ntype {s}\ntag {s}\n{s}\n{s}",.{id,obj.typ,name,if (tagger) |t| fmt("tagger {s}\n",.{t}) else "",message orelse ""}); const oid=objectHash("tag",bytes,true) orelse return 1; if (mark) |m| marks.put(m,oid) catch unreachable; if (updateRefValue(fmt("refs/tags/{s}",.{name}),oid,null,false,"fast-import",0)!=0) return 1; imported.append(a,.{.typ="tag",.data=bytes}) catch unreachable;
        } else if (eq(command,"alias")) { var mark: ?[]const u8=null; var id: ?[]const u8=null; while (stream.next()) |l| { if (starts(l,"mark :")) mark=l[6..] else if (starts(l,"to ")) { id=importResolve(l[3..],&marks) orelse return 128; break; } else if (l.len==0) continue else return fatal("invalid alias"); } marks.put(mark orelse return 128,id orelse return 128) catch unreachable; }
        else if (eq(command,"checkpoint")) {} else if (starts(command,"progress ")) line(command)
        else if (starts(command,"get-mark :")) { emit(query_fd,fmt("{s}\n",.{marks.get(command[10..]) orelse return fatal("unknown mark")})); }
        else if (starts(command,"cat-blob ")) { const oid=importResolve(command[9..],&marks) orelse return 128; const obj=readObject(oid) orelse { emit(query_fd,fmt("{s} missing\n",.{oid})); continue; }; emit(query_fd,fmt("{s} {s} {d}\n",.{oid,obj.typ,obj.data.len})); emit(query_fd,obj.data); emit(query_fd,"\n"); }
        else if (starts(command,"feature ") or starts(command,"option ")) { const feature=command[(std.mem.indexOfScalar(u8,command,' ').?)+1..]; if (started) return fatal("feature commands must precede data");
            if (starts(feature,"export-marks=") or starts(feature,"import-marks=") or starts(feature,"import-marks-if-exists=")) {
                if (!unsafe) return fatal("marks feature forbidden in input without --allow-unsafe-features");
                if (starts(feature,"export-marks=")) { if (!export_cli) exportfile=feature[13..]; }
                else { if (feature_imported) return fatal("only one import-marks feature is allowed"); feature_imported=true;
                    if (!import_cli) { const path=feature[std.mem.indexOfScalar(u8,feature,'=').?+1..]; if (load(path)) |data| { var lines=std.mem.splitScalar(u8,data,'\n'); while (lines.next()) |l| { const space=std.mem.indexOfScalar(u8,l,' ') orelse continue; if (starts(l,":")) marks.put(l[1..space],l[space+1..]) catch unreachable; } } else if (!starts(feature,"import-marks-if-exists=")) return fatal("cannot read marks"); }
                }
            } else if (eq(feature,"done")) require_done=true else if (starts(feature,"date-format=") or eq(feature,"force") or eq(feature,"cat-blob") or eq(feature,"get-mark") or eq(feature,"ls") or eq(feature,"alias") or eq(feature,"notes") or starts(feature,"relative-marks") or starts(feature,"no-relative-marks")) {} else if (starts(command,"feature ")) return fatal(fmt("unsupported feature {s}",.{feature}));
        }
        else return fatal(fmt("Unsupported command: {s}",.{command}));
    }
    if (require_done and !done) return fatal("stream ends early");
    if (exportfile) |file| { var keys: std.ArrayList([]const u8)=.empty; var it=marks.keyIterator(); while (it.next()) |k| keys.append(a,k.*) catch unreachable; std.mem.sort([]const u8,keys.items,{},struct { fn less(_: void,x: []const u8,y: []const u8) bool { return (std.fmt.parseInt(u64,x,10) catch 0)<(std.fmt.parseInt(u64,y,10) catch 0); } }.less); var b: std.ArrayList(u8)=.empty; for (keys.items) |k| b.appendSlice(a,fmt(":{s} {s}\n",.{k,marks.get(k).?})) catch unreachable; if (!put(file,b.items)) return 1; }
    if (imported.items.len>0) { const p=packlib.encode(imported.items,.{.deltas=true,.ofs_delta=true}) catch return 1; _=writePackFiles(join(objectDirectory() orelse return 128,"pack/pack"),p,2) orelse return 1;
        for (imported.items) |obj| { const id=packlib.hashObject(obj); remove(join(objectDirectory().?,fmt("{s}/{s}",.{id[0..2],id[2..]}))); }
    } return 0;
}
const RepositoryContext=struct {
    dir: ?[]const u8, dirs: ?Args, packs: std.ArrayList(CachedPack), loaded: bool,
    fn enter(path: []const u8) RepositoryContext {
        const saved=RepositoryContext{.dir=git_dir_arg,.dirs=object_dirs,.packs=pack_cache,.loaded=packs_loaded};
        git_dir_arg=path; object_dirs=null; pack_cache=.empty; packs_loaded=false; return saved;
    }
    fn restore(self: RepositoryContext) void { git_dir_arg=self.dir; object_dirs=self.dirs; pack_cache=self.packs; packs_loaded=self.loaded; }
};
fn repositoryPath(source: []const u8) ?[]const u8 {
    const path=absolute(if (starts(source,"file://")) source[7..] else source);
    if (exists(join(path,".git/HEAD"))) return join(path,".git"); if (exists(join(path,"HEAD")) and exists(join(path,"objects"))) return path; return null;
}
fn cloneCommand(args: Args) u8 {
    var bare=false; var mirror=false; var checkout_files=true; var branch: ?[]const u8=null; var origin: []const u8="origin"; var source: ?[]const u8=null; var destination: ?[]const u8=null; var filter: ?[]const u8=null;
    var i: usize=0; while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"--bare")) bare=true else if (eq(s,"--mirror")) { bare=true; mirror=true; } else if (eq(s,"--no-checkout") or eq(s,"-n")) checkout_files=false
        else if (eq(s,"-b") or eq(s,"--branch") or eq(s,"-o") or eq(s,"--origin")) { i+=1; if (i==args.len) return 129; if (eq(s,"-b") or eq(s,"--branch")) branch=args[i] else origin=args[i]; }
        else if (starts(s,"--filter=")) filter=s[9..] else if (eq(s,"--local") or eq(s,"--no-local") or eq(s,"--no-hardlinks") or eq(s,"-q") or eq(s,"--quiet")) {}
        else if (starts(s,"-")) return 129 else if (source==null) source=s else if (destination==null) destination=s else return 129;
    }
    const src=source orelse return 129; const srcgit=repositoryPath(src) orelse return fatal(fmt("repository '{s}' does not exist",.{src}));
    var defaultname=std.fs.path.basename(std.mem.trimEnd(u8,src,"/")); if (std.mem.endsWith(u8,defaultname,".git")) defaultname=defaultname[0..defaultname.len-4]; const dest=absolute(destination orelse if (bare) fmt("{s}.git",.{defaultname}) else defaultname);
    if (exists(dest)) { const d=std.c.opendir(z(dest)) orelse return fatal("destination path already exists"); var nonempty=false; while (std.c.readdir(d)) |e| { const name=std.mem.sliceTo(&e.name,0); if (!eq(name,".") and !eq(name,"..")) { nonempty=true; break; } } _=std.c.closedir(d); if (nonempty) return fatal("destination path already exists and is not an empty directory"); }
    const sourcecontext=RepositoryContext.enter(srcgit); const refs=allRefs(); const sourcehead=trim(load(join(srcgit,"HEAD")) orelse ""); var selected=branch;
    if (selected==null and starts(sourcehead,"ref: refs/heads/")) selected=sourcehead[16..];
    const head=if (selected) |name| resolve(name) else resolve("HEAD"); var seen=std.StringHashMap(void).init(a); var graph: std.ArrayList(NamedObject)=.empty; var valid=true;
    for (refs) |r| { if (!collectObjectGraph(r.oid,"",true,&seen,&graph,0)) { valid=false; break; } } if (head) |id| { if (!collectObjectGraph(id,"",true,&seen,&graph,0)) valid=false; } sourcecontext.restore();
    if (!valid) return fatal("unable to read source objects");
    const saved_dir=git_dir_arg; git_dir_arg=null; const rc=initRepo(if (bare) &.{"--bare","-q",dest} else &.{"-q",dest},bare); git_dir_arg=saved_dir; if (rc!=0) return rc;
    const dstgit=if (bare) dest else join(dest,".git"); var objects: std.ArrayList(Object)=.empty;
    for (graph.items) |named| { if (filter!=null and eq(filter.?,"blob:none") and eq(named.obj.typ,"blob")) { var direct=false; for (refs) |r| { if (eq(r.oid,named.oid)) direct=true; } if (!direct) continue; } objects.append(a,named.obj) catch unreachable; }
    if (objects.items.len>0) { const pack=packlib.encode(objects.items,.{.deltas=true,.ofs_delta=true}) catch return fatal("cannot transfer objects"); const sum=writePackFiles(join(dstgit,"objects/pack/pack"),pack,2) orelse return 1; if (filter!=null) _=put(join(dstgit,fmt("objects/pack/pack-{s}.promisor",.{sum})),""); }
    for (refs) |r| { const target=if (bare or mirror or starts(r.name,"refs/tags/")) r.name else if (starts(r.name,"refs/heads/")) fmt("refs/remotes/{s}/{s}",.{origin,r.name[11..]}) else continue; if (!put(join(dstgit,target),fmt("{s}\n",.{r.oid}))) return 1; }
    if (head) |id| {
        if (selected) |name| { _=put(join(dstgit,"HEAD"),fmt("ref: refs/heads/{s}\n",.{name})); _=put(join(dstgit,fmt("refs/heads/{s}",.{name})),fmt("{s}\n",.{id})); }
        else _=put(join(dstgit,"HEAD"),fmt("{s}\n",.{id}));
    }
    const cfg=join(dstgit,"config"); _=configSet(cfg,fmt("remote.{s}.url",.{origin}),absolute(if (starts(src,"file://")) src[7..] else src),false);
    _=configSet(cfg,fmt("remote.{s}.fetch",.{origin}),if (mirror) "+refs/*:refs/*" else fmt("+refs/heads/*:refs/remotes/{s}/*",.{origin}),false);
    if (selected) |name| { if (!bare) { _=configSet(cfg,fmt("branch.{s}.remote",.{name}),origin,false); _=configSet(cfg,fmt("branch.{s}.merge",.{name}),fmt("refs/heads/{s}",.{name}),false); } }
    if (filter) |f| { _=configSet(cfg,fmt("remote.{s}.promisor",.{origin}),"true",false); _=configSet(cfg,fmt("remote.{s}.partialclonefilter",.{origin}),f,false); }
    if (!bare and checkout_files and head!=null) {
        const old=cwd(); if (chdir(z(dest))!=0) return 1; defer _=chdir(z(old)); const context=RepositoryContext.enter(dstgit); defer context.restore(); return checkout(&.{"-f","HEAD"});
    } return 0;
}
fn fetchCommand(args: Args) u8 {
    var remote: []const u8="origin"; var specs: std.ArrayList([]const u8)=.empty; var named=false;
    for (args) |s| { if (starts(s,"-")) continue; if (!named) { remote=s; named=true; } else specs.append(a,s) catch unreachable; }
    const url=configGet(fmt("remote.{s}.url",.{remote})) orelse remote; const src=repositoryPath(url) orelse return fatal("only local repository fetch is supported"); const dstgit=gitdir() orelse return 128;
    const context=RepositoryContext.enter(src); const refs=allRefs(); var roots: std.ArrayList([]const u8)=.empty; var updates: std.ArrayList(Ref)=.empty;
    if (specs.items.len==0) { for (refs) |r| { if (starts(r.name,"refs/heads/")) { roots.append(a,r.oid) catch unreachable; updates.append(a,.{.name=fmt("refs/remotes/{s}/{s}",.{remote,r.name[11..]}),.oid=r.oid}) catch unreachable; } else if (starts(r.name,"refs/tags/")) { roots.append(a,r.oid) catch unreachable; updates.append(a,r) catch unreachable; } } }
    for (specs.items) |spec| { const text=if (starts(spec,"+")) spec[1..] else spec; const colon=std.mem.indexOfScalar(u8,text,':') orelse text.len; const id=resolve(text[0..colon]) orelse { context.restore(); return fatal("could not find remote ref"); }; roots.append(a,id) catch unreachable; if (colon<text.len) { const dest=text[colon+1..]; updates.append(a,.{.name=if (starts(dest,"refs/")) dest else fmt("refs/heads/{s}",.{dest}),.oid=id}) catch unreachable; } }
    var seen=std.StringHashMap(void).init(a); var graph: std.ArrayList(NamedObject)=.empty; var valid=true; for (roots.items) |id| { if (!collectObjectGraph(id,"",true,&seen,&graph,0)) valid=false; } context.restore(); if (!valid) return fatal("missing source object");
    var objects: std.ArrayList(Object)=.empty; for (graph.items) |named_object| objects.append(a,named_object.obj) catch unreachable; if (objects.items.len>0) { const p=packlib.encode(objects.items,.{.deltas=true,.ofs_delta=true}) catch return 1; _=writePackFiles(join(dstgit,"objects/pack/pack"),p,2) orelse return 1; }
    for (updates.items) |r| { if (!put(join(dstgit,r.name),fmt("{s}\n",.{r.oid}))) return 1; } var b: std.ArrayList(u8)=.empty; for (roots.items) |id| b.appendSlice(a,fmt("{s}\t\t{s}\n",.{id,url})) catch unreachable; return if (put(join(dstgit,"FETCH_HEAD"),b.items)) 0 else 1;
}
fn mergeBaseId(left: []const u8, right: []const u8) ?[]const u8 {
    var l=std.StringHashMap(void).init(a); var r=std.StringHashMap(void).init(a); ancestors(&.{left},&l,false); ancestors(&.{right},&r,false); var best: ?[]const u8=null; var newest: i64=std.math.minInt(i64); var it=l.keyIterator(); while (it.next()) |id| { if (r.contains(id.*) and commitTime(id.*)>=newest) { best=id.*; newest=commitTime(id.*); } } return best;
}
fn isAncestor(left: []const u8, right: []const u8) bool { var seen=std.StringHashMap(void).init(a); ancestors(&.{right},&seen,false); return seen.contains(left); }
fn mergeCommand(args: Args) u8 {
    var refs: std.ArrayList([]const u8)=.empty; var message: ?[]const u8=null; var noff=false; var ffonly=false; var nocommit=false; var ours=false;
    var i: usize=0; while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"-m")) { i+=1; if (i==args.len) return 129; message=args[i]; } else if (eq(s,"--no-ff")) noff=true else if (eq(s,"--ff-only")) ffonly=true else if (eq(s,"--no-commit")) nocommit=true else if (eq(s,"-s")) { i+=1; if (i==args.len) return 129; ours=eq(args[i],"ours"); } else if (!starts(s,"-")) refs.append(a,s) catch unreachable; }
    if (refs.items.len==0) return 129; const head=resolve("HEAD"); var current=head; var parents: std.ArrayList([]const u8)=.empty; if (head) |id| parents.append(a,id) catch unreachable;
    var result: std.ArrayList(IndexEntry)=.empty; if (head) |id| { if (!readTreeEntries(id,"",&result)) return 128; }
    for (refs.items) |ref| { const theirs=resolve(ref) orelse return fatal("not something we can merge"); if (current) |id| { if (isAncestor(theirs,id)) continue; if (isAncestor(id,theirs) and refs.items.len==1 and !noff and !ours) { const rc=updateRefValue("HEAD",theirs,null,false,"merge: Fast-forward",0); if (rc!=0) return rc; return checkout(&.{"-f","HEAD"}); } } else { if (updateRefValue("HEAD",theirs,null,false,"merge",0)!=0) return 1; return checkout(&.{"-f","HEAD"}); }
        if (ffonly) return fatal("Not possible to fast-forward, aborting."); parents.append(a,theirs) catch unreachable;
        if (!ours) { var other: std.ArrayList(IndexEntry)=.empty; if (!readTreeEntries(theirs,"",&other)) return 128; var base: std.ArrayList(IndexEntry)=.empty; if (mergeBaseId(current.?,theirs)) |id| { if (!readTreeEntries(id,"",&base)) return 128; }
            for (other.items) |e| { const old=entryFor(base.items,e.path); const own=entryFor(result.items,e.path); if (own!=null and eq(own.?.oid,e.oid)) continue; const theirs_changed=old==null or !eq(old.?.oid,e.oid); if (!theirs_changed) continue;
                if (own!=null and (old==null or !eq(own.?.oid,old.?.oid))) return fatal(fmt("merge conflict in {s}",.{e.path})); importSetFile(&result,e.path,e.oid,e.mode);
            }
            var n: usize=0; while (n<result.items.len) { const e=result.items[n]; const old=entryFor(base.items,e.path); if (old!=null and entryFor(other.items,e.path)==null and eq(old.?.oid,e.oid)) _=result.orderedRemove(n) else n+=1; }
        }
        current=theirs;
    }
    if (parents.items.len<=1) return 0; sortIndex(result.items); const tree=treeFromIndex(result.items,"") orelse return 1;
    for (readIndex()) |e| { if (entryFor(result.items,e.path)==null) remove(e.path); } for (result.items) |e| { if (!materialize(e)) return 1; } if (!writeIndex(result.items)) return 1;
    const msg=message orelse fmt("Merge branch '{s}'",.{refs.items[0]});
    if (nocommit) { var b: std.ArrayList(u8)=.empty; for (parents.items[1..]) |id| b.appendSlice(a,fmt("{s}\n",.{id})) catch unreachable; const g=gitdir().?; _=put(join(g,"MERGE_HEAD"),b.items); _=put(join(g,"MERGE_MSG"),msg); return 0; }
    var data: std.ArrayList(u8)=.empty; data.appendSlice(a,fmt("tree {s}\n",.{tree})) catch unreachable; for (parents.items) |id| data.appendSlice(a,fmt("parent {s}\n",.{id})) catch unreachable;
    data.appendSlice(a,fmt("author {s}\ncommitter {s}\n\n{s}\n",.{ident(false) orelse return 128,ident(true) orelse return 128,msg})) catch unreachable;
    return updateRefValue("HEAD",objectHash("commit",data.items,true) orelse return 1,null,false,"merge",0);
}
const NamedObject=struct { oid: []const u8, obj: Object, path: []const u8="" };
fn collectObjectGraph(oid: []const u8, path: []const u8, traverse: bool, seen: *std.StringHashMap(void), objects: *std.ArrayList(NamedObject), depth: usize) bool {
    if (seen.contains(oid)) return true; if (depth>2048) return false;
    const obj=readObject(oid) orelse return false; seen.put(oid,{}) catch unreachable; objects.append(a,.{.oid=oid,.obj=obj,.path=path}) catch unreachable;
    if (!traverse) return true;
    if (eq(obj.typ,"commit")) {
        const tree=header(obj.data,"tree") orelse return false; if (!collectObjectGraph(tree,"",true,seen,objects,depth+1)) return false;
        for (commitParents(obj)) |parent| { if (!collectObjectGraph(parent,"",true,seen,objects,depth+1)) return false; }
    } else if (eq(obj.typ,"tag")) {
        if (!collectObjectGraph(header(obj.data,"object") orelse return false,"",true,seen,objects,depth+1)) return false;
    } else if (eq(obj.typ,"tree")) {
        var off: usize=0; while (off<obj.data.len) { const space=std.mem.indexOfScalarPos(u8,obj.data,off,' ') orelse return false; const end=std.mem.indexOfScalarPos(u8,obj.data,space,0) orelse return false; if (end+21>obj.data.len) return false;
            if (!eq(obj.data[off..space],"160000")) { const hex=std.fmt.bytesToHex(obj.data[end+1..][0..20].*,.lower); const id=a.dupe(u8,&hex) catch unreachable; const name=if (path.len==0) obj.data[space+1..end] else join(path,obj.data[space+1..end]); if (!collectObjectGraph(id,name,true,seen,objects,depth+1)) return false; } off=end+21;
        }
    } return true;
}
fn looseObjectNames(objects: []const u8) Args {
    var names: std.ArrayList([]const u8)=.empty; const dir=std.c.opendir(z(objects)) orelse return &.{}; defer _=std.c.closedir(dir);
    while (std.c.readdir(dir)) |entry| { const prefix=std.mem.sliceTo(&entry.name,0); if (prefix.len!=2) continue; _=std.fmt.parseInt(u8,prefix,16) catch continue;
        const sub=std.c.opendir(z(join(objects,prefix))) orelse continue; defer _=std.c.closedir(sub);
        while (std.c.readdir(sub)) |e| { const name=std.mem.sliceTo(&e.name,0); if (name.len!=38) continue; _=std.fmt.parseInt(u152,name,16) catch continue; names.append(a,fmt("{s}{s}",.{prefix,name})) catch unreachable; }
    } return names.toOwnedSlice(a) catch unreachable;
}
fn packedLocation(oid: []const u8, kept_only: bool, external_only: bool) bool {
    loadPacks(); for (pack_cache.items) |cached| { if (cached.virtual or (external_only and cached.local)) continue; if (kept_only and !exists(fmt("{s}.keep",.{cached.path[0..cached.path.len-5]}))) continue; if (cached.pack) |p| { if (p.by_oid.contains(oid)) return true; } } return false;
}
fn writePackFiles(prefix: []const u8, p: packlib.Pack, version: u32) ?[]const u8 {
    return writePackFilesThreshold(prefix,p,version,0x80000000);
}
fn writePackFilesThreshold(prefix: []const u8, p: packlib.Pack, version: u32, threshold: u64) ?[]const u8 {
    const sum=packlib.hex(p.checksum); const base=fmt("{s}-{s}",.{prefix,sum}); const idx=packlib.encodeIndexThreshold(p,version,threshold) catch return null;
    if (!put(fmt("{s}.pack",.{base}),p.bytes)) return null; if (!put(fmt("{s}.idx",.{base}),idx)) return null; return sum;
}
fn packRanks(p: packlib.Pack) []u32 {
    const sorted=a.alloc(usize,p.records.len) catch unreachable; for (sorted,0..) |*v,i| v.*=i;
    std.mem.sort(usize,sorted,p.records,struct { fn less(records: []packlib.Record,x: usize,y: usize) bool { return std.mem.lessThan(u8,records[x].oid.?,records[y].oid.?); } }.less);
    const ranks=a.alloc(u32,p.records.len) catch unreachable; for (sorted,0..) |index,rank| ranks[index]=@intCast(rank); return ranks;
}
fn reachableBits(p: *const packlib.Pack, index: usize, states: []u8, bitsets: [][]u64) bool {
    if (states[index]==2) return true; if (states[index]==1) return false; states[index]=1;
    const words=a.alloc(u64,(p.records.len+63)/64) catch unreachable; @memset(words,0); words[index/64]|=@as(u64,1)<<@intCast(index%64); bitsets[index]=words;
    var children: std.ArrayList([]const u8)=.empty; const obj=p.records[index].object orelse return false;
    if (eq(obj.typ,"commit")) { children.append(a,header(obj.data,"tree") orelse return false) catch unreachable; children.appendSlice(a,commitParents(obj)) catch unreachable; }
    else if (eq(obj.typ,"tag")) children.append(a,header(obj.data,"object") orelse return false) catch unreachable
    else if (eq(obj.typ,"tree")) { var off: usize=0; while (off<obj.data.len) { const sp=std.mem.indexOfScalarPos(u8,obj.data,off,' ') orelse return false; const end=std.mem.indexOfScalarPos(u8,obj.data,sp,0) orelse return false; if (end+21>obj.data.len) return false; if (!eq(obj.data[off..sp],"160000")) children.append(a,packlib.hex(obj.data[end+1..][0..20].*)) catch unreachable; off=end+21; } }
    for (children.items) |id| { const child=p.by_oid.get(id) orelse return false; if (!reachableBits(p,child,states,bitsets)) return false; for (bitsets[child],0..) |w,i| words[i]|=w; }
    states[index]=2; return true;
}
fn writeBitmap(prefix: []const u8, p: *const packlib.Pack, lookup: bool) bool {
    const states=a.alloc(u8,p.records.len) catch unreachable; @memset(states,0); const bitsets=a.alloc([]u64,p.records.len) catch unreachable; const ranks=packRanks(p.*); var entries: std.ArrayList(packlib.BitmapEntry)=.empty;
    for (p.records,0..) |r,i| { if (!eq(r.object.?.typ,"commit")) continue; if (!reachableBits(p,i,states,bitsets)) return false; entries.append(a,.{.index=ranks[i],.words=bitsets[i]}) catch unreachable; }
    const bytes=packlib.encodeBitmap(p.*,entries.items,lookup) catch return false; if (!put(fmt("{s}.bitmap",.{prefix}),bytes)) return false;
    if (env("GIT_TRACE2_EVENT")) |path| { if (starts(path,"/")) {
        appendFile(path,fmt("{{\"event\":\"data\",\"category\":\"bitmap\",\"key\":\"num_selected_commits\",\"value\":\"{d}\"}}\n",.{entries.items.len}));
        if (lookup) appendFile(path,"{\"event\":\"region_enter\",\"category\":\"bitmap\",\"label\":\"writing_lookup_table\"}\n");
    } } return true;
}
const BitmapWalk=struct {
    pack: *const packlib.Pack, bitmap: *const packlib.Bitmap, ranks: []u32, seen: std.StringHashMap(void), bits: []u64, extras: std.ArrayList(NamedObject)=.empty, used: bool=false,
    fn add(self: *BitmapWalk, oid: []const u8, depth: usize) bool {
        if (self.seen.contains(oid)) return true; if (depth>2048) return false; self.seen.put(oid,{}) catch unreachable;
        if (self.pack.by_oid.get(oid)) |index| {
            if (self.bitmap.entries.get(self.ranks[index])) |words| { if (words.len>self.bits.len) return false; for (words,0..) |w,i| self.bits[i]|=w; self.used=true; return true; }
            self.bits[index/64]|=@as(u64,1)<<@intCast(index%64);
        }
        const obj=readObject(oid) orelse return false; if (!self.pack.by_oid.contains(oid)) self.extras.append(a,.{.oid=oid,.obj=obj}) catch unreachable;
        if (eq(obj.typ,"commit")) { if (!self.add(header(obj.data,"tree") orelse return false,depth+1)) return false; for (commitParents(obj)) |id| { if (!self.add(id,depth+1)) return false; } }
        else if (eq(obj.typ,"tag")) { if (!self.add(header(obj.data,"object") orelse return false,depth+1)) return false; }
        else if (eq(obj.typ,"tree")) { var off: usize=0; while (off<obj.data.len) { const sp=std.mem.indexOfScalarPos(u8,obj.data,off,' ') orelse return false; const end=std.mem.indexOfScalarPos(u8,obj.data,sp,0) orelse return false; if (end+21>obj.data.len) return false; if (!eq(obj.data[off..sp],"160000")) { if (!self.add(packlib.hex(obj.data[end+1..][0..20].*),depth+1)) return false; } off=end+21; } }
        return true;
    }
};
fn bitmapTraversal(roots: Args, excludes: Args, objects: bool, count: bool, quiet: bool, test_bitmap: bool) ?u8 {
    loadPacks(); var pack_index=pack_cache.items.len; while (pack_index>0) { pack_index-=1; const cached=&pack_cache.items[pack_index];
        const path=fmt("{s}.bitmap",.{cached.path[0..cached.path.len-5]}); const data=load(path) orelse continue; const bitmap=packlib.decodeBitmap(data) catch { emit(2,"warning: corrupted bitmap index\n"); continue; }; const p=if (cached.pack) |*v| v else continue; if (!eq(&p.checksum,&bitmap.checksum)) continue;
        const ranks=packRanks(p.*); const bits=a.alloc(u64,(p.records.len+63)/64) catch unreachable; @memset(bits,0); var walk=BitmapWalk{.pack=p,.bitmap=&bitmap,.ranks=ranks,.bits=bits,.seen=std.StringHashMap(void).init(a)};
        for (roots) |id| { if (!walk.add(id,0)) return null; } if (!walk.used) continue;
        if (env("GIT_TRACE2_EVENT")) |trace| { if (starts(trace,"/")) {
            appendFile(trace,fmt("{{\"event\":\"data\",\"category\":\"bitmap\",\"key\":\"opened bitmap\",\"value\":\"{s}\"}}\n",.{std.fs.path.basename(path)}));
            var extra=false; for (pack_cache.items) |other| { if (eq(other.path,cached.path)) continue; if (exists(fmt("{s}.bitmap",.{other.path[0..other.path.len-5]}))) extra=true; } if (extra) appendFile(trace,"{\"event\":\"data\",\"category\":\"bitmap\",\"key\":\"ignoring extra bitmap\",\"value\":\"true\"}\n");
        } }
        const minus=a.alloc(u64,bits.len) catch unreachable; @memset(minus,0); var excluded=BitmapWalk{.pack=p,.bitmap=&bitmap,.ranks=ranks,.bits=minus,.seen=std.StringHashMap(void).init(a)};
        for (excludes) |id| { if (!excluded.add(id,0)) return null; } for (minus,0..) |w,i| bits[i]&=~w;
        if (test_bitmap) {
            const states=a.alloc(u8,p.records.len) catch unreachable; @memset(states,0); const graph=a.alloc([]u64,p.records.len) catch unreachable;
            for (roots) |id| { const index=p.by_oid.get(id) orelse return 1; if (!reachableBits(p,index,states,graph)) return 1; const actual=bitmap.entries.get(ranks[index]) orelse return 1; if (!std.mem.eql(u64,actual,graph[index])) return fatal("bitmap reachability mismatch"); }
            emit(2,"Bitmap v1 test succeeded\n"); return 0;
        }
        var n: usize=0;
        for (1..5) |kind| { if (!objects and kind!=1) break; for (p.records,0..) |r,i| { if (bits[i/64]&(@as(u64,1)<<@intCast(i%64))==0 or !eq(r.object.?.typ,packlib.typeName(@intCast(kind)))) continue; n+=1; if (!count and !quiet) line(r.oid.?); } }
        var minus_objects=std.StringHashMap(void).init(a); for (excluded.extras.items) |extra| minus_objects.put(extra.oid,{}) catch unreachable;
        for (walk.extras.items) |extra| { if (minus_objects.contains(extra.oid) or (!objects and !eq(extra.obj.typ,"commit"))) continue; n+=1; if (!count and !quiet) line(extra.oid); }
        if (count) line(fmt("{d}",.{n})); return 0;
    } return null;
}
fn tracePackBytes(count: usize) void {
    if (env("GIT_TRACE2_EVENT")) |path| { if (starts(path,"/")) appendFile(path,fmt("{{\"event\":\"data\",\"category\":\"pack-objects\",\"key\":\"write_pack_file/wrote_bytes\",\"value\":\"{d}\"}}\n",.{count})); }
}
fn packObjects(args: Args) u8 {
    var stdout=false; var revs=false; var all=false; var include_reflogs=false; var local=false; var honor_keep=false; var unpacked=false; var progress=false; var prefix: ?[]const u8=null; var version: u32=2; var compression: c_int=-1; var deltas=true; var ofs=false; var bitmap=false;
    var roots: std.ArrayList([]const u8)=.empty; var excludes: std.ArrayList([]const u8)=.empty; var negative=false; var threshold: u64=0x80000000;
    var i: usize=0; while (i<args.len) : (i+=1) { const s=args[i];
        if (eq(s,"--stdout")) stdout=true else if (eq(s,"--revs")) revs=true else if (eq(s,"--all")) { all=true; revs=true; } else if (eq(s,"--reflog")) include_reflogs=true
        else if (eq(s,"--local")) local=true else if (eq(s,"--honor-pack-keep")) honor_keep=true else if (eq(s,"--unpacked")) unpacked=true else if (eq(s,"--progress") or eq(s,"--all-progress")) progress=true else if (eq(s,"--delta-base-offset")) ofs=true
        else if (starts(s,"--window=")) { const n=std.fmt.parseInt(i32,s[9..],10) catch return 129; if (n<=0) deltas=false; }
        else if (starts(s,"--depth=")) { if (eq(s[8..],"0")) deltas=false; }
        else if (starts(s,"--compression=")) compression=std.fmt.parseInt(c_int,s[14..],10) catch return 129
        else if (starts(s,"--index-version=")) { var parts=std.mem.splitScalar(u8,s[16..],','); version=std.fmt.parseInt(u32,parts.next().?,10) catch return 129; if (parts.next()) |limit| { if (limit.len==0) return 129; threshold=std.fmt.parseInt(u64,limit,0) catch return 129; } }
        else if (starts(s,"--name-hash-version=")) { const n=std.fmt.parseInt(i32,s[20..],10) catch return 129; if (n==0 or n>2) return fatal("invalid --name-hash-version option"); }
        else if (eq(s,"--write-bitmap-index")) bitmap=true
        else if (eq(s,"--stdin")) return fatal("disallowed abbreviated or ambiguous option 'stdin'")
        else if (eq(s,"--stdin-packs")) return fatal("stdin-packs is not supported")
        else if (starts(s,"--")) { if (eq(s,"--keep-true-parents")) {} }
        else if (starts(s,"-")) return 129 else { if (prefix!=null) return 129; prefix=s; }
    }
    if ((!stdout and prefix==null) or (stdout and prefix!=null) or version<1 or version>2 or compression < -1 or compression>9) return 129;
    while (inputRecord('\n')) |l| {
        if (revs and l.len==0) break;
        if (revs and eq(l,"--not")) { negative=!negative; continue; }
        var words=std.mem.tokenizeScalar(u8,l,' '); const name=words.next() orelse "";
        if (revs and std.mem.indexOf(u8,name,"..")!=null) { const pos=std.mem.indexOf(u8,name,"..").?; const left=resolve(name[0..pos]) orelse return fatal(fmt("bad revision '{s}'",.{name})); const right=resolve(name[pos+2..]) orelse return fatal(fmt("bad revision '{s}'",.{name})); excludes.append(a,left) catch unreachable; roots.append(a,right) catch unreachable; continue; }
        const neg=name.len>0 and name[0]=='^'; const id=if (revs) resolve(if (neg) name[1..] else name) else if (name.len==40) resolve(name) else null;
        if (id==null) { if (revs) return fatal(fmt("bad revision '{s}'",.{name})); emit(2,fmt("fatal: expected object ID, got garbage:\n {s}\n\n",.{l})); return 128; }
        if (neg or negative) excludes.append(a,id.?) catch unreachable else roots.append(a,id.?) catch unreachable;
    }
    if (all) { for (allRefs()) |r| roots.append(a,r.oid) catch unreachable; }
    if (include_reflogs) appendReflogRoots(&roots);
    var seen=std.StringHashMap(void).init(a); var excluded_objects: std.ArrayList(NamedObject)=.empty;
    for (excludes.items) |id| { if (!collectObjectGraph(id,"",true,&seen,&excluded_objects,0)) return fatal("bad object"); }
    var objects: std.ArrayList(NamedObject)=.empty; for (roots.items) |id| { if (!collectObjectGraph(id,"",revs,&seen,&objects,0)) return fatal(fmt("bad object {s}",.{id})); }
    var selected: std.ArrayList(Object)=.empty;
    for (objects.items) |named| {
        if (unpacked and packedLocation(named.oid,false,false)) continue;
        if (honor_keep and packedLocation(named.oid,true,false)) continue;
        if (local) { var external=packedLocation(named.oid,false,true); for (objectDirectories()[@min(1,objectDirectories().len)..]) |d| { if (exists(join(d,fmt("{s}/{s}",.{named.oid[0..2],named.oid[2..]})))) external=true; } if (external) continue; }
        selected.append(a,named.obj) catch unreachable;
    }
    const pack=packlib.encode(selected.items,.{.compression=compression,.deltas=deltas,.ofs_delta=ofs}) catch |err| return fatal(fmt("cannot create pack: {s}",.{@errorName(err)}));
    if (stdout) out(pack.bytes) else line(writePackFilesThreshold(prefix.?,pack,version,threshold) orelse return fatal("unable to write pack"));
    if (bitmap and !stdout) { if (!writeBitmap(fmt("{s}-{s}",.{prefix.?,packlib.hex(pack.checksum)}),&pack,eq(configGet("pack.writebitmaplookuptable") orelse "false","true"))) emit(2,"warning: bitmap index could not be written for incomplete object closure\n"); }
    if (progress) { var n: usize=0; for (pack.records) |r| { if (r.kind==6 or r.kind==7) n+=1; } emit(2,fmt("Total {d} (delta {d}), reused 0 (delta 0), pack-reused 0\n",.{pack.records.len,n})); }
    tracePackBytes(pack.bytes.len); return 0;
}
fn appendReflogRoots(roots: *std.ArrayList([]const u8)) void {
    const g=gitdir() orelse return; var refs: std.ArrayList([]const u8)=.empty; refs.append(a,"HEAD") catch unreachable; for (allRefs()) |r| refs.append(a,r.name) catch unreachable;
    for (refs.items) |n| { if (load(join(g,fmt("logs/{s}",.{n})))) |data| { var lines=std.mem.splitScalar(u8,data,'\n'); while (lines.next()) |l| { if (l.len<81) continue; if (!eq(l[0..40],zeroOid)) roots.append(a,l[0..40]) catch unreachable; if (!eq(l[41..81],zeroOid)) roots.append(a,l[41..81]) catch unreachable; } } }
}
fn unpackObjects(args: Args) u8 {
    var dry=false; for (args) |s| { if (eq(s,"-n")) dry=true; }
    var pack=packlib.decode(stdin()) catch |err| return fatal(fmt("invalid pack: {s}",.{@errorName(err)})); pack.resolve(readExternalObject) catch |err| return fatal(fmt("invalid delta: {s}",.{@errorName(err)}));
    if (!dry) { for (pack.records) |r| { const obj=r.object orelse return 1; if (objectHash(obj.typ,obj.data,true)==null) return 1; } } return 0;
}
fn indexPack(args: Args) u8 {
    var input=false; var fix=false; var keep: ?[]const u8=null; var promisor=false; var path: ?[]const u8=null; var output: ?[]const u8=null; var version: u32=2;
    var verify=false; var explicit_version=false; var threshold: u64=0x80000000; var max_input: usize=std.math.maxInt(usize); var strict=false; var verbose=false;
    var i: usize=0; while (i<args.len) : (i+=1) { const s=args[i]; if (eq(s,"--stdin")) input=true else if (eq(s,"--fix-thin")) fix=true else if (eq(s,"--keep")) keep="" else if (starts(s,"--keep=")) keep=s[7..] else if (eq(s,"--promisor") or starts(s,"--promisor=")) promisor=true
        else if (eq(s,"-o")) { i+=1; if (i==args.len) return 129; output=args[i]; } else if (starts(s,"--index-version=")) { explicit_version=true; var split=std.mem.splitScalar(u8,s[16..],','); version=std.fmt.parseInt(u32,split.next().?,10) catch return 129; if (split.next()) |limit| { if (limit.len==0) return 129; threshold=std.fmt.parseInt(u64,limit,0) catch return 129; } }
        else if (eq(s,"--verify")) verify=true else if (eq(s,"--strict") or eq(s,"--fsck-objects")) strict=true else if (eq(s,"-v")) verbose=true
        else if (starts(s,"--max-input-size=")) max_input=std.fmt.parseInt(usize,s[17..],10) catch return 129 else if (!starts(s,"-")) { if (path!=null) return 129; path=s; }
    }
    if (!input and path==null) return 129; if (fix and !input) return 129;
    const bytes=if (input) stdin() else load(path.?) orelse return fatal("cannot open pack"); if (bytes.len>max_input) return fatal(fmt("pack exceeds maximum allowed size ({d} bytes)",.{max_input}));
    var p=packlib.decode(bytes) catch |err| return fatal(fmt("invalid pack: {s}",.{@errorName(err)}));
    p.resolve(if (fix) readExternalObject else null) catch |err| return fatal(fmt("invalid delta: {s}",.{@errorName(err)}));
    if (fix) {
        var objects: std.ArrayList(Object)=.empty; for (p.records) |r| objects.append(a,r.object.?) catch unreachable; var seen=std.StringHashMap(void).init(a);
        for (p.records) |r| { if (r.base_oid) |id| { if (!p.by_oid.contains(id) and !seen.contains(id)) { seen.put(id,{}) catch unreachable; objects.append(a,readObject(id) orelse return fatal("missing delta base")) catch unreachable; } } }
        if (objects.items.len!=p.records.len) p=packlib.encode(objects.items,.{}) catch return fatal("cannot complete thin pack");
    }
    const sum=packlib.hex(p.checksum); const packpath=if (path) |file| file else join(objectDirectory() orelse return 128,fmt("pack/pack-{s}.pack",.{sum}));
    if (input and !put(packpath,p.bytes)) return fatal("cannot write pack");
    const base=if (std.mem.endsWith(u8,packpath,".pack")) packpath[0..packpath.len-5] else packpath;
    const indexpath=output orelse fmt("{s}.idx",.{base});
    if (verify) { const existing=load(indexpath) orelse return fatal("cannot open index"); if (!explicit_version) version=if (starts(existing,"\xfftOc")) 2 else 1; if (verifyPack(&.{indexpath})!=0) return 1; return 0; }
    if (strict) { for (p.records) |r| { const obj=r.object.?; if (eq(obj.typ,"tag") and header(obj.data,"tagger")==null) emit(2,"warning: expected 'tagger' line in tag object\n");
        if (eq(obj.typ,"tree")) { var off: usize=0; while (off<obj.data.len) { const sp=std.mem.indexOfScalarPos(u8,obj.data,off,' ') orelse return 128; const end=std.mem.indexOfScalarPos(u8,obj.data,sp,0) orelse return 128; if (end+21>obj.data.len) return 128; const id=packlib.hex(obj.data[end+1..][0..20].*); if (!eq(obj.data[off..sp],"160000") and !p.by_oid.contains(id) and readObject(id)==null) return fatal(if (gitdir()==null) "cannot perform queued object checks outside of a repository" else "missing object"); off=end+21; } }
    } }
    const idx=packlib.encodeIndexThreshold(p,version,threshold) catch return fatal("invalid index version"); if (!put(indexpath,idx)) return fatal("cannot write index");
    if (keep) |msg| { if (!put(fmt("{s}.keep",.{base}),fmt("{s}\n",.{msg}))) return 1; } if (promisor) { if (!put(fmt("{s}.promisor",.{base}),"")) return 1; }
    if (verbose) emit(2,fmt("Receiving objects: 100% ({d}/{d}), done.\nResolving deltas: 100%, done.\n",.{p.records.len,p.records.len}));
    line(if (input) fmt("{s}\t{s}",.{if (keep!=null) "keep" else "pack",sum}) else sum); return 0;
}
fn showIndex(args: Args) u8 {
    _=args; const data=stdin(); if (data.len<1064) return fatal("short pack index"); const v2=eq(data[0..4],"\xfftOc"); if (v2 and be32(data[4..8])!=2) return fatal("unknown index version"); const start: usize=if (v2) 8 else 0; const count: usize=be32(data[start+1020..]); const table=start+1024;
    if (count>(data.len-table-40)/(if (v2) @as(usize,28) else 24)) return fatal("short pack index");
    for (0..count) |i| { const nameoff=if (v2) table+i*20 else table+i*24+4; const oid=packlib.hex(data[nameoff..][0..20].*); const off=be32(data[if (v2) table+24*count+4*i else table+24*i..]); var offset: u64=off;
        if (v2 and off&0x80000000!=0) { const pos=table+28*count+8*@as(usize,off&0x7fffffff); if (pos+8>data.len-40) return fatal("short pack index"); offset=std.mem.readInt(u64,data[pos..][0..8],.big); }
        if (v2) line(fmt("{d} {s} ({x:0>8})",.{offset,oid,be32(data[table+20*count+4*i..])})) else line(fmt("{d} {s}",.{offset,oid}));
    } return 0;
}
fn verifyPack(args: Args) u8 {
    var verbose=false; var stats=false; var paths: std.ArrayList([]const u8)=.empty; for (args) |s| { if (eq(s,"-v") or eq(s,"--verbose")) verbose=true else if (eq(s,"-s") or eq(s,"--stat-only")) stats=true else if (!starts(s,"-")) paths.append(a,s) catch unreachable; }
    if (paths.items.len==0) return 129;
    for (paths.items) |path| { const base=if (std.mem.endsWith(u8,path,".idx")) path[0..path.len-4] else if (std.mem.endsWith(u8,path,".pack")) path[0..path.len-5] else path;
        const index=load(fmt("{s}.idx",.{base})) orelse return fatal("cannot open pack index"); if (index.len<40 or !eq(&packlib.digest(index[0..index.len-20]),index[index.len-20..])) return fatal("pack index checksum mismatch");
        const data=load(fmt("{s}.pack",.{base})) orelse return fatal("cannot open pack"); var p=packlib.decode(data) catch return fatal("pack checksum mismatch"); p.resolve(null) catch return fatal("unresolved delta");
        if (!eq(&p.checksum,index[index.len-40..index.len-20])) return fatal("pack checksum does not match index");
        var undeltified: usize=0; var depths=std.AutoHashMap(usize,usize).init(a); var maxdepth: usize=0;
        for (p.records) |r| { if (r.depth==0) undeltified+=1 else { depths.put(r.depth,(depths.get(r.depth) orelse 0)+1) catch unreachable; maxdepth=@max(maxdepth,r.depth); }
            if (verbose) { const obj=r.object.?; out(fmt("{s} {s} {d} {d} {d}",.{r.oid.?,obj.typ,obj.data.len,r.packed_size,r.offset})); if (r.depth>0) { const baseoid=if (r.base_oid) |id| id else p.records[p.by_offset.get(r.base_offset.?).?].oid.?; out(fmt(" {d} {s}",.{r.depth,baseoid})); } out("\n"); }
        }
        if (verbose or stats) { line(fmt("non delta: {d} object{s}",.{undeltified,if (undeltified==1) "" else "s"})); var d: usize=1; while (d<=maxdepth) : (d+=1) { if (depths.get(d)) |n| line(fmt("chain length = {d}: {d} object{s}",.{d,n,if (n==1) "" else "s"})); } }
        if (verbose) line(fmt("{s}.pack: ok",.{base}));
    } return 0;
}
fn repack(args: Args) u8 {
    var delete=false; var all=false; var quiet=false; var window=true; var bitmap=eq(configGet("repack.writebitmaps") orelse "false","true");
    for (args) |s| { if (eq(s,"--window=0")) window=false else if (eq(s,"--write-bitmap-index")) bitmap=true else if (eq(s,"--no-write-bitmap-index")) bitmap=false else if (starts(s,"-") and !starts(s,"--")) { for (s[1..]) |c| { if (c=='a' or c=='A') all=true else if (c=='d') delete=true else if (c=='q') quiet=true else if (c=='b') bitmap=true; } } }
    const objectsdir=objectDirectory() orelse return 128; var roots: std.ArrayList([]const u8)=.empty; for (allRefs()) |r| roots.append(a,r.oid) catch unreachable; if (resolve("HEAD")) |id| roots.append(a,id) catch unreachable; appendReflogRoots(&roots); for (readIndex()) |e| roots.append(a,e.oid) catch unreachable;
    var seen=std.StringHashMap(void).init(a); var objects: std.ArrayList(NamedObject)=.empty; for (roots.items) |id| { if (!collectObjectGraph(id,"",true,&seen,&objects,0)) return fatal(fmt("bad object {s}",.{id})); }
    var selected: std.ArrayList(Object)=.empty; for (objects.items) |named| { if (!all and packedLocation(named.oid,false,false)) continue; selected.append(a,named.obj) catch unreachable; }
    if (selected.items.len==0) { if (!quiet) line("Nothing new to pack."); return 0; }
    const p=packlib.encode(selected.items,.{.deltas=window,.ofs_delta=true}) catch return fatal("cannot write pack");
    const hash=writePackFiles(join(objectsdir,"pack/pack"),p,2) orelse return fatal("cannot write pack");
    if (bitmap) { if (!writeBitmap(join(objectsdir,fmt("pack/pack-{s}",.{hash})),&p,eq(configGet("pack.writebitmaplookuptable") orelse "false","true"))) emit(2,"warning: bitmap index could not be written for incomplete object closure\n"); }
    if (delete) {
        if (all) { loadPacks(); for (pack_cache.items) |cached| { if (!cached.local or exists(fmt("{s}.keep",.{cached.path[0..cached.path.len-5]})) or std.mem.endsWith(u8,cached.path,fmt("pack-{s}.pack",.{hash}))) continue; remove(cached.path); remove(fmt("{s}.idx",.{cached.path[0..cached.path.len-5]})); remove(fmt("{s}.bitmap",.{cached.path[0..cached.path.len-5]})); remove(fmt("{s}.rev",.{cached.path[0..cached.path.len-5]})); } }
        for (objects.items) |named| remove(join(objectsdir,fmt("{s}/{s}",.{named.oid[0..2],named.oid[2..]})));
    }
    tracePackBytes(p.bytes.len); return 0;
}
fn prunePacked() u8 {
    const dir=objectDirectory() orelse return 128; for (looseObjectNames(dir)) |id| { if (packedLocation(id,false,false)) remove(join(dir,fmt("{s}/{s}",.{id[0..2],id[2..]}))); } return 0;
}
fn countObjects(args: Args) u8 {
    var verbose=false; for (args) |s| { if (eq(s,"-v") or eq(s,"-vH")) verbose=true; }
    const objects=objectDirectory() orelse return 128; const loose=looseObjectNames(objects); var size: usize=0; for (loose) |id| { if (load(join(objects,fmt("{s}/{s}",.{id[0..2],id[2..]})))) |data| size+=(data.len+1023)/1024; }
    if (!verbose) { line(fmt("{d} objects, {d} kilobytes",.{loose.len,size})); return 0; }
    loadPacks(); var count: usize=0; var packs: usize=0; var packedsize: usize=0; var prune: usize=0; for (pack_cache.items) |cached| { if (!cached.local or cached.virtual) continue; if (cached.pack) |p| { count+=p.records.len; packs+=1; packedsize+=p.bytes.len; } } for (loose) |id| { if (packedLocation(id,false,false)) prune+=1; }
    out(fmt("count: {d}\nsize: {d}\nin-pack: {d}\npacks: {d}\nsize-pack: {d}\nprune-packable: {d}\ngarbage: 0\nsize-garbage: 0\n",.{loose.len,size,count,packs,packedsize/1024,prune})); return 0;
}
fn midxChunk(data: []const u8, name: []const u8) ?[]const u8 {
    if (data.len<32 or !starts(data,"MIDX") or data[6]>32) return null; const count: usize=data[6]; if (12+(count+1)*12>data.len-20) return null;
    for (0..count) |i| { const pos=12+i*12; if (!eq(data[pos..pos+4],name)) continue; const start=std.mem.readInt(u64,data[pos+4..][0..8],.big); const end=std.mem.readInt(u64,data[pos+16..][0..8],.big); if (start>end or end>data.len-20) return null; return data[@intCast(start)..@intCast(end)]; } return null;
}
fn loadMidxCache() void {
    if (eq(configGet("core.multipackindex") orelse "true","false")) return; const objects=objectDirectory() orelse return; const data=load(join(objects,"pack/multi-pack-index")) orelse return;
    if (data.len<32 or data[5]!=1 or !eq(&packlib.digest(data[0..data.len-20]),data[data.len-20..])) return;
    const names=midxChunk(data,"PNAM") orelse return; const fanout=midxChunk(data,"OIDF") orelse return; const ids=midxChunk(data,"OIDL") orelse return; const offsets=midxChunk(data,"OOFF") orelse return; if (fanout.len!=1024) return; const count: usize=be32(fanout[1020..]); if (ids.len!=count*20 or offsets.len!=count*8) return;
    const packcount: usize=be32(data[8..12]); var filenames: std.ArrayList([]const u8)=.empty; var split=std.mem.splitScalar(u8,names,0); for (0..packcount) |_| filenames.append(a,split.next() orelse return) catch unreachable;
    const sorted_records=a.alloc(packlib.Record,count) catch unreachable;
    for (0..count) |i| { const id=packlib.hex(ids[i*20..][0..20].*); const packid: usize=be32(offsets[i*8..]); if (packid>=filenames.items.len) return; const idxname=filenames.items[packid]; if (!std.mem.endsWith(u8,idxname,".idx")) return; const wanted=fmt("{s}.pack",.{idxname[0..idxname.len-4]}); var found=false;
        for (pack_cache.items) |cached| { if (cached.virtual or !eq(std.fs.path.basename(cached.path),wanted)) continue; if (cached.pack) |p| { if (p.by_oid.get(id)) |index| { sorted_records[i]=p.records[index]; found=true; break; } } } if (!found) return;
    }
    const reverse=midxChunk(data,"RIDX") orelse return; if (reverse.len!=count*4) return;
    const records=a.alloc(packlib.Record,count) catch unreachable; var p=packlib.Pack{.bytes="",.records=records,.checksum=data[data.len-20..][0..20].*,.by_oid=std.StringHashMap(usize).init(a),.by_offset=std.AutoHashMap(u64,usize).init(a)};
    for (0..count) |i| { const index: usize=be32(reverse[i*4..]); if (index>=count) return; records[i]=sorted_records[index]; records[i].offset=i+12; p.by_oid.put(records[i].oid.?,i) catch unreachable; p.by_offset.put(i+12,i) catch unreachable; }
    const hash=packlib.hex(p.checksum); pack_cache.append(a,.{.path=join(objects,fmt("pack/multi-pack-index-{s}.pack",.{hash})),.pack=p,.virtual=true}) catch unreachable;
    if (env("GIT_TRACE2_EVENT")) |path| { if (starts(path,"/")) appendFile(path,"{\"event\":\"data\",\"category\":\"load_midx_revindex\",\"key\":\"source\",\"value\":\"midx\"}\n"); }
}
fn multiPackIndex(args: Args) u8 {
    var command: []const u8=""; var bitmap=false; var preferred: ?[]const u8=null; var objects=objectDirectory() orelse return 128;
    for (args) |s| { if (eq(s,"write") or eq(s,"verify") or eq(s,"expire") or eq(s,"repack")) command=s else if (eq(s,"--bitmap")) bitmap=true else if (starts(s,"--preferred-pack=")) preferred=s[17..] else if (starts(s,"--object-dir=")) objects=absolute(s[13..]); }
    const midxpath=join(objects,"pack/multi-pack-index");
    if (eq(command,"verify")) { const data=load(midxpath) orelse return 0; if (data.len<32 or !eq(&packlib.digest(data[0..data.len-20]),data[data.len-20..])) return fatal("multi-pack-index checksum mismatch"); const names=midxChunk(data,"PNAM") orelse return 1; var it=std.mem.splitScalar(u8,names,0); const count: usize=be32(data[8..12]); for (0..count) |_| { const name=it.next() orelse return 1; if (verifyPack(&.{join(join(objects,"pack"),name)})!=0) return 1; } return 0; }
    if (eq(command,"expire")) { const data=load(midxpath) orelse return 0; const offsets=midxChunk(data,"OOFF") orelse return 1; const names=midxChunk(data,"PNAM") orelse return 1; var it=std.mem.splitScalar(u8,names,0); const count: usize=be32(data[8..12]); for (0..count) |i| { const name=it.next() orelse return 1; var used=false; var off: usize=0; while (off+8<=offsets.len) : (off+=8) { if (be32(offsets[off..])==i) used=true; } if (!used) { const path=join(join(objects,"pack"),name); remove(path); if (std.mem.endsWith(u8,path,".idx")) remove(fmt("{s}.pack",.{path[0..path.len-4]})); } } return 0; }
    if (!eq(command,"write")) return 129;
    loadPacks(); var packs: std.ArrayList(usize)=.empty; for (pack_cache.items,0..) |cached,i| { if (!cached.virtual and starts(cached.path,join(objects,"pack/"))) packs.append(a,i) catch unreachable; }
    std.mem.sort(usize,packs.items,{},struct { fn less(_: void,x: usize,y: usize) bool { return std.mem.lessThan(u8,pack_cache.items[x].path,pack_cache.items[y].path); } }.less);
    if (packs.items.len==0) return fatal("no pack files to index");
    const MidxEntry=struct { record: packlib.Record, packid: u32, offset: u64 };
    var entries: std.ArrayList(MidxEntry)=.empty; var seen=std.StringHashMap(void).init(a); var packorder: std.ArrayList(usize)=.empty; var preferred_id: ?usize=null;
    if (preferred) |name| { for (packs.items,0..) |index,i| { const basename=std.fs.path.basename(pack_cache.items[index].path); if (eq(name,basename) or eq(name,fmt("{s}.pack",.{basename[0..basename.len-5]})) or eq(name,fmt("{s}.idx",.{basename[0..basename.len-5]}))) preferred_id=i; } if (preferred_id==null) return fatal("preferred pack not found"); }
    if (preferred_id) |id| packorder.append(a,id) catch unreachable;
    var n=packs.items.len; while (n>0) { n-=1; if (preferred_id!=null and preferred_id.?==n) continue; packorder.append(a,n) catch unreachable; }
    const ranges=a.alloc([2]u32,packs.items.len) catch unreachable; @memset(ranges,.{0,0});
    for (packorder.items) |packid| { const p=pack_cache.items[packs.items[packid]].pack orelse return 1; ranges[packid][0]=@intCast(entries.items.len); for (p.records) |r| { const id=r.oid orelse return 1; if (seen.contains(id)) continue; seen.put(id,{}) catch unreachable; entries.append(a,.{.record=r,.packid=@intCast(packid),.offset=r.offset}) catch unreachable; } ranges[packid][1]=@intCast(entries.items.len-ranges[packid][0]); }
    const records=a.alloc(packlib.Record,entries.items.len) catch unreachable; var pseudo=packlib.Pack{.bytes="",.records=records,.checksum=@splat(0),.by_oid=std.StringHashMap(usize).init(a),.by_offset=std.AutoHashMap(u64,usize).init(a)};
    for (entries.items,0..) |e,i| { records[i]=e.record; records[i].offset=i+12; pseudo.by_oid.put(records[i].oid.?,i) catch unreachable; pseudo.by_offset.put(i+12,i) catch unreachable; }
    if (bitmap) { const states=a.alloc(u8,records.len) catch unreachable; @memset(states,0); const bits=a.alloc([]u64,records.len) catch unreachable; for (records,0..) |_,i| { if (!reachableBits(&pseudo,i,states,bits)) return fatal("multi-pack bitmap doesn't have full closure"); } }
    const ranks=packRanks(pseudo); const sorted=a.alloc(usize,records.len) catch unreachable; for (ranks,0..) |rank,i| sorted[rank]=i;
    var pnam: std.ArrayList(u8)=.empty; for (packs.items) |index| { const basename=std.fs.path.basename(pack_cache.items[index].path); pnam.appendSlice(a,fmt("{s}.idx\x00",.{basename[0..basename.len-5]})) catch unreachable; } while (pnam.items.len%4!=0) pnam.append(a,0) catch unreachable;
    var fanout: std.ArrayList(u8)=.empty; var names: std.ArrayList(u8)=.empty; var offsets: std.ArrayList(u8)=.empty; var reverse: std.ArrayList(u8)=.empty; var bitmapped: std.ArrayList(u8)=.empty;
    var cumulative: u32=0; var pos: usize=0; for (0..256) |first| { while (pos<sorted.len) { const id=records[sorted[pos]].oid.?; const byte=std.fmt.parseInt(u8,id[0..2],16) catch return 1; if (byte>first) break; pos+=1; cumulative+=1; } packlib.appendInt(&fanout,u32,cumulative); }
    for (sorted) |i| { names.appendSlice(a,&oidBytes(records[i].oid.?)) catch unreachable; packlib.appendInt(&offsets,u32,entries.items[i].packid); if (entries.items[i].offset>std.math.maxInt(u32)) return fatal("large MIDX offsets are not supported"); packlib.appendInt(&offsets,u32,@intCast(entries.items[i].offset)); }
    for (ranks) |rank| packlib.appendInt(&reverse,u32,rank); for (ranges) |range| { packlib.appendInt(&bitmapped,u32,range[0]); packlib.appendInt(&bitmapped,u32,range[1]); }
    const Chunk=struct { name: []const u8, data: []const u8 }; const chunks=[_]Chunk{.{.name="PNAM",.data=pnam.items},.{.name="OIDF",.data=fanout.items},.{.name="OIDL",.data=names.items},.{.name="OOFF",.data=offsets.items},.{.name="RIDX",.data=reverse.items},.{.name="BTMP",.data=bitmapped.items}};
    var output: std.ArrayList(u8)=.empty; output.appendSlice(a,"MIDX\x01\x01\x06\x00") catch unreachable; packlib.appendInt(&output,u32,@intCast(packs.items.len)); var off: u64=12+(chunks.len+1)*12;
    for (chunks) |chunk| { output.appendSlice(a,chunk.name) catch unreachable; packlib.appendInt(&output,u64,off); off+=chunk.data.len; } packlib.appendInt(&output,u32,0); packlib.appendInt(&output,u64,off);
    for (chunks) |chunk| output.appendSlice(a,chunk.data) catch unreachable; pseudo.checksum=packlib.digest(output.items); output.appendSlice(a,&pseudo.checksum) catch unreachable;
    if (!put(midxpath,output.items)) return 1; const hash=packlib.hex(pseudo.checksum);
    if (bitmap) { if (!writeBitmap(join(objects,fmt("pack/multi-pack-index-{s}",.{hash})),&pseudo,eq(configGet("pack.writebitmaplookuptable") orelse "false","true"))) { remove(midxpath); return 1; } }
    else { remove(join(objects,fmt("pack/multi-pack-index-{s}.bitmap",.{hash}))); remove(join(objects,fmt("pack/multi-pack-index-{s}.rev",.{hash}))); }
    const dir=std.c.opendir(z(join(objects,"pack"))) orelse return 0; defer _=std.c.closedir(dir); while (std.c.readdir(dir)) |e| { const name=std.mem.sliceTo(&e.name,0); if (starts(name,"multi-pack-index-") and (std.mem.endsWith(u8,name,".bitmap") or std.mem.endsWith(u8,name,".rev")) and !starts(name,fmt("multi-pack-index-{s}.",.{hash}))) remove(join(join(objects,"pack"),name)); }
    return 0;
}
fn fsckCommand(args: Args) u8 {
    var roots: std.ArrayList([]const u8)=.empty; var showdangling=true;
    for (args) |s| { if (eq(s,"--no-dangling") or eq(s,"--no-progress")) { if (eq(s,"--no-dangling")) showdangling=false; } else if (!starts(s,"-")) roots.append(a,resolve(s) orelse return 1) catch unreachable; }
    var allobjects=std.StringHashMap(Object).init(a);
    for (objectDirectories()) |d| {
        for (looseObjectNames(d)) |id| { const obj=readObject(id) orelse return fatal(fmt("missing or corrupt object {s}",.{id})); if (!eq(packlib.hashObject(obj),id)) return fatal(fmt("hash mismatch {s}",.{id})); allobjects.put(id,obj) catch unreachable; }
        const dir=std.c.opendir(z(join(d,"pack"))) orelse continue; defer _=std.c.closedir(dir); while (std.c.readdir(dir)) |e| { const name=std.mem.sliceTo(&e.name,0); if (!std.mem.endsWith(u8,name,".idx")) continue; if (verifyPack(&.{join(join(d,"pack"),name)})!=0) return 1; }
    }
    loadPacks(); for (pack_cache.items) |cached| { if (cached.pack) |p| { for (p.records) |r| { if (r.object==null or r.oid==null) return 1; allobjects.put(r.oid.?,r.object.?) catch unreachable; } } }
    if (roots.items.len==0) { for (allRefs()) |r| roots.append(a,r.oid) catch unreachable; if (resolve("HEAD")) |id| roots.append(a,id) catch unreachable; for (readIndex()) |e| roots.append(a,e.oid) catch unreachable; appendReflogRoots(&roots); }
    var reachable=std.StringHashMap(void).init(a); var graph: std.ArrayList(NamedObject)=.empty; for (roots.items) |id| { if (!collectObjectGraph(id,"",true,&reachable,&graph,0)) return fatal(fmt("broken link from {s}",.{id})); }
    var checked=std.StringHashMap(void).init(a); var reference_count=std.StringHashMap(void).init(a); var it=allobjects.iterator();
    while (it.next()) |entry| { const obj=entry.value_ptr.*; if (eq(obj.typ,"commit")) { if (header(obj.data,"tree")) |id| reference_count.put(id,{}) catch unreachable else return 1; for (commitParents(obj)) |id| reference_count.put(id,{}) catch unreachable; } else if (eq(obj.typ,"tag")) { if (header(obj.data,"object")) |id| reference_count.put(id,{}) catch unreachable else return 1; }
        var objects: std.ArrayList(NamedObject)=.empty; if (!collectObjectGraph(entry.key_ptr.*,"",true,&checked,&objects,0)) return fatal("broken object connectivity"); for (objects.items) |named| { if (!eq(named.oid,entry.key_ptr.*)) reference_count.put(named.oid,{}) catch unreachable; }
    }
    if (showdangling) { var keys=allobjects.keyIterator(); while (keys.next()) |id| { if (!reachable.contains(id.*) and !reference_count.contains(id.*)) line(fmt("dangling {s} {s}",.{allobjects.get(id.*).?.typ,id.*})); } }
    return 0;
}
fn commitParents(obj: Object) Args {
    var list: std.ArrayList([]const u8)=.empty; var it=std.mem.splitScalar(u8,obj.data,'\n'); while (it.next()) |l| { if (l.len==0) break; if (starts(l,"parent ")) list.append(a,l[7..]) catch unreachable; } return list.toOwnedSlice(a) catch unreachable;
}
fn commitTime(oid: []const u8) i64 {
    const obj=readObject(oid) orelse return 0; const identity=header(obj.data,"committer") orelse return 0; const gt=std.mem.lastIndexOfScalar(u8,identity,'>') orelse return 0; var words=std.mem.tokenizeScalar(u8,identity[gt+1..],' '); return std.fmt.parseInt(i64,words.next() orelse "0",10) catch 0;
}
fn ancestors(roots: Args, seen: *std.StringHashMap(void), first: bool) void {
    var todo: std.ArrayList([]const u8)=.empty; todo.appendSlice(a,roots) catch unreachable;
    while (todo.pop()) |oid| { if (seen.contains(oid)) continue; seen.put(oid,{}) catch unreachable; const obj=readObject(oid) orelse continue;
        if (eq(obj.typ,"tag")) { if (header(obj.data,"object")) |id| todo.append(a,id) catch unreachable; continue; }
        const parents=commitParents(obj); todo.appendSlice(a,if (first and parents.len>0) parents[0..1] else parents) catch unreachable;
    }
}
fn prettyCommit(oid: []const u8, obj: Object, pattern: []const u8) []const u8 {
    var b: std.ArrayList(u8)=.empty; var i: usize=0; const ref=Ref{.name="",.oid=oid};
    while (i<pattern.len) : (i+=1) { if (pattern[i]!='%' or i+1>=pattern.len) { b.append(a,pattern[i]) catch unreachable; continue; } i+=1;
        if (pattern[i]=='x' and i+2<pattern.len) { const byte=std.fmt.parseInt(u8,pattern[i+1..i+3],16) catch return ""; b.append(a,byte) catch unreachable; i+=2; continue; }
        const code=pattern[i]; var value: []const u8="";
        switch (code) {
            '%'=>value="%", 'n'=>value="\n", 'H'=>value=oid, 'h'=>value=oid[0..7], 'T'=>value=header(obj.data,"tree") orelse "", 't'=>{ const t=header(obj.data,"tree") orelse ""; value=t[0..@min(t.len,7)]; },
            's'=>value=atomValue(ref,"subject") orelse "", 'b'=>value=atomValue(ref,"body") orelse "", 'B'=>value=atomValue(ref,"contents") orelse "",
            'P','p'=>{ var parents: std.ArrayList(u8)=.empty; for (commitParents(obj),0..) |p,j| { if (j>0) parents.append(a,' ') catch unreachable; parents.appendSlice(a,if (code=='p') p[0..7] else p) catch unreachable; } value=parents.items; },
            'a','c'=>{ if (i+1>=pattern.len) continue; i+=1; const who=if (code=='a') "author" else "committer"; const suffix=pattern[i]; value=atomValue(ref,fmt("{s}{s}",.{who,switch (suffix) { 'n','N'=>"name", 'e','E'=>"email:trim", 't'=>"date:unix", 'd'=>"date", 's'=>"date:short", 'i'=>"date:iso", else=>"" }})) orelse ""; },
            'd','D'=>{ var decorations: std.ArrayList(u8)=.empty; for (allRefs()) |r| { if (!eq(r.oid,oid)) continue; if (decorations.items.len>0) decorations.appendSlice(a,", ") catch unreachable; decorations.appendSlice(a,stripRef(r.name,"short")) catch unreachable; } value=if (code=='d' and decorations.items.len>0) fmt(" ({s})",.{decorations.items}) else decorations.items; },
            else=>{ b.append(a,'%') catch unreachable; b.append(a,code) catch unreachable; continue; },
        }
        b.appendSlice(a,value) catch unreachable;
    }
    return b.toOwnedSlice(a) catch unreachable;
}
fn printReachableObject(oid: []const u8, path: []const u8, seen: *std.StringHashMap(void), names: bool) void {
    if (seen.contains(oid)) return; seen.put(oid,{}) catch unreachable; const obj=readObject(oid) orelse return;
    line(if (path.len>0 and names) fmt("{s} {s}",.{oid,path}) else oid);
    if (eq(obj.typ,"tag")) { if (header(obj.data,"object")) |id| printReachableObject(id,path,seen,names); }
    if (!eq(obj.typ,"tree")) return;
    var off: usize=0; while (off<obj.data.len) { const sp=std.mem.indexOfScalarPos(u8,obj.data,off,' ') orelse return; const end=std.mem.indexOfScalarPos(u8,obj.data,sp,0) orelse return; if (end+21>obj.data.len) return; const hex=std.fmt.bytesToHex(obj.data[end+1..][0..20].*,.lower); const id=a.dupe(u8,&hex) catch unreachable; const child=if (path.len>0) join(path,obj.data[sp+1..end]) else obj.data[sp+1..end]; printReachableObject(id,child,seen,names); off=end+21; }
}
fn historyCommand(args: Args, command: []const u8) u8 {
    var roots: std.ArrayList([]const u8)=.empty; var excluded: std.ArrayList([]const u8)=.empty; var paths: std.ArrayList([]const u8)=.empty;
    var all=false; var reverse=false; var first=false; var count=false; var quiet=false; var parentsflag=false; var objects=false; var objectnames=true; var max: usize=if (eq(command,"show")) 1 else std.math.maxInt(usize); var skip: usize=0; var usebitmap=false; var testbitmap=false;
    var format: ?[]const u8=null; var raw=false; var patch=eq(command,"show"); var names=false; var numstat=false; var no_walk=false; var negated=false; var after=false; var minparents: usize=0; var maxparents: usize=std.math.maxInt(usize); var grep: ?[]const u8=null; var author: ?[]const u8=null; var committer: ?[]const u8=null; var invert=false; var terminate=true; var difffilter: ?[]const u8=null;
    var i: usize=0; while (i<args.len) : (i+=1) { const s=args[i];
        if (eq(s,"--")) { after=true; continue; } if (after) { paths.append(a,s) catch unreachable; continue; }
        if (eq(s,"--all") or eq(s,"--branches") or eq(s,"--tags") or eq(s,"--remotes")) all=true else if (eq(s,"--reverse")) reverse=true else if (eq(s,"--first-parent")) first=true else if (eq(s,"--count")) count=true else if (eq(s,"--quiet")) quiet=true else if (eq(s,"--parents")) parentsflag=true else if (eq(s,"--objects")) objects=true else if (eq(s,"--no-object-names")) objectnames=false else if (eq(s,"--not")) negated=!negated else if (starts(s,"--no-walk")) no_walk=true
        else if (eq(s,"--use-bitmap-index")) usebitmap=true else if (eq(s,"--test-bitmap")) { usebitmap=true; testbitmap=true; }
        else if (eq(s,"--oneline")) format="%h %s" else if (eq(s,"--pretty=oneline")) format="%H %s" else if (eq(s,"--pretty=raw")) format="raw" else if (eq(s,"--format") or eq(s,"--pretty")) format="%H"
        else if (starts(s,"--format=")) format=s[9..] else if (starts(s,"--pretty=format:")) { format=s[16..]; terminate=false; } else if (starts(s,"--pretty=tformat:")) format=s[17..] else if (starts(s,"--pretty=")) { const style=s[9..]; if (eq(style,"short")) format="commit %H%nAuthor: %an <%ae>%n%n    %s" else if (eq(style,"medium")) format=null else if (std.mem.indexOfScalar(u8,style,'%')!=null) format=style else format="%H"; }
        else if (eq(s,"-n") or eq(s,"--max-count")) { i+=1; if (i==args.len) return 129; max=std.fmt.parseInt(usize,args[i],10) catch return 129; }
        else if (starts(s,"--max-count=")) max=std.fmt.parseInt(usize,s[12..],10) catch return 129 else if (starts(s,"--skip=")) skip=std.fmt.parseInt(usize,s[7..],10) catch return 129
        else if (eq(s,"--merges")) minparents=2 else if (eq(s,"--no-merges")) maxparents=1
        else if (eq(s,"--raw")) raw=true else if (eq(s,"-p") or eq(s,"--patch")) patch=true else if (eq(s,"--no-patch") or eq(s,"-s")) patch=false else if (eq(s,"--name-only")) names=true else if (eq(s,"--numstat")) numstat=true else if (starts(s,"--grep=")) grep=s[7..]
        else if (starts(s,"--author=")) author=s[9..] else if (starts(s,"--committer=")) committer=s[12..] else if (eq(s,"--invert-grep")) invert=true
        else if (eq(s,"--grep") or eq(s,"--author") or eq(s,"--committer") or eq(s,"--diff-filter")) { i+=1; if (i==args.len) return 129; if (eq(s,"--grep")) grep=args[i] else if (eq(s,"--author")) author=args[i] else if (eq(s,"--committer")) committer=args[i] else difffilter=args[i]; }
        else if (starts(s,"--diff-filter=")) difffilter=s[14..]
        else if (eq(s,"--exclude-promisor-objects") and !eq(command,"rev-list")) return 129
        else if (s.len>1 and s[0]=='-' and std.ascii.isDigit(s[1])) max=std.fmt.parseInt(usize,s[1..],10) catch return 129
        else if (starts(s,"-")) {} else {
            if (std.mem.indexOf(u8,s,"..")) |pos| { const symmetric=pos+2<s.len and s[pos+2]=='.'; const offset: usize=if (symmetric) 3 else 2; const left=resolve(if (pos==0) "HEAD" else s[0..pos]) orelse return 128; const right=resolve(if (pos+offset==s.len) "HEAD" else s[pos+offset..]) orelse return 128; if (symmetric) { roots.append(a,left) catch unreachable; if (mergeBaseId(left,right)) |id| excluded.append(a,id) catch unreachable; } else excluded.append(a,left) catch unreachable; roots.append(a,right) catch unreachable; }
            else { if (s.len==0) return fatal("bad revision ''"); const oid=resolve(if (s[0]=='^') s[1..] else s) orelse { if (exists(s)) { paths.append(a,s) catch unreachable; continue; } return fatal(fmt("bad revision '{s}'",.{s})); }; if (negated or s[0]=='^') excluded.append(a,oid) catch unreachable else roots.append(a,oid) catch unreachable; }
        }
    }
    if (all) { for (allRefs()) |r| roots.append(a,r.oid) catch unreachable; }
    if (roots.items.len==0 and !all) { roots.append(a,resolve("HEAD") orelse return fatal("your current branch does not have any commits yet")) catch unreachable; }
    if (eq(command,"rev-list") and paths.items.len==0 and !parentsflag and max==std.math.maxInt(usize) and skip==0 and minparents==0 and maxparents==std.math.maxInt(usize) and !first and !reverse and grep==null and author==null and committer==null) {
        if (usebitmap) { if (bitmapTraversal(roots.items,excluded.items,objects,count,quiet,testbitmap)) |rc| return rc; if (testbitmap) return fatal("no bitmap found"); }
        if (count and objects) { var found=std.StringHashMap(void).init(a); var ignored: std.ArrayList(NamedObject)=.empty; for (excluded.items) |id| { if (!collectObjectGraph(id,"",true,&found,&ignored,0)) return 128; } var graph: std.ArrayList(NamedObject)=.empty; for (roots.items) |id| { if (!collectObjectGraph(id,"",true,&found,&graph,0)) return 128; } line(fmt("{d}",.{graph.items.len})); return 0; }
    }
    if (eq(command,"show") and roots.items.len>0) { const obj=readObject(roots.items[0]) orelse return 128; if (eq(obj.typ,"blob")) { out(obj.data); return 0; } if (eq(obj.typ,"tree")) return lsTree(&.{roots.items[0]}); }
    var seen=std.StringHashMap(void).init(a); ancestors(excluded.items,&seen,false); var todo: std.ArrayList([]const u8)=.empty; todo.appendSlice(a,roots.items) catch unreachable; var ordered: std.ArrayList([]const u8)=.empty;
    while (todo.items.len>0) { var best: usize=0; for (todo.items,0..) |id,j| { if (commitTime(id)>commitTime(todo.items[best])) best=j; } var oid=todo.orderedRemove(best); if (seen.contains(oid)) continue; var obj=readObject(oid) orelse continue;
        if (eq(obj.typ,"tag")) { oid=resolve(fmt("{s}^{{}}",.{oid})) orelse continue; obj=readObject(oid) orelse continue; } if (!eq(obj.typ,"commit") or seen.contains(oid)) continue;
        seen.put(oid,{}) catch unreachable; ordered.append(a,oid) catch unreachable;
        if (!no_walk and !eq(command,"show")) { const ps=commitParents(obj); todo.appendSlice(a,if (first and ps.len>0) ps[0..1] else ps) catch unreachable; }
    }
    if (reverse) std.mem.reverse([]const u8,ordered.items); var emitted: usize=0; var objectseen=std.StringHashMap(void).init(a);
    for (ordered.items) |oid| { if (emitted>=max) break; const obj=readObject(oid) orelse continue; const ps=commitParents(obj); if (ps.len<minparents or ps.len>maxparents) continue;
        if (grep) |pattern| { const matched=regexMatch(pattern,atomValue(.{.name="",.oid=oid},"contents") orelse "") orelse return 128; if (matched==invert) continue; }
        if (author) |pattern| { if (!(regexMatch(pattern,header(obj.data,"author") orelse "") orelse return 128)) continue; }
        if (committer) |pattern| { if (!(regexMatch(pattern,header(obj.data,"committer") orelse "") orelse return 128)) continue; }
        if (paths.items.len>0 or difffilter!=null) { var current: std.ArrayList(IndexEntry)=.empty; if (!readTreeEntries(oid,"",&current)) continue; var previous: std.ArrayList(IndexEntry)=.empty; if (ps.len>0) _=readTreeEntries(ps[0],"",&previous); var changed=false;
            for (current.items) |e| { if (!pathMatches(e.path,paths.items)) continue; const old=entryFor(previous.items,e.path); if (old==null or !eq(old.?.oid,e.oid)) { const status: u8=if (old==null) 'A' else 'M'; if (filterAllows(difffilter,status)) changed=true; } } for (previous.items) |e| { if (pathMatches(e.path,paths.items) and entryFor(current.items,e.path)==null and filterAllows(difffilter,'D')) changed=true; } if (!changed) continue;
        }
        if (skip>0) { skip-=1; continue; } emitted+=1; if (count or quiet) continue;
        if (eq(command,"rev-list")) { out(oid); if (parentsflag) { for (ps) |p| out(fmt(" {s}",.{p})); } out("\n"); }
        else if (format) |pattern| { if (eq(pattern,"raw")) { line(fmt("commit {s}",.{oid})); out(obj.data[0..std.mem.indexOf(u8,obj.data,"\n\n") orelse obj.data.len]); out("\n\n"); const contents=atomValue(.{.name="",.oid=oid},"contents") orelse ""; for (splitLines(contents)) |l| { out("    "); out(l); } out("\n"); }
            else { if (!terminate and emitted>1) out("\n"); out(prettyCommit(oid,obj,pattern)); if (terminate) out("\n"); } }
        else { if (emitted>1) out("\n"); line(fmt("commit {s}",.{oid})); const identity=header(obj.data,"author") orelse ""; const gt=std.mem.indexOfScalar(u8,identity,'>') orelse identity.len; line(fmt("Author: {s}",.{identity[0..@min(gt+1,identity.len)]})); line(fmt("Date:   {s}",.{if (gt<identity.len) formatDate(trim(identity[gt+1..]),"") else ""})); out("\n"); const contents=atomValue(.{.name="",.oid=oid},"contents") orelse ""; for (splitLines(contents)) |l| { out("    "); out(l); } }
        if (!eq(command,"rev-list") and (patch or raw or names or numstat)) { var diffargs: std.ArrayList([]const u8)=.empty; if (ps.len>0) diffargs.append(a,ps[0]) catch unreachable else diffargs.append(a,objectHash("tree","",true) orelse return 1) catch unreachable; diffargs.append(a,oid) catch unreachable; if (raw) diffargs.append(a,"--raw") catch unreachable else if (names) diffargs.append(a,"--name-only") catch unreachable else if (numstat) diffargs.append(a,"--numstat") catch unreachable; diffargs.append(a,"--") catch unreachable; diffargs.appendSlice(a,paths.items) catch unreachable; out("\n"); _=diffCommand(diffargs.items,"diff"); }
    }
    if (count) line(fmt("{d}",.{emitted}));
    if (objects and !quiet and !count) { var ignored: std.ArrayList(NamedObject)=.empty; for (excluded.items) |id| { if (!collectObjectGraph(id,"",true,&objectseen,&ignored,0)) return 128; } for (ordered.items) |id| objectseen.put(id,{}) catch unreachable; for (ordered.items) |id| { const obj=readObject(id) orelse continue; const tree=header(obj.data,"tree") orelse continue; printReachableObject(tree,"",&objectseen,objectnames); } for (roots.items) |id| { const obj=readObject(id) orelse continue; if (!eq(obj.typ,"commit")) printReachableObject(id,"",&objectseen,objectnames); } }
    return 0;
}
fn filterAllows(filter: ?[]const u8, status: u8) bool {
    const f=filter orelse return true; var positive=false; var included=false; for (f) |c| { if (std.ascii.isLower(c) and std.ascii.toUpper(c)==status) return false; if (std.ascii.isUpper(c)) { positive=true; if (c==status) included=true; } } return !positive or included;
}
const builtinNames="add am annotate apply archive backfill bisect blame branch bugreport bundle cat-file check-attr check-ignore check-mailmap check-ref-format checkout checkout--worker checkout-index cherry cherry-pick clean clone column commit commit-graph commit-tree config count-objects credential credential-cache credential-cache--daemon credential-store describe diagnose diff diff-files diff-index diff-pairs diff-tree difftool fast-export fast-import fetch fetch-pack fmt-merge-msg for-each-ref for-each-repo format-patch format-rev fsck fsck-objects fsmonitor--daemon gc get-tar-commit-id grep hash-object help history hook index-pack init init-db interpret-trailers last-modified log ls-files ls-remote ls-tree mailinfo mailsplit maintenance merge merge-base merge-file merge-index merge-ours merge-recursive merge-recursive-ours merge-recursive-theirs merge-subtree merge-tree mktag mktree multi-pack-index mv name-rev notes pack-objects pack-redundant pack-refs patch-id pickaxe prune prune-packed pull push range-diff read-tree rebase receive-pack reflog refs remote remote-ext remote-fd repack replace replay repo rerere reset restore rev-list rev-parse revert rm send-pack shortlog show show-branch show-index show-ref sparse-checkout stage stash status stripspace submodule--helper switch symbolic-ref tag unpack-file unpack-objects update-index update-ref update-server-info upload-archive upload-archive--writer upload-pack url-parse var verify-commit verify-pack verify-tag version whatchanged worktree write-tree";
fn isBuiltin(name: []const u8) bool { var it=std.mem.tokenizeScalar(u8,builtinNames,' '); while (it.next()) |n| { if (eq(n,name)) return true; } return false; }
const helpTrailer="'git help -a' and 'git help -g' list available subcommands and some\nconcept guides. See 'git help <command>' or 'git help <concept>'\nto read about a specific subcommand or concept.\nSee 'git help git' for an overview of the system.\n";
fn commonHelp() void {
    out("usage: git [-v | --version] [-h | --help] [-C <path>] [-c <name>=<value>]\n           [--exec-path[=<path>]] [--html-path] [--man-path] [--info-path]\n           [-p | --paginate | -P | --no-pager] [--no-replace-objects] [--no-lazy-fetch]\n           [--no-optional-locks] [--no-advice] [--bare] [--git-dir=<path>]\n           [--work-tree=<path>] [--namespace=<name>] [--config-env=<name>=<envvar>]\n           <command> [<args>]\n\nThese are common Git commands used in various situations:\n\nstart a working area (see also: git help tutorial)\n   clone     Clone a repository into a new directory\n   init      Create an empty Git repository or reinitialize an existing one\n\nwork on the current change (see also: git help everyday)\n   add       Add file contents to the index\n   mv        Move or rename a file, a directory, or a symlink\n   restore   Restore working tree files\n   rm        Remove files from the working tree and from the index\n\nexamine the history and state (see also: git help revisions)\n   bisect    Use binary search to find the commit that introduced a bug\n   diff      Show changes between commits, commit and working tree, etc\n   grep      Print lines matching a pattern\n   log       Show commit logs\n   show      Show various types of objects\n   status    Show the working tree status\n\ngrow, mark and tweak your common history\n   branch    List, create, or delete branches\n   commit    Record changes to the repository\n   merge     Join two or more development histories together\n   rebase    Reapply commits on top of another base tip\n   reset     Reset current HEAD to the specified state\n   switch    Switch branches\n   tag       Create, list, delete or verify a tag object signed with GPG\n\ncollaborate (see also: git help workflows)\n   fetch     Download objects and refs from another repository\n   pull      Fetch from and integrate with another repository or a local branch\n   push      Update remote refs along with associated objects\n\n"); out(helpTrailer);
}
const helpConfigNames="branch.<name>.merge branch.<name>.remote browser.<tool>.cmd core.attributesFile core.autocrlf core.bare core.editor core.eol core.filemode core.ignorecase core.logAllRefUpdates core.pager core.repositoryformatversion core.safecrlf grep.extendedRegexp grep.lineNumber grep.patternType help.browser help.format help.htmlPath init.defaultBranch push.default remote.<name>.fetch remote.<name>.url remote.pushDefault sequence.editor user.email user.name";
fn helpCommand(args: Args) u8 {
    const Mode=enum { common, all, guides, config, completion, sections, interfaces }; var mode: Mode=.common; var modes: usize=0; var page: ?[]const u8=null; var viewer=false; var external=false;
    for (args) |s| { if (eq(s,"-a") or eq(s,"--all")) { mode=.all; modes+=1; } else if (eq(s,"-g") or eq(s,"--guides")) { mode=.guides; modes+=1; } else if (eq(s,"-c") or eq(s,"--config")) { mode=.config; modes+=1; } else if (eq(s,"--config-for-completion")) { mode=.completion; modes+=1; } else if (eq(s,"--config-sections-for-completion")) { mode=.sections; modes+=1; } else if (eq(s,"--user-interfaces")) { mode=.interfaces; modes+=1; }
        else if (eq(s,"-i") or eq(s,"-m") or eq(s,"-w") or eq(s,"--info") or eq(s,"--man") or eq(s,"--web")) viewer=true
        else if (eq(s,"--no-external-commands") or eq(s,"--no-aliases")) external=true
        else if (eq(s,"--no-verbose") or eq(s,"--verbose") or eq(s,"--exclude-guides")) {}
        else if (starts(s,"-")) return 129 else { if (page!=null) return 129; page=s; }
    }
    if (modes>1 or (mode!=.common and (page!=null or viewer)) or (external and mode!=.all)) return 129;
    if (page!=null or viewer) return fatal("documentation viewer is not available");
    switch (mode) {
        .common=>commonHelp(),
        .guides=>{ out("The Git concept guides are:\n\n   everyday    A useful minimum set of commands for Everyday Git\n   tutorial    A tutorial introduction to Git\n   revisions   Specifying revisions and ranges for Git\n   workflows   An overview of recommended workflows with Git\n\n"); out(helpTrailer); },
        .interfaces=>out("The user-facing repository, command and file interfaces are:\n\n   attributes   Defining attributes per path\n   mailmap   Map author/committer names and/or E-Mail addresses\n"),
        .all=>{ out("See 'git help <command>' to read about a specific subcommand\n\n"); for ([_][]const u8{"Main Porcelain Commands","Ancillary Commands / Manipulators","Ancillary Commands / Interrogators","Interacting with Others","Low-level Commands / Manipulators","Low-level Commands / Interrogators","Low-level Commands / Syncing Repositories","Low-level Commands / Internal Helpers","User-facing repository, command and file interfaces","Developer-facing file formats, protocols and other interfaces"},0..) |section,j| { line(section); if (j==0) { var it=std.mem.tokenizeScalar(u8,builtinNames,' '); while (it.next()) |name| line(fmt("   {s}",.{name})); } if (j<9) out("\n"); } },
        .config,.completion,.sections=>{ var names: std.ArrayList([]const u8)=.empty; var it=std.mem.tokenizeScalar(u8,helpConfigNames,' '); while (it.next()) |key| { const name=if (mode==.sections) key[0..std.mem.indexOfScalar(u8,key,'.').?] else if (mode==.completion) key[0..std.mem.indexOfScalar(u8,key,'<') orelse key.len] else key; var found=false; for (names.items) |n| { if (eq(n,name)) found=true; } if (!found) names.append(a,name) catch unreachable; } std.mem.sort([]const u8,names.items,{},struct { fn less(_: void,x: []const u8,y: []const u8) bool { return std.mem.lessThan(u8,x,y); } }.less); for (names.items) |n| line(n); if (mode==.config) out("\n'git help config' for more information\n"); },
    }
    return 0;
}
fn commandUsage(name: []const u8) void {
    line(fmt("usage: git {s} [<options>]",.{name}));
    if (eq(name,"add")) out("\n    -A, --all             add changes from all tracked and untracked files\n    -u, --update          update tracked files\n    --renormalize         renormalize tracked files\n")
    else if (eq(name,"config")) out("\n    --get                 get a value\n    --list                list configuration\n    --file <file>         read or write a configuration file\n")
    else if (eq(name,"checkout")) out("\n    -b <branch>           create and switch to a branch\n    --orphan <branch>     create an unborn branch\n    -- <path>...          restore paths from the index\n")
    else out("\n    -h                    show this help\n");
}
fn helper(args: Args) u8 {
    if (args.len>0 and eq(args[0],"env-helper")) {
        var default: []const u8="false"; var name: []const u8="";
        for (args[1..]) |s| { if (starts(s,"--default=")) default=s[10..] else if (!starts(s,"-")) name=s; }
        const v=lower(env(name) orelse default);
        if (eq(v,"true") or eq(v,"yes") or eq(v,"on") or eq(v,"1")) return 0;
        if (eq(v,"false") or eq(v,"no") or eq(v,"off") or eq(v,"0") or v.len==0) return 1;
        return 128;
    }
    emit(2,"probe test-tool: helper not implemented\n"); return 1;
}
pub export fn main(argc: c_int, argv: [*]const [*:0]const u8) c_int {
    if (env("GIT_TRACE2_EVENT")) |path| { if (starts(path,"/")) appendFile(path,fmt("{{\"event\":\"start\",\"thread\":\"main\",\"argc\":{d}}}\n",.{argc})); }
    overrides=std.StringHashMap([]const u8).init(a);
    const args=a.alloc([]const u8,@intCast(argc)) catch unreachable;
    for (args,0..) |*s,i| s.*=std.mem.span(argv[i]);
    exec_path=std.fs.path.dirname(absolute(args[0])) orelse cwd();
    if (eq(std.fs.path.basename(args[0]),"test-tool")) return helper(args[1..]);
    var i: usize=1; var bare=false;
    while (i<args.len) : (i+=1) {
        const s=args[i];
        if (starts(s,"--list-cmds=")) { var it=std.mem.tokenizeScalar(u8,builtinNames,' '); while (it.next()) |name| line(name); return 0; }
        if (eq(s,"--help") or eq(s,"-h")) return helpCommand(args[i+1..]);
        if (eq(s,"--exec-path")) { line(env("GIT_EXEC_PATH") orelse exec_path); return 0; }
        if (eq(s,"--version")) { line("git version 2.56.1"); return 0; }
        if (eq(s,"--no-pager") or eq(s,"--no-optional-locks")) continue;
        if (eq(s,"--bare")) { bare=true; continue; }
        if (starts(s,"--git-dir=")) { git_dir_arg=s[10..]; continue; }
        if (starts(s,"--work-tree=")) { work_tree_arg=s[12..]; continue; }
        if (eq(s,"--git-dir") or eq(s,"--work-tree")) { i+=1; if (i==args.len) return 129; if (eq(s,"--git-dir")) git_dir_arg=args[i] else work_tree_arg=args[i]; continue; }
        if (eq(s,"-C")) { i+=1; if (i>=args.len) return 129; if (chdir(z(args[i]))!=0) return fatal("cannot change directory"); continue; }
        if (eq(s,"-c") or starts(s,"--config-env=")) {
            const pair=if (eq(s,"-c")) blk: { i+=1; if (i>=args.len) return 129; break :blk args[i]; } else s[13..];
            const n=if (eq(s,"-c")) std.mem.indexOfScalar(u8,pair,'=') orelse pair.len else std.mem.lastIndexOfScalar(u8,pair,'=') orelse return fatal("invalid config-env parameter");
            const key=pair[0..n]; if (!validConfigKey(key)) return fatal(fmt("invalid key: {s}",.{key}));
            const value=if (!eq(s,"-c")) env(pair[n+1..]) orelse return fatal("missing environment variable") else if (n<pair.len) pair[n+1..] else "";
            const implicit=eq(s,"-c") and n==pair.len;
            command_config.append(a,.{.key=canonicalKey(key),.value=value,.implicit=implicit,.origin="command line",.scope="command"}) catch unreachable;
            overrides.put(canonicalKey(key),if (implicit) "true" else value) catch unreachable; continue;
        }
        const rest=args[i+1..];
        if (isBuiltin(s)) { for (rest) |r| { if (eq(r,"-h")) { commandUsage(s); return 0; } } }
        if (eq(s,"help")) return helpCommand(rest);
        if (eq(s,"version")) { line("git version 2.56.1"); for (rest) |r| { if (eq(r,"--build-options")) out("cpu: aarch64\nno commit associated with this build\nsizeof-long: 8\nsizeof-size_t: 8\ndefault-hash: sha1\n"); } return 0; }
        if (eq(s,"init")) return initRepo(rest,bare);
        if (eq(s,"config")) return config(rest);
        if (eq(s,"var")) return variable(rest);
        if (eq(s,"hash-object")) return hashObject(rest);
        if (eq(s,"fast-import")) return fastImport(rest);
        if (eq(s,"clone")) return cloneCommand(rest);
        if (eq(s,"fetch")) return fetchCommand(rest);
        if (eq(s,"fsck") or eq(s,"fsck-objects")) return fsckCommand(rest);
        if (eq(s,"gc")) { for (rest) |r| { if (eq(r,"--auto") and looseObjectNames(objectDirectory() orelse return 128).len<6700) return 0; } return repack(&.{"-ad","-q"}); }
        if (eq(s,"merge")) return mergeCommand(rest);
        if (eq(s,"merge-base")) { var refs: std.ArrayList([]const u8)=.empty; var check=false; for (rest) |r| { if (eq(r,"--is-ancestor")) check=true else if (!starts(r,"-")) refs.append(a,resolve(r) orelse return 128) catch unreachable; } if (refs.items.len<2) return 129; if (check) return if (isAncestor(refs.items[0],refs.items[1])) 0 else 1; line(mergeBaseId(refs.items[0],refs.items[1]) orelse return 1); return 0; }
        if (eq(s,"pack-objects")) return packObjects(rest);
        if (eq(s,"index-pack")) return indexPack(rest);
        if (eq(s,"unpack-objects")) return unpackObjects(rest);
        if (eq(s,"show-index")) return showIndex(rest);
        if (eq(s,"verify-pack")) return verifyPack(rest);
        if (eq(s,"repack")) return repack(rest);
        if (eq(s,"prune-packed")) return prunePacked();
        if (eq(s,"count-objects")) return countObjects(rest);
        if (eq(s,"multi-pack-index")) return multiPackIndex(rest);
        if (eq(s,"cat-file")) return catFile(rest);
        if (eq(s,"rev-parse")) return revParse(rest);
        if (eq(s,"check-ref-format")) { var name: ?[]const u8=null; var single=false; var branch=false; for (rest) |r| { if (eq(r,"--allow-onelevel")) single=true else if (eq(r,"--branch")) { single=true; branch=true; } else if (!starts(r,"--")) name=r; } const n=name orelse return 129; if (!validRef(n,single) or (branch and n[0]=='-')) return 1; if (branch) line(n); return 0; }
        if (eq(s,"update-ref")) return updateRef(rest);
        if (eq(s,"symbolic-ref")) return symbolicRef(rest);
        if (eq(s,"show-ref")) return showRef(rest);
        if (eq(s,"add")) return addCommand(rest);
        if (eq(s,"update-index")) return updateIndex(rest);
        if (eq(s,"mktree")) return mkTree(rest);
        if (eq(s,"grep")) return grepCommand(rest);
        if (eq(s,"status")) return @import("status.zig").run(rest);
        if (eq(s,"log") or eq(s,"rev-list") or eq(s,"show")) return historyCommand(rest,s);
        if (eq(s,"diff") or eq(s,"diff-files") or eq(s,"diff-index") or eq(s,"diff-tree")) return diffCommand(rest,s);
        if (eq(s,"write-tree")) { line(treeFromIndex(readIndex(),"") orelse return 1); return 0; }
        if (eq(s,"commit-tree")) return commitTree(rest);
        if (eq(s,"commit")) return commit(rest);
        if (eq(s,"rm")) return rmCommand(rest);
        if (eq(s,"mv")) return mvCommand(rest);
        if (eq(s,"checkout") or eq(s,"switch")) return checkout(rest);
        if (eq(s,"reset")) return resetCommand(rest);
        if (eq(s,"checkout-index")) { var paths: std.ArrayList([]const u8)=.empty; var all=false; for (rest) |r| { if (eq(r,"-a") or eq(r,"--all")) all=true else if (!starts(r,"-")) paths.append(a,r) catch unreachable; } for (readIndex()) |e| { if (all or pathMatches(e.path,paths.items)) { if (!materialize(e)) return 1; } } return 0; }
        if (eq(s,"branch")) return branchCommand(rest);
        if (eq(s,"tag")) return tagCommand(rest);
        if (eq(s,"ls-tree")) return lsTree(rest);
        if (eq(s,"for-each-ref")) return forEachRef(rest);
        if (eq(s,"refs") and rest.len>0 and eq(rest[0],"list")) return forEachRef(rest[1..]);
        if (eq(s,"remote") and rest.len>=3 and eq(rest[0],"add")) { const file=join(gitdir() orelse return 128,"config"); if (!configSet(file,fmt("remote.{s}.url",.{rest[1]}),rest[2],false)) return 1; return if (configSet(file,fmt("remote.{s}.fetch",.{rest[1]}),fmt("+refs/heads/*:refs/remotes/{s}/*",.{rest[1]}),false)) 0 else 1; }
        if (eq(s,"read-tree")) { var entries: std.ArrayList(IndexEntry)=.empty; for (rest) |r| { if (!starts(r,"-")) { if (!readTreeEntries(r,"",&entries)) return 1; } } return if (writeIndex(entries.items)) 0 else 1; }
        if (eq(s,"ls-files")) return lsFiles(rest);
        if (eq(s,"pack-refs")) { var b: std.ArrayList(u8)=.empty; b.appendSlice(a,"# pack-refs with: peeled fully-peeled sorted\n") catch unreachable; const refs=allRefs(); for (refs) |r| b.appendSlice(a,fmt("{s} {s}\n",.{r.oid,r.name})) catch unreachable; const g=gitdir() orelse return 128; if (!put(join(g,"packed-refs"),b.items)) return 1; for (refs) |r| remove(join(g,r.name)); return 0; }
        if (eq(s,"reflog") and rest.len>=2 and eq(rest[0],"exists")) return if (exists(join(gitdir() orelse return 128,fmt("logs/{s}",.{rest[1]})))) 0 else 1;
        emit(2,fmt("git: '{s}' is not a git command. See 'git --help'.\n",.{s})); return 1;
    }
    commonHelp(); return 1;
}
