//! Build scaffold. This is not an implementation of git: it proves only that the toolchain
//! builds and that zlib is linked and callable. Replace it.

const std = @import("std");

// Declared rather than imported from zlib.h, so the scaffold needs no C header translation.
// The call still forces the linker to resolve the symbol from -lz, which is the proof wanted.
extern fn zlibVersion() [*:0]const u8;

pub fn main() void {
    const version = std.mem.span(zlibVersion());
    std.debug.print("scaffold: zig build works, zlib {s} linked\n", .{version});
    std.debug.print("scaffold: nothing is implemented yet\n", .{});
    std.process.exit(1);
}
