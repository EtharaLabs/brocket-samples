const std = @import("std");
const Parser = @import("refparse.zig").Parser;
const g = @import("main.zig").refApi;
const a = g.allocator;
const eq = g.equal;
const fmt = g.format;
const zero = "0000000000000000000000000000000000000000";
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" fn rmdir([*:0]const u8) c_int;
pub const Options = struct { nul: bool, noderef: bool, message: []const u8, logmode: i8, batch: bool };
const Kind = enum { update, create, delete, verify, @"symref-update", @"symref-create", @"symref-delete", @"symref-verify" };
const Update = struct { kind: Kind, name: []const u8, target: []const u8, value: ?[]const u8 = null, old: ?[]const u8 = null, oldref: ?[]const u8 = null, noderef: bool, previous: []const u8 = zero, rejected: bool = false };
var locks: std.ArrayList([]const u8) = .empty;
pub fn ownsLock(name: []const u8) bool { for (locks.items) |n| { if (eq(n,name)) return true; } return false; }
fn unlock(repo: []const u8) void {
    for (locks.items) |n| {
        g.removeFile(g.pathJoin(repo,fmt("{s}.lock",.{n})));
        var parent=std.fs.path.dirname(n);
        while (parent) |p| {
            if (eq(p,"refs") or eq(p,"refs/heads") or eq(p,"refs/tags")) break;
            const path=g.pathJoin(repo,p); const terminated=a.allocSentinel(u8,path.len,0) catch unreachable; @memcpy(terminated,path);
            if (rmdir(terminated)!=0) break;
            parent=std.fs.path.dirname(p);
        }
    }
    locks.clearRetainingCapacity();
}
fn symbolic(kind: Kind) bool { return switch (kind) { .@"symref-update", .@"symref-create", .@"symref-delete", .@"symref-verify" => true, else => false }; }
fn deleting(kind: Kind) bool { return kind == .delete or kind == .@"symref-delete"; }
fn verifying(kind: Kind) bool { return kind == .verify or kind == .@"symref-verify"; }
fn creating(kind: Kind) bool { return kind == .create or kind == .@"symref-create"; }


fn check(repo: []const u8, u: *Update) ?[]const u8 {
    const current = g.objectId(u.target);
    const raw = g.readFile(g.pathJoin(repo,u.target));
    const ref = if (raw) |r| (if (g.startsWith(r,"ref: ")) std.mem.trim(u8,r[5..]," \t\r\n") else null) else null;
    u.previous = current orelse zero;
    if (u.oldref) |expected| {
        const actual = ref orelse return if (raw == null) fmt("cannot lock ref '{s}': unable to resolve reference '{s}'",.{u.target,u.target}) else fmt("cannot lock ref '{s}': expected symref with target '{s}': but is a regular ref",.{u.target,expected});
        if (!eq(actual,expected)) return fmt("verifying symref target: '{s}': is at {s} but expected {s}",.{u.target,actual,expected});
    }
    if (creating(u.kind) and raw != null and ref!=null and current==null) return fmt("cannot lock ref '{s}': dangling symref already exists",.{u.target});
    if (creating(u.kind) and current != null) return fmt("cannot lock ref '{s}': reference already exists",.{u.target});
    if (!deleting(u.kind) and !verifying(u.kind)) for (g.references()) |r| {
        if (g.startsWith(r.name,fmt("{s}/",.{u.target})) or g.startsWith(u.target,fmt("{s}/",.{r.name}))) return fmt("cannot lock ref '{s}': '{s}' exists; cannot create '{s}'",.{u.target,r.name,u.target});
    };
    if (u.old) |expected| { if (!eq(expected,u.previous)) {
        if (current == null) return if (ref != null and u.noderef) fmt("cannot lock ref '{s}': reference is missing but expected {s}",.{u.name,expected}) else fmt("cannot lock ref '{s}': unable to resolve reference '{s}'",.{u.name,u.target});
        if (eq(expected,zero)) return fmt("cannot lock ref '{s}': reference already exists",.{u.target});
        return fmt("cannot lock ref '{s}': is at {s} but expected {s}",.{u.target,u.previous,expected});
    } }
    if (!symbolic(u.kind) and !deleting(u.kind) and !verifying(u.kind)) {
        const value = u.value.?;
        if (!eq(value,zero)) {
            const obj = g.object(value) orelse return fmt("trying to write ref '{s}' with nonexistent object {s}",.{u.target,value});
            if (g.startsWith(u.target,"refs/heads/") and !eq(obj.typ,"commit")) return fmt("trying to write non-commit object {s} to branch '{s}'",.{value,u.target});
        }
    }
    return null;
}

