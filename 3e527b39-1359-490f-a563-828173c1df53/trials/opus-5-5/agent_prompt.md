## Iterative Evaluation Mode

You are working with iterative test feedback. After implementing code, you can submit your work for evaluation at any time to see which tests pass and which fail, then iterate based on the results.

### How to Test Your Code

- Run `sforge-submit` to submit your current code for evaluation. It will package the files, send them to the judge server, and return results showing score, pass rate, and a summary of findings.
- Run `sforge-submit --details` to submit and see detailed per-test results.
- Run `sforge-submit --list` to view all previous submissions and their scores for this run.

You should use these regularly to check your progress and identify issues.

### Submitted Files

Only the following paths are submitted for evaluation: `zig-port`

**Keep these files in a compilable/runnable state at all times.** A background process periodically auto-evaluates your code — if the submitted files are broken, incomplete, or contain syntax errors at that moment, the auto-evaluation will fail. Write changes to disk promptly and ensure the submitted files always represent your current best solution.

### Submission Limits

- There is a **minimum interval of 1800s** between submissions.

### Network Environment

**This environment has NO internet access.** Only the judge server and the AI API are reachable. Do not attempt to download packages, fetch remote resources, or access external URLs — all dependencies are pre-installed in the workspace.

### Strategy

- **Implement incrementally**: Complete one module/project at a time
- **Read test feedback carefully**: Failed test names often hint at what's broken
- **Iterate**: Fix failing tests based on the feedback, then submit again

### Scoring

- Your **best score** across all submissions is your final score
- You don't lose points for failed attempts — experimentation is encouraged

---

# Git to Zig

Reimplement git in Zig as a drop-in replacement for the `git` binary. The C source for git v2.56.1 is at `/home/workspace/git-src/`: read it, understand it, and rewrite it. Your binary must behave identically to the real `git`: same CLI interface, same output formats, same exit codes, and the same repository state on disk.

Your workspace is `/home/workspace/zig-port/` with a build scaffold that already compiles and links zlib. `zig build` produces `zig-out/bin/git`.

Ship only Zig source. Do not leave C, C++, assembly or Rust files, object files, archives, shared libraries or any other prebuilt binary anywhere in the tree.

No internet. Do not compile, link, or translate the C source; write Zig. Work autonomously, do not ask user for input.
