const std = @import("std");
const a = std.heap.page_allocator;
extern "c" fn compressBound(c_ulong) c_ulong;
extern "c" fn compress2([*]u8, *c_ulong, [*]const u8, c_ulong, c_int) c_int;
extern "c" fn uncompress2([*]u8, *c_ulong, [*]const u8, *c_ulong) c_int;
extern "c" fn crc32(c_ulong, [*]const u8, c_uint) c_ulong;

pub const Object = struct { typ: []const u8, data: []const u8 };
pub const Record = struct {
    offset: u64, packed_size: usize, kind: u8, payload: []const u8,
    base_offset: ?u64 = null, base_oid: ?[]const u8 = null,
    crc: u32, object: ?Object = null, oid: ?[]const u8 = null, depth: usize = 0,
};
pub const Pack = struct {
    bytes: []const u8, records: []Record, checksum: [20]u8,
    by_oid: std.StringHashMap(usize), by_offset: std.AutoHashMap(u64, usize),
    pub fn resolve(self: *Pack, external: ?*const fn ([]const u8) ?Object) !void {
        var remaining: usize = 0;
        for (self.records) |r| { if (r.object == null) remaining += 1; }
        while (remaining > 0) {
            var progress = false;
            for (self.records, 0..) |*r, i| {
                if (r.object != null) continue;
                var base: ?Object = null; var depth: usize = 1;
                if (r.base_offset) |off| {
                    const index = self.by_offset.get(off) orelse return error.InvalidBase;
                    base = self.records[index].object; depth += self.records[index].depth;
                } else if (r.base_oid) |oid| {
                    if (self.by_oid.get(oid)) |index| { base = self.records[index].object; depth += self.records[index].depth; }
                }
                if (base) |obj| {
                    r.object = .{ .typ = obj.typ, .data = try applyDelta(obj.data, r.payload) };
                    r.oid = hashObject(r.object.?); r.depth = depth;
                    try self.by_oid.put(r.oid.?, i); remaining -= 1; progress = true;
                }
            }
            if (!progress) {
                if (external) |lookup| {
                    for (self.records, 0..) |*r, i| {
                        if (r.object != null) continue;
                        const id = r.base_oid orelse continue;
                        const base = lookup(id) orelse continue;
                        r.object = .{ .typ = base.typ, .data = try applyDelta(base.data, r.payload) };
                        r.oid = hashObject(r.object.?); r.depth = 1;
                        try self.by_oid.put(r.oid.?, i); remaining -= 1; progress = true;
                    }
                }
                if (!progress) return error.UnresolvedDelta;
            }
        }
    }
};
pub fn digest(data: []const u8) [20]u8 { var d: [20]u8 = undefined; std.crypto.hash.Sha1.hash(data, &d, .{}); return d; }
pub fn hex(bytes: [20]u8) []const u8 { return a.dupe(u8, &std.fmt.bytesToHex(bytes, .lower)) catch unreachable; }
pub fn hashObject(obj: Object) []const u8 {
    var state = std.crypto.hash.Sha1.init(.{});
    var buf: [64]u8 = undefined;
    state.update(std.fmt.bufPrint(&buf, "{s} {d}\x00", .{ obj.typ, obj.data.len }) catch unreachable);
    state.update(obj.data); var d: [20]u8 = undefined; state.final(&d); return hex(d);
}
fn readSize(data: []const u8, off: *usize) !usize {
    var size: usize = 0; var shift: usize = 0;
    while (off.* < data.len and shift < @bitSizeOf(usize)) {
        const c = data[off.*]; off.* += 1;
        if (@as(usize, c & 127) > (@as(usize, std.math.maxInt(usize)) >> @intCast(shift))) return error.Overflow;
        size |= @as(usize, c & 127) << @intCast(shift);
        if (c & 128 == 0) return size; shift += 7;
    } return error.InvalidDelta;
}
pub fn applyDelta(base: []const u8, delta: []const u8) ![]const u8 {
    var off: usize = 0; if (try readSize(delta, &off) != base.len) return error.InvalidBaseSize;
    const size = try readSize(delta, &off); if (size > 1024 * 1024 * 1024) return error.ObjectTooLarge;
    const result = try a.alloc(u8, size); errdefer a.free(result); var written: usize = 0;
    while (off < delta.len) {
        const instruction = delta[off]; off += 1;
        if (instruction & 128 != 0) {
            var source: usize = 0; var count: usize = 0;
            for (0..7) |i| { if (instruction & (@as(u8, 1) << @intCast(i)) == 0) continue;
                if (off >= delta.len) return error.TruncatedDelta; const byte = delta[off]; off += 1;
                if (i < 4) source |= @as(usize, byte) << @intCast(i * 8) else count |= @as(usize, byte) << @intCast((i - 4) * 8);
            }
            if (count == 0) count = 0x10000;
            if (source > base.len or count > base.len - source or count > result.len - written) return error.InvalidCopy;
            @memcpy(result[written..][0..count], base[source..][0..count]); written += count;
        } else {
            const count: usize = instruction;
            if (count == 0 or count > delta.len - off or count > result.len - written) return error.InvalidInsert;
            @memcpy(result[written..][0..count], delta[off..][0..count]); written += count; off += count;
        }
    }
    if (written != result.len) return error.InvalidResultSize; return result;
}
pub fn decode(bytes: []const u8) !Pack {
    if (bytes.len < 32 or !std.mem.eql(u8, bytes[0..4], "PACK")) return error.InvalidHeader;
    const version = std.mem.readInt(u32, bytes[4..8], .big);
    if (version != 2 and version != 3) return error.InvalidVersion;
    const checksum = digest(bytes[0..bytes.len - 20]);
    if (!std.mem.eql(u8, &checksum, bytes[bytes.len - 20..])) return error.ChecksumMismatch;
    const count: usize = std.mem.readInt(u32, bytes[8..12], .big);
    if (count > bytes.len - 32) return error.InvalidCount;
    const records = try a.alloc(Record, count);
    var pack = Pack{ .bytes = bytes, .records = records, .checksum = checksum, .by_oid = std.StringHashMap(usize).init(a), .by_offset = std.AutoHashMap(u64, usize).init(a) };
    var off: usize = 12;
    for (records, 0..) |*r, i| {
        const start = off; if (off >= bytes.len - 20) return error.TruncatedPack;
        var c = bytes[off]; off += 1; const kind = (c >> 4) & 7;
        var size: usize = c & 15; var shift: usize = 4;
        while (c & 128 != 0) {
            if (off >= bytes.len - 20 or shift + 7 > @bitSizeOf(usize)) return error.InvalidSize;
            c = bytes[off]; off += 1; size |= @as(usize, c & 127) << @intCast(shift); shift += 7;
        }
        if (size > 1024 * 1024 * 1024) return error.ObjectTooLarge;
        var base_offset: ?u64 = null; var base_oid: ?[]const u8 = null;
        if (kind == 6) {
            if (off >= bytes.len - 20) return error.TruncatedPack;
            c = bytes[off]; off += 1; var distance: usize = c & 127;
            while (c & 128 != 0) { if (off >= bytes.len - 20 or distance > std.math.maxInt(usize) / 128 - 1) return error.InvalidOffset; c = bytes[off]; off += 1; distance = ((distance + 1) << 7) | (c & 127); }
            if (distance == 0 or distance > start - 12) return error.InvalidOffset; base_offset = start - distance;
        } else if (kind == 7) {
            if (off + 20 > bytes.len - 20) return error.TruncatedPack;
            base_oid = hex(bytes[off..][0..20].*); off += 20;
        } else if (kind < 1 or kind > 4) return error.InvalidType;
        const payload = try a.alloc(u8, @max(size, 1)); var dest_len: c_ulong = @intCast(size); var source_len: c_ulong = @intCast(bytes.len - 20 - off);
        if (uncompress2(payload.ptr, &dest_len, bytes[off..].ptr, &source_len) != 0 or dest_len != size) return error.InvalidCompressedData;
        off += @intCast(source_len);
        r.* = .{ .offset = start, .packed_size = off - start, .kind = kind, .payload = payload[0..size], .base_offset = base_offset, .base_oid = base_oid, .crc = @intCast(crc32(0, bytes[start..off].ptr, @intCast(off - start))) };
        try pack.by_offset.put(start, i);
        if (kind >= 1 and kind <= 4) {
            r.object = .{ .typ = typeName(kind), .data = r.payload }; r.oid = hashObject(r.object.?); try pack.by_oid.put(r.oid.?, i);
        }
    }
    if (off != bytes.len - 20) return error.TrailingData; return pack;
}
pub fn typeName(kind: u8) []const u8 { return switch (kind) { 1 => "commit", 2 => "tree", 3 => "blob", 4 => "tag", else => "unknown" }; }
fn typeCode(name: []const u8) u8 { for (1..5) |i| { if (std.mem.eql(u8, name, typeName(@intCast(i)))) return @intCast(i); } return 0; }
pub fn appendInt(list: *std.ArrayList(u8), comptime T: type, value: T) void {
    var bytes: [@sizeOf(T)]u8 = undefined; std.mem.writeInt(T, &bytes, value, .big); list.appendSlice(a, &bytes) catch unreachable;
}
fn appendHeader(list: *std.ArrayList(u8), kind: u8, size: usize) void {
    var n = size >> 4; list.append(a, (@as(u8, kind) << 4) | @as(u8, @intCast(size & 15)) | @as(u8, if (n > 0) 128 else 0)) catch unreachable;
    while (n > 0) { const byte: u8 = @intCast(n & 127); n >>= 7; list.append(a, byte | @as(u8, if (n > 0) 128 else 0)) catch unreachable; }
}
pub const WriteOptions = struct { compression: c_int = -1, deltas: bool = false, ofs_delta: bool = false, index_version: u32 = 2 };
pub fn encode(objects: []const Object, options: WriteOptions) !Pack {
    var bytes: std.ArrayList(u8) = .empty; try bytes.appendSlice(a, "PACK"); appendInt(&bytes, u32, 2); appendInt(&bytes, u32, @intCast(objects.len));
    var offsets: std.ArrayList(usize) = .empty;
    for (objects, 0..) |obj, i| {
        const start = bytes.items.len; var payload = obj.data; var base: ?usize = null;
        if (options.deltas and obj.data.len >= 64) {
            var j = i; var attempts: usize = 0; while (j > 0 and attempts < 10) { j -= 1; attempts += 1;
                if (!std.mem.eql(u8, objects[j].typ, obj.typ)) continue;
                const candidate = makeDelta(objects[j].data, obj.data);
                if (candidate.len + 32 < payload.len) { if (base != null) a.free(payload); payload = candidate; base = j; } else a.free(candidate);
            }
        }
        appendHeader(&bytes, if (base != null) (if (options.ofs_delta) @as(u8, 6) else 7) else typeCode(obj.typ), payload.len);
        if (base) |j| {
            if (options.ofs_delta) {
                var distance = start - offsets.items[j]; var encoded: [16]u8 = undefined; var n: usize = encoded.len - 1; encoded[n] = @intCast(distance & 127);
                while (distance > 127) { distance = (distance >> 7) - 1; n -= 1; encoded[n] = @as(u8, @intCast(distance & 127)) | 128; }
                try bytes.appendSlice(a, encoded[n..]);
            } else { const id = hashObject(objects[j]); var digest_bytes: [20]u8 = undefined; _ = try std.fmt.hexToBytes(&digest_bytes, id); try bytes.appendSlice(a, &digest_bytes); }
        }
        var length = compressBound(@intCast(payload.len)); const compressed = try a.alloc(u8, @intCast(length));
        if (compress2(compressed.ptr, &length, payload.ptr, @intCast(payload.len), options.compression) != 0) return error.CompressionFailed;
        try bytes.appendSlice(a, compressed[0..@intCast(length)]); a.free(compressed); try offsets.append(a, start);
    }
    const sum = digest(bytes.items); try bytes.appendSlice(a, &sum); var pack = try decode(try bytes.toOwnedSlice(a)); try pack.resolve(null); return pack;
}
fn appendVarint(b: *std.ArrayList(u8), value: usize) void {
    var n = value; while (true) { const byte: u8 = @intCast(n & 127); n >>= 7; b.append(a, byte | @as(u8, if (n > 0) 128 else 0)) catch unreachable; if (n == 0) break; }
}
pub fn makeDelta(base: []const u8, target: []const u8) []const u8 {
    var prefix: usize = 0; while (prefix < @min(base.len, target.len) and base[prefix] == target[prefix]) : (prefix += 1) {}
    var suffix: usize = 0; while (suffix < @min(base.len, target.len) - prefix and base[base.len - suffix - 1] == target[target.len - suffix - 1]) : (suffix += 1) {}
    var b: std.ArrayList(u8) = .empty; appendVarint(&b, base.len); appendVarint(&b, target.len);
    appendCopy(&b, 0, prefix); var off = prefix; const end = target.len - suffix;
    while (off < end) { const n = @min(127, end - off); b.append(a, @intCast(n)) catch unreachable; b.appendSlice(a, target[off..][0..n]) catch unreachable; off += n; }
    appendCopy(&b, base.len - suffix, suffix); return b.toOwnedSlice(a) catch unreachable;
}
fn appendCopy(b: *std.ArrayList(u8), source: usize, length: usize) void {
    var offset = source; var remaining = length; while (remaining > 0) {
        const count = @min(remaining, 0xffffff); var command: u8 = 128; var args: std.ArrayList(u8) = .empty;
        for (0..4) |i| { const c: u8 = @truncate(offset >> @intCast(i * 8)); if (c != 0) { command |= @as(u8, 1) << @intCast(i); args.append(a, c) catch unreachable; } }
        for (0..3) |i| { const c: u8 = @truncate(count >> @intCast(i * 8)); if (c != 0) { command |= @as(u8, 1) << @intCast(i + 4); args.append(a, c) catch unreachable; } }
        b.append(a, command) catch unreachable; b.appendSlice(a, args.items) catch unreachable; offset += count; remaining -= count;
    }
}
pub fn encodeIndex(pack: Pack, version: u32) ![]const u8 {
    return encodeIndexThreshold(pack, version, 0x80000000);
}
pub fn encodeIndexThreshold(pack: Pack, version: u32, threshold: u64) ![]const u8 {
    if (version != 1 and version != 2) return error.InvalidIndexVersion;
    const sorted = try a.alloc(usize, pack.records.len); for (sorted, 0..) |*index, i| index.* = i;
    std.mem.sort(usize, sorted, pack.records, struct { fn less(records: []Record, x: usize, y: usize) bool { return std.mem.lessThan(u8, records[x].oid.?, records[y].oid.?); } }.less);
    var b: std.ArrayList(u8) = .empty; if (version == 2) { try b.appendSlice(a, "\xfftOc"); appendInt(&b, u32, 2); }
    var cumulative: u32 = 0; var index: usize = 0;
    for (0..256) |first| { while (index < sorted.len) { const oid = pack.records[sorted[index]].oid orelse return error.UnresolvedDelta; const byte = try std.fmt.parseInt(u8, oid[0..2], 16); if (byte > first) break; cumulative += 1; index += 1; } appendInt(&b, u32, cumulative); }
    for (sorted) |i| { const r = pack.records[i]; if (version == 1) { if (r.offset > std.math.maxInt(u32)) return error.OffsetTooLarge; appendInt(&b, u32, @intCast(r.offset)); } var id: [20]u8 = undefined; _ = try std.fmt.hexToBytes(&id, r.oid.?); try b.appendSlice(a, &id); }
    if (version == 2) {
        for (sorted) |i| appendInt(&b, u32, pack.records[i].crc);
        var large: u32 = 0; for (sorted) |i| { const off = pack.records[i].offset; if (off >= @min(threshold, 0x80000000)) { appendInt(&b, u32, 0x80000000 | large); large += 1; } else appendInt(&b, u32, @intCast(off)); }
        for (sorted) |i| { const off = pack.records[i].offset; if (off >= @min(threshold, 0x80000000)) appendInt(&b, u64, off); }
    }
    try b.appendSlice(a, &pack.checksum); const sum = digest(b.items); try b.appendSlice(a, &sum); return b.toOwnedSlice(a);
}
test "pack round trips preserve objects and resolve both delta representations" {
    const base = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz";
    const changed = "abcdefghijklmnopqrstuvwxyzXYZabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz";
    const objects = [_]Object{ .{ .typ = "blob", .data = base }, .{ .typ = "blob", .data = changed }, .{ .typ = "blob", .data = "" } };
    for ([_]bool{ false, true }) |ofs| {
        const pack = try encode(&objects, .{ .deltas = true, .ofs_delta = ofs });
        try std.testing.expectEqual(@as(usize, 3), pack.records.len);
        try std.testing.expectEqual(@as(u8, if (ofs) 6 else 7), pack.records[1].kind);
        for (objects, 0..) |obj, i| { try std.testing.expectEqualStrings(obj.data, pack.records[i].object.?.data); try std.testing.expectEqualStrings(hashObject(obj), pack.records[i].oid.?); }
        for ([_]u32{ 1, 2 }) |version| { const index = try encodeIndex(pack, version); try std.testing.expectEqualSlices(u8, &digest(index[0..index.len - 20]), index[index.len - 20..]); }
        const corrupt = try a.dupe(u8, pack.bytes); corrupt[12] ^= 1; try std.testing.expectError(error.ChecksumMismatch, decode(corrupt));
    }
}
test "delta decoder rejects invalid sizes, zero opcodes and out-of-bounds copies" {
    try std.testing.expectError(error.InvalidBaseSize, applyDelta("a", &.{ 2, 1, 1, 'x' }));
    try std.testing.expectError(error.InvalidInsert, applyDelta("a", &.{ 1, 1, 0 }));
    try std.testing.expectError(error.InvalidCopy, applyDelta("a", &.{ 1, 2, 0x90, 2 }));
    try std.testing.expectError(error.TruncatedDelta, applyDelta("a", &.{ 1, 1, 0x91 }));
}
pub const BitmapEntry = struct { index: u32, words: []const u64 };
pub const Bitmap = struct { checksum: [20]u8, bit_size: usize, types: [4][]u64, entries: std.AutoHashMap(u32, []u64) };
fn appendEwah(b: *std.ArrayList(u8), words: []const u64, bits: usize) void {
    appendInt(b, u32, @intCast(bits)); appendInt(b, u32, @intCast(words.len + 1));
    appendInt(b, u64, @as(u64, @intCast(words.len)) << 33); for (words) |w| appendInt(b, u64, w); appendInt(b, u32, 0);
}
pub fn encodeBitmap(pack: Pack, entries: []const BitmapEntry, lookup: bool) ![]const u8 {
    var b: std.ArrayList(u8) = .empty; try b.appendSlice(a, "BITM"); appendInt(&b, u16, 1); appendInt(&b, u16, 1 | @as(u16, if (lookup) 16 else 0)); appendInt(&b, u32, @intCast(entries.len)); try b.appendSlice(a, &pack.checksum);
    for (1..5) |kind| { const words = try a.alloc(u64, (pack.records.len + 63) / 64); @memset(words, 0); for (pack.records, 0..) |r, i| { if (std.mem.eql(u8, r.object.?.typ, typeName(@intCast(kind)))) words[i / 64] |= @as(u64, 1) << @intCast(i % 64); } appendEwah(&b, words, pack.records.len); }
    const offsets = try a.alloc(u64, entries.len);
    for (entries, 0..) |entry, i| { offsets[i] = b.items.len; appendInt(&b, u32, entry.index); try b.appendSlice(a, &.{ 0, 1 }); appendEwah(&b, entry.words, pack.records.len); }
    if (lookup) {
        const order = try a.alloc(usize, entries.len); for (order, 0..) |*v, i| v.* = i;
        std.mem.sort(usize, order, entries, struct { fn less(items: []const BitmapEntry, x: usize, y: usize) bool { return items[x].index < items[y].index; } }.less);
        for (order) |i| { appendInt(&b, u32, entries[i].index); appendInt(&b, u64, offsets[i]); appendInt(&b, u32, 0xffffffff); }
    }
    const sum = digest(b.items); try b.appendSlice(a, &sum); return b.toOwnedSlice(a);
}
fn readEwah(data: []const u8, off: *usize) ![]u64 {
    if (off.* + 8 > data.len) return error.TruncatedBitmap;
    const bits: usize = std.mem.readInt(u32, data[off.*..][0..4], .big); const compressed: usize = std.mem.readInt(u32, data[off.* + 4..][0..4], .big); off.* += 8;
    if (compressed > (data.len - off.*) / 8 or compressed * 8 + 4 > data.len - off.* or bits > 100_000_000) return error.InvalidBitmap;
    const words = try a.alloc(u64, (bits + 63) / 64); @memset(words, 0); var output: usize = 0; var i: usize = 0;
    while (i < compressed) {
        const rlw = std.mem.readInt(u64, data[off.* + i * 8..][0..8], .big); i += 1;
        const run: usize = @intCast((rlw >> 1) & 0xffffffff); const literals: usize = @intCast(rlw >> 33);
        if (run > words.len - output or literals > words.len - output - run or literals > compressed - i) return error.InvalidBitmap;
        @memset(words[output..][0..run], if (rlw & 1 == 1) std.math.maxInt(u64) else 0); output += run;
        for (0..literals) |_| { words[output] = std.mem.readInt(u64, data[off.* + i * 8..][0..8], .big); output += 1; i += 1; }
    }
    const rlw_position = std.mem.readInt(u32, data[off.* + compressed * 8..][0..4], .big); if (rlw_position >= compressed) return error.InvalidBitmap;
    off.* += compressed * 8 + 4; return words;
}
pub fn decodeBitmap(data: []const u8) !Bitmap {
    if (data.len < 52 or !std.mem.eql(u8, data[0..4], "BITM") or std.mem.readInt(u16, data[4..6], .big) != 1) return error.InvalidBitmap;
    if (!std.mem.eql(u8, &digest(data[0..data.len - 20]), data[data.len - 20..])) return error.ChecksumMismatch;
    const flags = std.mem.readInt(u16, data[6..8], .big); if (flags & 1 == 0) return error.InvalidBitmap;
    const count: usize = std.mem.readInt(u32, data[8..12], .big); var off: usize = 32;
    var bitmap = Bitmap{ .checksum = data[12..32].*, .bit_size = 0, .types = undefined, .entries = std.AutoHashMap(u32, []u64).init(a) };
    for (&bitmap.types) |*words| words.* = try readEwah(data[0..data.len - 20], &off);
    const previous = try a.alloc([]u64, count);
    for (0..count) |i| {
        if (off + 6 > data.len - 20) return error.TruncatedBitmap;
        const index = std.mem.readInt(u32, data[off..][0..4], .big); const xor: usize = data[off + 4]; off += 6;
        if (xor > 160 or xor > i) return error.InvalidBitmap;
        var words = try readEwah(data[0..data.len - 20], &off);
        if (xor > 0) { const base = previous[i - xor]; if (base.len > words.len) { const expanded = try a.alloc(u64, base.len); @memset(expanded, 0); @memcpy(expanded[0..words.len], words); words = expanded; } for (base, 0..) |w, j| words[j] ^= w; }
        previous[i] = words; try bitmap.entries.put(index, words);
    }
    return bitmap;
}
test "bitmap EWAH and lookup extension round trip" {
    const objects = [_]Object{ .{ .typ = "blob", .data = "blob" }, .{ .typ = "tree", .data = "" } };
    const pack = try encode(&objects, .{}); const entries = [_]BitmapEntry{ .{ .index = 0, .words = &.{3} } };
    for ([_]bool{ false, true }) |lookup| { const bytes = try encodeBitmap(pack, &entries, lookup); const decoded = try decodeBitmap(bytes); try std.testing.expectEqualSlices(u8, &pack.checksum, &decoded.checksum); try std.testing.expectEqual(@as(u64, 3), decoded.entries.get(0).?[0]); try std.testing.expectEqual(@as(u64, 1), decoded.types[2][0]); }
}