fn prepare(repo: []const u8, updates: []Update, batch: bool) ?[]const u8 {
    for (updates,0..) |*u,i| {
        for (updates[0..i]) |prior| {
            if (eq(prior.target,u.target)) {
                if (!eq(u.name,u.target)) return fmt("multiple updates for '{s}' (including one via symref '{s}') are not allowed",.{u.target,u.name});
                if (!eq(prior.name,prior.target)) return fmt("multiple updates for '{s}' (including one via symref '{s}') are not allowed",.{u.target,prior.name});
                return fmt("multiple updates for ref '{s}' not allowed",.{u.target});
            }
            if (eq(u.target,"HEAD") or eq(prior.target,"HEAD")) {
                const referent=g.dereference(repo,"HEAD") orelse "HEAD";
                if (eq(u.target,referent) or eq(prior.target,referent)) return fmt("multiple updates for 'HEAD' (including one via its referent '{s}') are not allowed",.{referent});
            }
        }
        if (check(repo,u)) |err| {
            if (!batch) return err;
            const reason=if (std.mem.indexOf(u8,err,"nonexistent object")!=null or std.mem.indexOf(u8,err,"non-commit object")!=null) "invalid new value provided"
                else if (std.mem.indexOf(u8,err,"cannot create")!=null) "refname conflict"
                else if (std.mem.indexOf(u8,err,"but is a regular ref")!=null) "expected symref but found regular ref"
                else if (std.mem.indexOf(u8,err,"reference already exists")!=null) "reference already exists"
                else if (std.mem.indexOf(u8,err,"unable to resolve")!=null or std.mem.indexOf(u8,err,"reference is missing")!=null) "reference does not exist"
                else "incorrect old value provided";
            g.printError(2,fmt("error: {s}\n",.{err}));
            g.printLine(fmt("rejected {s} {s} {s} {s}",.{u.target,if (symbolic(u.kind)) zero else u.value orelse zero,u.old orelse zero,reason}));
            u.rejected=true; continue;
        }
        // Exclusive lock creation, immediately closed: large transactions do not exhaust descriptors.
        const path = g.pathJoin(repo,fmt("{s}.lock",.{u.target}));
        if (std.fs.path.dirname(path)) |parent| g.makePath(parent);
        const terminated = a.allocSentinel(u8,path.len,0) catch unreachable;
        @memcpy(terminated,path);
        const file = fopen(terminated,"wx") orelse return fmt("cannot lock ref '{s}': File exists",.{u.target});
        _ = fclose(file); locks.append(a,u.target) catch unreachable;
    }
    return null;
}

