# Git to Zig

Reimplement git in Zig as a drop-in replacement for the `git` binary. The C source for git v2.56.1 is at `/home/workspace/git-src/`: read it, understand it, and rewrite it. Your binary must behave identically to the real `git`: same CLI interface, same output formats, same exit codes, and the same repository state on disk.

Your workspace is `/home/workspace/zig-port/` with a build scaffold that already compiles and links zlib. `zig build` produces `zig-out/bin/git`.

Ship only Zig source. Do not leave C, C++, assembly or Rust files, object files, archives, shared libraries or any other prebuilt binary anywhere in the tree.

No internet. Do not compile, link, or translate the C source; write Zig. Work autonomously, do not ask user for input.