fn commit(repo: []const u8, updates: []Update, opts: Options) u8 {
    for (updates) |u| {
        if (verifying(u.kind) or u.rejected) continue;
        if (symbolic(u.kind) and !deleting(u.kind)) {
            const lockpath=g.pathJoin(repo,fmt("{s}.lock",.{u.target}));
            if (!g.writeFile(lockpath,fmt("ref: {s}\n",.{u.value.?}))) return g.fail("unable to write symbolic reference");
            const source=a.allocSentinel(u8,lockpath.len,0) catch unreachable; @memcpy(source,lockpath);
            const destination=g.pathJoin(repo,u.target); const dest=a.allocSentinel(u8,destination.len,0) catch unreachable; @memcpy(dest,destination);
            if (std.c.rename(source,dest)!=0) return g.fail("unable to commit symbolic reference");
            const setting = g.setting("core.logallrefupdates") orelse "false";
            const logpath = g.pathJoin(repo,fmt("logs/{s}",.{u.target}));
            if (opts.logmode == 1 or (opts.logmode != -1 and (eq(setting,"always") or (eq(setting,"true") and g.startsWith(u.target,"refs/heads/")))) or g.readFile(logpath) != null) {
                g.append(logpath,fmt("{s} {s} {s}\t{s}\n",.{u.previous,g.objectId(u.value.?) orelse zero,g.identity(true) orelse "unknown <unknown> 0 +0000",opts.message}));
            }
        } else {
            const rc = g.update(u.name,if (deleting(u.kind)) null else u.value,null,u.noderef,opts.message,opts.logmode);
            if (rc != 0) return rc;
        }
        if (!eq(u.name,u.target) and !eq(u.name,"HEAD") and !deleting(u.kind)) {
            g.append(g.pathJoin(repo,fmt("logs/{s}",.{u.name})),fmt("{s} {s} {s}\t{s}\n",.{u.previous,g.objectId(u.name) orelse zero,g.identity(true) orelse "unknown <unknown> 0 +0000",opts.message}));
        }
    }
    return 0;
}

pub fn run(opts: Options) u8 {
    const repo = g.repository() orelse return g.fail("not a git repository");
    defer unlock(repo);
    var updates: std.ArrayList(Update) = .empty;
    const State = enum { implicit, active, prepared, closed };
    var state: State = .implicit;
    var explicit = false;
    var noderef = opts.noderef;
    while (g.record(if (opts.nul) 0 else '\n')) |text| {
        if (text.len == 0) return g.fail("empty command in input");
        if (std.ascii.isWhitespace(text[0])) return g.fail(fmt("whitespace before command: {s}",.{text}));
        var parser = Parser{.text=text};
        const cmd = parser.next().?;
        if (state == .prepared and !eq(cmd,"commit") and !eq(cmd,"abort")) return g.fail("prepared transactions can only be closed");
        if (eq(cmd,"start")) {
            if (state == .active or updates.items.len > 0) return g.fail("cannot restart ongoing transaction");
            state = .active; explicit = true; g.printLine("start: ok"); continue;
        }
        if (state == .closed) return g.fail("transaction is closed");
        if (eq(cmd,"prepare") or eq(cmd,"commit") or eq(cmd,"abort")) {
            if (!eq(cmd,"abort") and state != .prepared) { if (prepare(repo,updates.items,opts.batch)) |err| return g.fail(err); }
            if (eq(cmd,"prepare")) state = .prepared else {
                if (eq(cmd,"commit")) { const rc=commit(repo,updates.items,opts); if (rc != 0) return rc; }
                unlock(repo); updates.clearRetainingCapacity(); state = .closed;
            }
            g.printLine(fmt("{s}: ok",.{cmd})); continue;
        }
        if (eq(cmd,"option")) {
            const option = parser.next() orelse "";
            if (!eq(option,"no-deref")) return g.fail(fmt("option unknown: {s}",.{option}));
            noderef = true; continue;
        }
        const kind = std.meta.stringToEnum(Kind,cmd) orelse return g.fail(fmt("unknown command: {s}",.{text}));
        const name = parser.next() orelse { return g.fail(parser.err orelse fmt("{s}: missing <ref>",.{cmd})); };
        if (name.len == 0) return g.fail(fmt("{s}: missing <ref>",.{cmd}));
        if (!g.validName(name,true)) return g.fail(fmt("invalid ref format: {s}",.{name}));
        if ((kind == .@"symref-delete" or kind == .@"symref-verify") and !noderef) return g.fail(fmt("{s}: cannot operate with deref mode",.{cmd}));
        const prefix = fmt("{s} {s}",.{cmd,name});
        var u = Update{.kind=kind,.name=name,.target=if (noderef) name else g.dereference(repo,name) orelse name,.noderef=noderef};
        var values: [3]?[]const u8 = .{null,null,null};
        const count: usize = if (kind == .update) 2 else if (kind == .@"symref-update") 3 else 1;
        for (0..count) |j| {
            values[j] = if (opts.nul) g.record(0) else parser.next();
            if (parser.err) |err| return g.fail(err);
            if (opts.nul and values[j] == null) {
                // symref-update's old-target form is optional, even in NUL mode.
                if (kind == .@"symref-update" and j > 0) break;
                return g.fail(fmt("{s}: unexpected end of input when reading <{s}>",.{prefix,if (j==0 and !deleting(kind) and !verifying(kind)) "new-oid" else "old-oid"}));
            }
            if (kind == .@"symref-update" and j == 1 and (values[j] == null or values[j].?.len == 0)) break;
        }
        if (!opts.nul) { const extraStart = parser.pos; if (parser.next() != null) return g.fail(fmt("{s}: extra input: {s}",.{prefix,text[extraStart..]})); }
        if (symbolic(kind)) {
            if (deleting(kind) or verifying(kind)) { if (values[0]) |v| { if (v.len > 0) u.oldref=v; } if (verifying(kind) and u.oldref==null) u.old=zero; }
            else {
                u.value = values[0]; if (u.value == null or u.value.?.len == 0) return g.fail(fmt("{s}: missing <new-target>",.{prefix}));
                if (!g.validName(u.value.?,true)) return g.fail(fmt("{s}: invalid ref: {s}",.{prefix,u.value.?}));
                if (creating(kind)) u.old=zero;
                if (values[1]) |mode| { if (mode.len>0) {
                    const v=values[2] orelse return g.fail(fmt("{s}: missing old value",.{prefix}));
                    if (eq(mode,"ref")) { if (v.len==0) return g.fail("missing old target"); u.oldref=v; }
                    else if (eq(mode,"oid")) u.old=g.objectId(v) orelse return g.fail(fmt("{s}: invalid oid: {s}",.{prefix,v}))
                    else return g.fail(fmt("{s}: invalid arg '{s}' for old value",.{prefix,mode}));
                } }
            }
        } else {
            if (deleting(kind) or verifying(kind)) {
                if (values[0]) |v| { if (v.len>0) u.old=g.objectId(v) orelse return g.fail(fmt("{s}: invalid <old-oid>: {s}",.{prefix,v})); }
                if (verifying(kind) and u.old==null) u.old=zero;
                if (deleting(kind) and u.old!=null and eq(u.old.?,zero)) return g.fail(fmt("{s}: zero <old-oid>",.{prefix}));
            } else {
                const v=values[0] orelse return g.fail(fmt("{s}: missing <new-oid>",.{prefix}));
                if (v.len==0 and creating(kind)) return g.fail(fmt("{s}: missing <new-oid>",.{prefix}));
                u.value=if (v.len==0) zero else g.objectId(v) orelse return g.fail(fmt("{s}: invalid <new-oid>: {s}",.{prefix,v}));
                if (opts.nul and v.len==0) g.printError(2,fmt("warning: {s}: missing <new-oid>, treating as zero\n",.{prefix}));
                if (creating(kind)) { if (eq(u.value.?,zero)) return g.fail(fmt("{s}: zero <new-oid>",.{prefix})); u.old=zero; }
                else if (values[1]) |old| { if (old.len>0) u.old=g.objectId(old) orelse return g.fail(fmt("{s}: invalid <old-oid>: {s}",.{prefix,old})); }
            }
        }
        for (updates.items) |prior| { if (eq(prior.name,name)) return g.fail(fmt("multiple updates for ref '{s}' not allowed",.{name})); }
        updates.append(a,u) catch unreachable;
        noderef=opts.noderef;
    }
    if (!explicit and state == .implicit) {
        if (prepare(repo,updates.items,opts.batch)) |err| return g.fail(err);
        return commit(repo,updates.items,opts);
    }
    return 0;
}
